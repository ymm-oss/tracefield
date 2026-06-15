# 実装ブリーフ — H8 Step B: 散文 vs tool-use の A/B 計測

> 前提: Step A（`docs/impl-brief-h8-stepA.md`、commit 9330c81）で tool版 RunTurn（`deliberation: :tools`）が動作。既存 `:prose` は無改変。gemma4:31b-it-qat 実走確認済。
> 目的: **同一シナリオ・同一 seeds で `:prose`（散文パース）と `:tools`（構造化ツールコール）を A/B し、tool-use が研究の2レバーで散文版を上回るかを反証可能に測る**。
> 上位文脈: H5/H2 が「攻めの便益 = retrieval（事実の外部化）× expression（接続）」と確定し、retrieval 段が ~5-6/10 で頭打ち（§13 ファネル）。H4/H6 が「散文パース citation は過剰連結（§6a）し grounding gate で後始末が要る」を示した。**tool-use はこの2点（多段 retrieval・構造化 citation）への介入**。

## 仮説と反証条件

**H8（主張）**: agent をツールコール化すると (a) 多段 serve で retrieval coverage が上がり、(b) 構造化 citation で過剰連結が減る。

**反証条件（どれか起きれば該当レバーで tool-use は無効）**:
- **G1（coverage 不転移）**: `:tools` の `disc_strict` が `:prose` と同等以下（多段 serve が効かない）。
- **G2（citation 改善なし）**: `:tools` の citation grounding rate が `:prose` と同等以下（構造化しても過剰連結が減らない）。
- **G3（決定性悪化が便益を食う）**: `:tools` の seed 間分散が `:prose` より大きく、平均改善を相殺。

反証されなければ「tool-use は retrieval/expression レバーで散文版を上回る」が機構レベルで立つ。**陰性（G1/G2 該当）も価値**＝「tool-use の旨味は限定的、散文パース＋H4 ゲートで十分」を確定。

## 計測（hetero ハーネスに A/B フラグを足す）

### 配線（最小）
- `lib/mix/tasks/tracefield.hetero.ex`: OptionParser strict に **`deliberation: :string`** を追加し、`run_one` の `Agent.new(...)` に `deliberation: String.to_atom(...)` を渡す（default `:prose`＝既存挙動不変）。tool版は `tool_max_rounds` も `--tool-max-rounds`（default 4）で渡せると良い。
- 既存 arm（synth 等）と直交。`--deliberation tools` 時も adapter は Ollama（gemma）でよい（tool path は Ollama `:tools` 経由）。

### M-cov（retrieval/expression coverage）— G1
- 既存 `Discovery.strict_score(absorbed, interactions)` をそのまま使用。`scenarios/enterprise-hi` ＋ `--interactions hi`（10 組）。
- `--deliberation prose` vs `tools` を **同一 seeds（例 2000/2001/2002）** で走らせ disc_strict を比較。
- 追加で `perception` から **多段 serve の実測**を集計: `tool_rounds` 分布・`served_queries` 数（agents が実際に多段検索したか）。prose には無い指標なので tools 側のみ。

### M-cite（citation grounding rate）— G2
- **過剰連結の直接計測**。各 absorbed entry の citation について「**接地しているか**」を判定：
  - 接地の定義（決定的・H6 接地ゲートと同じ思想）: citation `e_src → e_cited` が接地 ⇔ `e_cited.text` が、`e_src` が使う植え込みキーワード（その entry が strict-hit している interaction のキーワード集合）を含む。
  - **grounding rate = 接地 citation 数 / 全 citation 数**。低い＝過剰連結（無関係 entry を引用）。
- scorer は新規 `Tracefield.CitationGrounding`（純関数、`absorbed` ＋ scenario の植え込みキーワードを受け取り rate と ungrounded 列挙を返す）。植え込みキーワードは `Discovery.interactions(:hi)` / シナリオから取得。
- prose（パース由来）vs tools（構造化由来）で rate を比較。**tool-use が過剰連結を減らすなら tools の rate > prose**。
- 既存 `Tracefield.CitationPrecision`（撤回閉包の precision）とは別軸（こちらは引用そのものの接地率）。両方出せるなら CitationPrecision も補助指標に。

### M-det（決定性）— G3
- 各モード×seeds の disc_strict・grounding rate の **分散/レンジ**。tools の `tool_rounds` 分散も。

## 出力（A/B レポート）
- `mix tracefield.hetero` の既存 JSON 出力に `deliberation` と上記指標を載せる。
- 加えて A/B を一括実行して表を出す薄いランナー（任意）: `mix tracefield.tooluse_ab --scenario-dir scenarios/enterprise-hi --interactions hi --seeds 2000,2001,2002`（prose と tools を順に回し、disc_strict mean/各 seed・grounding rate・tool_rounds を1表に）。重ければ手動2回実行＋私が集計でも可。

## テスト
- `--deliberation` フラグが `run_one` 経由で `Agent.new` に伝わること（Mock で smoke）。
- `Tracefield.CitationGrounding` の純関数単体テスト（接地/非接地の判定が植え込みキーワードで正しく分かれる、決定的）。
- 既存テスト全 green 維持（270）。

## 完了条件（Claude に返す）
- `mix test` green（270 以上）。
- Mock で A/B 配線が通る（決定的）。
- **実走は Claude が引き取る**（gemma 実走はサンドボックス TCP 不可のため codex は省略可）。codex は配線＋scorer＋テストまで。実 gemma での prose vs tools の数値取得・G1/G2/G3 判定・findings doc 執筆は Claude。

## 制約（厳守）
- `:prose` 既定で既存挙動・既存テストを変えない。
- 既存テスト編集禁止。
- `mix format` は新規/変更ファイルのみ。
- mise 経由。
