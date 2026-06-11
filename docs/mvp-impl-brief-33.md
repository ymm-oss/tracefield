# 実装ブリーフ 33 — ポリシー cascade（多層解決 + per-key 来歴 + 散在フラグの吸収）

> codex 指示（第33弾）。前提: brief-32 まで（180 tests）。設計者: Claude。
> `mise exec -- mix ...`。ネット不可。tracefield リポジトリに git commit しない。mise.toml に触れない。
> 着手前に必読: `lib/mix/tasks/tracefield.dev.ex`（parse_args / run_dev 冒頭 / seed_git_policy! / warn_uncovered_chunks!）/
> `lib/tracefield/workspace.ex`（load! の git セクション解釈）/ `test/dev_task_test.exs`。
> 核心: 作業様式の決定を「散在するフラグ既定値」から「**多層 cascade で解決され、どの層が勝ったかまで来歴に残る
> ポリシー**」に昇格させる。挙動の既定は現行と完全一致（全ファイル不在・全フラグ未指定 = 今日の動作）。

## 1. `Tracefield.Policy`（新モジュール、純粋）

- `resolve(layers)` — 層のリスト（`[{source_atom, map}]`、優先度昇順）を受け取り、
  **深いマージ**（map はキー単位で再帰マージ、スカラ/リストは上書き）で実効ポリシーを構築。
  併せて **per-key 来歴** `%{"coverage.mode" => :cli, "git.mode" => :issue, ...}`（flatten したキー → 勝った source）を返す:
  `{effective_map, provenance_map}`。
- `load_layers!(issue_dir, cli_policy_map)` — 以下の4層を順に読み、存在しないファイルは空 map:
  1. `:default` — コード内既定（下記 §2 の全キーの現行既定値）
  2. `:org` — 環境変数 `TRACEFIELD_ORG_POLICY` が指す JSON ファイル（未設定なら層なし）
  3. `:repo` — workspace 設定がある場合のみ `<workspace path>/.tracefield/policy.json`
  4. `:issue` — `<issue_dir>/policy.json`（存在すれば）＋ 互換: workspace.json の `"git"` セクションは
     issue 層の `git` キーとして読む（既存設定を壊さない。policy.json と両方ある場合は policy.json が勝つ）
  5. `:cli` — cli_policy_map（dev タスクが明示指定されたフラグのみから構築。**未指定フラグは含めない** —
     既定値で上書きすると cascade が壊れるため）
- **検証**: 各ファイルの top-level キーは §2 の既知セクションのみ許可。未知キーは `Mix.raise`
  （typo の静かな無視を防ぐ。`embed_module!` の先例）。値の型・許容値の検証は既存の検証関数に委譲できる形でよい。

## 2. ポリシーのキー空間 v1（現行フラグの吸収）

```json
{
  "coverage": {"mode": "absolute", "threshold": 0.2},
  "embed": "mock",
  "recruit": false,
  "rounds": 2,
  "git": { ...brief-31/32 の git セクションと同形... }
}
```

- 既定値は**現行の既定と完全一致**（mode absolute / threshold 0.2 / embed mock / recruit false / rounds 2 / git.mode current）。
- adapter / model / temperature / cli_cmd は**対象外**（実行機構でありポリシーではない。本ブリーフで触らない）。

## 3. dev タスク統合

- `run_dev` 冒頭で `Policy.load_layers!` + `resolve` を実行し、以後の
  `coverage_mode` / `coverage_threshold` / `embed` / `recruit` / `rounds` / git セクションの参照を
  実効ポリシー経由に置き換える（CLI フラグの個別 Keyword.get は cli 層構築に集約）。
- `Workspace.load!` の git 解釈との整合: 実効ポリシーの `git` map を Workspace に渡せるよう、
  `load!(issue_dir, git_override)` 相当の口を追加（nil なら従来どおり workspace.json を読む。
  既存の公開 API 互換は維持）。
- **来歴の拡張**: brief-31 の `seed_git_policy!` を一般化して**実効ポリシー全体**を1つの `:policy` entry に:
  text = 決定的な1行サマリ（`policy: coverage.mode=relative(repo) embed=ollama(cli) git.mode=branch(issue) ...`
  — 値と勝った層を併記、キーは辞書順）、meta = `%{kind: "effective_policy", policy: <実効map>, sources: <provenance map>}`。
  `:change` の citations への追加は既存機構のまま（policy entry id が変わるだけ）。
- `--status` に実効ポリシーと各キーの出所を表示する節を追加。

## 4. テスト（`test/policy_test.exs` 新規 + 既存ファイル追記）

- resolve unit: 優先度（cli > issue > repo > org > default）/ 深いマージ（git.mode だけ issue が
  上書きし他キーは下層が残る）/ provenance map が勝者を正しく指す / 未知キー raise。
- load_layers!: ファイル不在 = 既定のみ / TRACEFIELD_ORG_POLICY 設定時に org 層が効く
  （テストでは System.put_env + on_exit で戻す）/ workspace.json の git セクションが issue 層として
  読まれる互換 / policy.json が workspace.json の git より勝つ。
- dev 統合: repo の .tracefield/policy.json で coverage.mode=relative → relative 検出が動く /
  CLI フラグがそれを上書きする / :policy entry の text に値と出所が併記され meta に sources が入る。
- 互換: ポリシーファイル一切なし＋フラグなしで現行挙動と同一（既存 e2e 無変更 green が証明）。
- 既存 180 green 維持。

## 5. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（180 + 新規、全 green）
3. 変更ファイル一覧

コミットしない。報告に変更ファイルとテスト結果。
