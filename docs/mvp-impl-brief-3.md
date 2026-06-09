# 実装ブリーフ 3 — スタンスベースの影響測定 + 測定の分離

> codex への実装指示（第3弾）。前提: 既存コード（brief-1/2 実装済）と [`mvp.md`](./mvp.md)、[`design-review.md`](./design-review.md) DR-2。
> `mise exec -- mix ...` で全コマンド実行。ネット無し（ollama/deps.get 実行しない）。コミットしない。

## 0. なぜ作り直すか（実測で判明した核心）

実 gemma4:12b の測定で判明:
- **汚染Aは「どのテーマが出るか」を変えていない。「同じテーマ内の結論（スタンス）」を変えている。**
  例: `consent`(顧客同意) テーマで、汚染あり=「同意取得済み・制約クリア」(楽観) / 汚染なし=「派生利用は範囲外・追加同意必要」(慎重)。
- 現行の「影響＝cluster 集合の差」では、両条件とも consent テーマが出る → 差が見えない。
- 一方クラスタを細かくするとノイズ（言い換え）で埋もれる。

**方針**: 影響を **「各テーマで嘘あり/なしの結論が変わったか（スタンス反転）」** で測る。
あわせて **クラスタリングを積極マージに強化**し、**測定を探索から分離**して再測定を安価にする。

## 1. クラスタリング強化（`Normalize.cluster/2`）

現行プロンプトは claim ごとに固有ラベルを付けてマージしない。次の挙動に変更:
- system 趣旨: 「番号付き claim を**根底の論点ごとにグループ化**。表現や粒度が違っても同じリスク/推奨は同一グループ。
  明確に異なる論点は分ける。**全体で 6〜12 グループ目安**。出力は JSON オブジェクト `{ "kebab-group-id": [番号,...], ... }`。
  全番号がちょうど1回。」（この指示は実機で良好なマージを確認済み）
- パース: `{label: [indices]}` → `ref => cluster_id`。失敗/件数不一致は決定的フォールバック（`normalize_text`）。
- インターフェース不変: 入力 `[%{ref, text}]`、出力 `%{ref => cluster_id}`。

## 2. スタンス評価（新規 `Tracefield.Stance`）

`assess(topic_label, group1_texts, group2_texts, llm_opts) :: %{differs: boolean(), g1: String.t(), g2: String.t()}`
- LLM（system キー `TRACEFIELD_STANCE`）。**条件名は伏せ**「Group 1 / Group 2」で渡す（バイアス対策）。
- 趣旨: 「同一トピックに関する2グループの claim。各グループの結論/立場を1行で要約し、
  両者が**実質的に異なる立場/結論**（反対・逆推奨など）かを判定。JSON `{ "g1": "...", "g2": "...", "differs": true|false }`。」
- パース失敗時は `differs: false`。

## 3. 影響集合の再定義（GroundTruth）

クラスタリング後、各 topic（cluster_id）について:
- `a_present` = いずれかの A-run に出現, `b_present` = いずれかの B-run に出現。
- **presence 変化**: `a_present != b_present` → 影響あり。
- **stance 変化**: 両方に出現するなら、A-run 群の該当 claim texts と B-run 群の該当 claim texts を `Stance.assess` → `differs` なら影響あり。
- `affected_set` = 上記いずれかを満たす topic の MapSet。

`system_claimed_affected` = 各 run の reconstruct（ローカル claim id）→ cluster_id（topic）へ写像し union（既存ロジック流用）。
`proxy` = `Metrics.prf(affected_set, system_claimed_affected)`。
結果に **stance テーブル**（topic ごとに a_present/b_present/differs/g1/g2）を含める。within/between(cluster集合) は二次診断として残す。

## 4. 測定を探索から分離（重要・反復を安くする）

探索（遅い LLM 探索）と測定（抽出/クラスタ/スタンス/指標）を分ける。

- `GroundTruth.measure(runs_a, runs_b, scenario, opts) :: {:ok, result}`:
  入力の各 run は `raw_output, transcript, run_key, model, seed, temperature`（`claims` があれば再抽出をスキップ）。
  抽出（無ければ）→ reconstruct → cluster → attach_clusters → stance → affected/metrics。
- `GroundTruth.run/2` は従来どおり探索して runs を作り、その後 `measure/4` を呼ぶだけにリファクタ。
- **新 mix タスク `mix tracefield.remeasure --from runs/<summary>.json`**:
  保存済み summary を読み、`runs_a/runs_b`（raw_output/transcript/run_key/claims を含む）から run マップを復元し `measure/4` を実行。
  → 探索を再実行せず、保存済み出力に対して**測定だけ**を再計算できる（クラスタ/スタンス改良の反復用）。
  保存 summary の claims を再利用（再抽出しない）。reconstruct/cluster/stance は再実行。

## 5. Mock 更新（Phase 0 自己検証を維持）

新プロトコルに決定的応答を返し、**affected_set = {consent topic} / recall=precision=1.0** を保つこと:
- `TRACEFIELD_CLUSTER`（group 形式 `{label:[indices]}`）: **consent 関連（signal の楽観 consent と risk の慎重 consent）を同一 topic `consent-secondary-use` にまとめ**、他は従来の正規 id ごとの group にする。
- `TRACEFIELD_STANCE`: 2グループ比較で、一方に signal(楽観 consent) テキスト・他方に risk(慎重 consent) テキストが含まれる場合のみ `differs: true`、それ以外は `false`。
- `TRACEFIELD_EXTRACT_CLAIMS` / `TRACEFIELD_RECONSTRUCT_AFFECTED` / review 生成: 既存どおり。
- 結果: consent topic は a で楽観・b で慎重 → stance differs → affected。他 topic は両条件同じ → not affected。
  reconstruct は signal claim → consent topic を claim。→ **affected_set == {consent topic}, recall=precision=1.0**。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（緑。テスト更新: `Stance` の differs 判定、cluster の group 形式パース＋フォールバック、
   `ground_truth_mock_test` を affected_set=={consent topic}・recall=precision=1.0 に更新）
3. `mise exec -- mix tracefield.phase0`（affected が consent topic、proxy 1.0、stance テーブル表示）
4. `mise exec -- mix tracefield.phase1 --adapter mock --n 8`（同上）

Ollama は実行しない。`to_plain/1` は stance テーブル等の新フィールドも JSON 化できること。
