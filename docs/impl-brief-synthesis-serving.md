# 実装ブリーフ — 合成層の serving 経路（best-of-N synth を default-on）

> 由来: 2026-06-16「性能のため合成層をデフォルトで使いたい」→ ユーザー選択＝**新 serving 経路を作る**／**Opus × best-of-N N=3**。
> 背景: 合成層（best-of-N synth）は H5b/H2 で横断発見 約2倍、H6 で来歴付き（撤回が層を越える）と実証済。だが現状は **`mix tracefield.hetero` の計測パス（`--synth`）にしか無く、成果を返す経路が無い**。本ブリーフは consumer 向けに「チームを熟議させ、best-of-N synth で横断発見を合成し、来歴付きで返す」serving 経路を新設する。
> **研究ハーネス（hetero）のコード・既定は一切変えない**（A/B 統制を保つ）。serving は別経路。

## スコープ

1. 新モジュール `Tracefield.Synthesis`（production 版 best-of-N cited synth＋接地＋来歴付き absorb）。
2. 新コマンド `mix tracefield.consult`（名前は調整可）＝ 熟議 → 合成 → 来歴付き結果を返す。**synth は default-on（Opus, N=3）**。
3. テスト（Mock で決定的）。

**やらないこと**: hetero 実験コード/既定の変更、プロセス制御層（H7）の変更（既に dev/evidence で既定・現状維持）、retraction の自動実行（来歴は「返す」だけ。撤回は別途）。

## 1. `Tracefield.Synthesis` モジュール

`mix tracefield.hetero` の private `multilayer_demo`（H6）から **production に使える部分だけ**を関数化する。**実験専用部分は除外**：

- **再利用する核**: best-of-N synth 呼び出し（cursor-agent CLI で synth_model を N 回）→ cited findings をパース（`parse_synth_cited` 相当）→ layer-0 を citation して store に absorb（来歴付き＝H6 の固有価値）。
- **差し替える肝（重要）**: H6 の接地ゲートは**植え込みキーワード（`interactions` の ground truth）依存**で、実運用では ground truth が無いので**使えない**。production の接地は **`Tracefield.Reference.verify`（LLM 接地判定）** に差し替える ── synth の各 citation について「cited entry が本当にその発見を接地するか」を verify し、**接地しない citation を落とす**（H6 keyword gate と同じ目的＝過剰連結の抑制を、ground-truth 無しで行う）。
  - 注: H6 検証では lenient な gemma verify が過剰連結を見逃した実績あり。verify には強めの judge を使えるよう `verify_adapter`/`verify_model` を引数化（default はローカル ollama でよいが上書き可）。これは「H8 の構造化 citation」とも整合（synth も citation を構造的に出す）。
- **公開 API 例**:
  ```
  Synthesis.run(reference, layer0_entries, opts)
    opts: synth_model (default "claude-opus-4-8-medium" 等の cursor-agent slug),
          synth_n (default 3), verify_adapter, verify_model
    returns: %{
      findings: [%{id, text, citations: [layer0_id], grounded_citations: [...], verified: bool}],
      synth_entry_ids: [...],     # store に absorb 済（来歴付き＝撤回可能）
      dropped_citations: [...]    # 接地ゲートで落ちた引用（正直な可視化）
    }
  ```
- best-of-N の union は H5b と同じ思想（N サンプルを束ね分散低減）。strict/judge スコアは**付けない**（あれは実験の指標。serving は findings を返すのが仕事）。

## 2. `mix tracefield.consult` serving コマンド

- 入力: `--scenario-dir <dir>`（既存 `Scenario.load!` 再利用。task＋agents の private docs）。将来 `--task` 直指定も可だが v1 は scenario-dir でよい。
- フロー:
  1. `Reference.start_link`（embed は ollama）。task chunk を absorb。
  2. **熟議**: `Dissolution.default_agents()` を `Agent.run_turn` で `--rounds`（default 2）回す（hetero の `run_round` と同じ最小ループ。serve_policy=diverse, aware=true を既定に）。
  3. **合成（default-on）**: `Synthesis.run(reference, layer0, synth_model: "<opus slug>", synth_n: 3, …)`。`--no-synth` で無効化、`--synth-model`/`--synth-n` で上書き。
  4. 出力（人間可読＋機械可読 JSON）: synth findings（text＋来歴 citation＋verified）、落とした引用、layer-0 entries の id→text マップ（consumer が来歴を辿れる）。
- **synth が default-on**＝引数を付けなくても Opus×3 で合成して返す。これがユーザー要望の本体。
- コスト注記をログに出す（「best-of-3 Opus synth＝強モデル3回呼び出し」）＝ silent な高コストにしない。

## 3. テスト
- `test/synthesis_test.exs`: Mock adapter＋スクリプト化した synth 出力で、(a) cited findings が absorb され store に乗る、(b) verify 接地ゲートが未接地 citation を落とす、(c) layer-0 撤回が synth findings に閉包伝播する（H6 の来歴価値が serving 経路でも成立）、を決定的に検証。
- `test/consult_task_test.exs`: Mock で consult が default-synth ON で findings を返す smoke。`--no-synth` で熟議のみ返る。
- 既存テスト全 green 維持（現 main = 273）。hetero のテストは無改変。

## 完了条件（Claude に返す）
- `mix test` green（273 以上、既存無改変）。
- Mock で consult/Synthesis の決定的テスト pass。
- 実走（任意・サンドボックス TCP 不可なら省略可、Claude が引き取る）。**Opus synth は cursor-agent 経由＝Claude 側で実走確認する**。

## 制約（厳守）
- hetero 実験コード/既定を変えない。プロセス制御層（H7）を変えない。
- 既存テスト編集禁止。
- production 接地は keyword gate でなく `Reference.verify`（ground truth 非依存）。
- `mix format` は新規/変更ファイルのみ。mise 経由。
