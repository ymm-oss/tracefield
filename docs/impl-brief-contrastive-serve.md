# 実装ブリーフ — 差延的 serve（`policy: :contrastive`）v1

> 対象: codex（実装）。Claude が brief 化・検証。
> 由来: 「実行時に他エージェントとの関係で偏りを強化＝エージェント個体の意味の差延（différance）」の最小実装。
> 関連知見: `conclusions.md` §2-3（構造×契約の自覚）、`experiment-results.md` §11（k_s は均質化ダイヤル）・§14（serve:diverse × aware で発見 0.33→2.0）。

## 0. 狙い（なぜ）

偏りを「所有する静的属性（ペルソナ＝薄膜、§9b/§11 で washout）」ではなく、**他者との差異から実行時に再導出され能動的に防衛される関係的位置**として扱う。
`:diverse`（著者バランス）の次段として、**チームが現在収束している重心から離れた"周縁/フロンティア"の他者寄与を提示**し、エージェントを補集合へ駆動する。

**重要な前提（乗数であって源泉でない）**: この効果は実体的な異質性（別私的文書・別データ）がある時のみ genuine。無い時は diversity theater（指標 1−cos だけ上がり発見は増えない）。v1 はこれを後段の実験（v2）で切り分けられるよう、方策だけを最小実装する。

## 1. スコープ

**IN（v1）**
- `Tracefield.Reference.serve` に `policy: :contrastive` を追加
- CLI 配線（`--serve contrastive`）
- aware 連動プリアンブル（contrastive 時の補集合指示）
- 単体テスト
- `mix tracefield.hetero` で `--serve contrastive` が走ること

**OUT（v2・別ブリーフ）**
- `collapse_rate` を反発トリガにするフィードバックループ
- 領土台帳（TERRITORY CONTRACT）の実行時再契約
- homogeneous 対照（theater 検出器）と k_d 用量反応実験
- self の重心からの距離（自己 entries を参照する反発）

## 2. 対象コードと現状（file:line、変更前）

- serve API: `lib/tracefield/reference.ex:52`、`handle_call({:serve,...})` 196-211
  - opts: `:k`(既定5) `:exclude_author` `:only_author` `:exclude_types`(既定[]) `:policy`(既定`:similar`)
  - 候補 = active → `filter_author(:exclude_author)` → `filter_author(:only_author)` → `serve_entries(query_text, k, exclude_types, policy, state)`
- `serve_entries`: `:similar` 820-832（query埋め込み cosine 降順 take k）／`:diverse` 834-843（著者 group → 各著者 recency 降順 → `round_robin/1` → take k）／fallback 845-847（未知 policy は raise）
- helpers: `embed_one/2` 798、`Tracefield.Embed.cosine/2`（`lib/tracefield/embed.ex:26`）、`entry_number/1`、`filter_types/3` 812、`round_robin/1` 849
- centroid 参考（private・移植元）: `lib/tracefield/genesis.ex:153-174`（`centroid/1` + `normalize_vector/1`）
- agent の serve 呼び出し: `lib/tracefield/agent.ex:72-78`（`policy: state.serve_policy` で素通し。`:contrastive` を渡せば動く）
- CLI 正規化: `lib/mix/tasks/tracefield.ideate.ex:1220-1224`（`normalize_serve/1`）
- 既定 serve: `lib/mix/tasks/tracefield.dev.ex:1473,1552`（`serve_policy: :diverse` ── **変更しない**）
- aware/SITUATION プリアンブル: コード内を `grep -rn "SITUATION\|aware" lib/tracefield/agent.ex` で特定（build_prompt 周辺）

## 3. 実装仕様

### 3.1 `serve_entries(entries, query_text, k, exclude_types, :contrastive, state)`
`:diverse` 句の後・fallback の前に新句を追加。候補プール = 引数 `entries`（既に active・exclude_author=self 適用済み＝**他者の寄与**）。

手順:
1. `filter_types(:exclude_types, [:procedure | List.wrap(exclude_types)])`（`:diverse` と同様に procedure を除外）。
2. 残候補が空、または `k == 0` → `[]`。
3. `query_embedding = embed_one(query_text, state)`。
4. `team_centroid = centroid(候補の埋め込み群)`（mean → L2 正規化。`genesis.ex` のパターンを移植、または `Embed.centroid/1` を新設して共有＝**推奨**）。
5. 各候補 `e` の **contrastive score**:
   `score(e) = cosine(query_embedding, e.embedding) - @contrastive_lambda * cosine(team_centroid, e.embedding)`
   - `@contrastive_lambda` はモジュール属性（既定 `1.0`）。
   - = 「課題に関連するが、チームの収束点からは遠い」ものを高評価。
6. **著者バランス**（`:diverse` の良さを保つ）: `group_by author` → 各著者内を `score` 降順（tie-break: `entry_number` 昇順で決定的）→ 著者を「その著者の最高 score」降順に整列 → `round_robin/1` → `Enum.take(k)`。

結果 = 他者の「関連かつ特徴的」な寄与を著者横断で提示。

### 3.2 CLI 配線
- `ideate.ex` `normalize_serve/1` に追加: `normalize_serve(:contrastive) -> :contrastive` / `normalize_serve("contrastive") -> :contrastive`。
- `tracefield.hetero` の serve パース: `normalize_serve` を共有しているなら自動。独自パーサなら `contrastive` を同様に受理。
- 既定値は変更しない。

### 3.3 aware 連動プリアンブル（agent.ex）
既存 aware/SITUATION プリアンブルを特定し、`state.serve_policy == :contrastive` **かつ** aware 有効時に、以下主旨の一節を既存プリアンブルへ**合成**（日本語・既存スタイル、`@contrast_procedure_text`（`tracefield.hetero.ex:8`）の語彙感に合わせる）:

> PRESENTED ENTRIES は、この課題に関連する「他メンバーの最も特徴的な寄与」の横断サンプルである。
> あなたの価値はそれらの**補集合**にある。エコー（提示内容の言い換え）を書くな。
> 彼らが構造的に見落としている観点を、**自分の偏りから**提示せよ。

aware=false のときは出さない（既存の aware ゲートに従う）。

## 4. テスト（既存 serve テストファイルを特定して追加）

`grep -rln "policy: :diverse\|Reference.serve" test/` で対象を特定し追加（埋め込みは Mock アダプタ＝テキスト決定的。必要なら `%Reference.Entry{}` を直接構築して embedding を制御）。

1. **意味の検証**: 著者 B・C が互いに酷似の "consensus" entries を複数、著者 D が1つだけ離れた distinctive entry を持つ構成。
   - `:contrastive` は distinctive（D）を上位 k に含める。
   - 同一構成で `:similar`（query 寄り）/`:diverse`（著者バランスのみ）は D を必ずしも上位にしない ── 順位差で `:contrastive` の固有性を示す。
2. `k == 0` → `[]`、空候補 → `[]`。
3. **著者バランス**: 3 著者で round-robin 表現（1 著者が独占しない）。
4. **決定性**: 同入力で順序安定（tie-break 確認）。
5. **回帰**: 未知 policy は依然 `raise`。`:similar`/`:diverse` の既存テストは不変。
6. **CLI**: `normalize_serve("contrastive") == :contrastive`。

## 5. 完了基準

- `mix test` 緑（新規含む全件）。
- `mix format` 適用済み。
- `mix tracefield.hetero --serve contrastive`（他は既存引数）が起動・パース成功。
- `:similar`/`:diverse` の挙動とテストに回帰なし。
- 既定 serve（dev/ideate）は `:diverse` のまま不変。

## 6. 検証（Claude 側、実装後）

diff レビュー → `mix test` / `mix format --check-formatted` 再実行 → 3.1 のスコア式と著者バランスの妥当性、3.3 プリアンブルの aware ゲート整合を確認 → ユーザー報告。
