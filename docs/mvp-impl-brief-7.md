# 実装ブリーフ 7 — Dissolution 実験（融合深さ × 協働 × 多様性）

> codex 指示（第7弾）。実験設計は [`experiment-core.md`](./experiment-core.md) を必読。既存コード（lib/tracefield/*, Mock, Normalize, Metrics, mix tasks, test/*）を再利用。
> `mise exec -- mix ...`。ネット無し（ollama 実行しない・deps.get 不要）。コミットしない。

## 1. `Tracefield.Dissolution` — regime 付き探索ランナー

`run(scenario, regime, opts)` で1探索（3エージェント×rounds）を実行:
- opts: `adapter, model, temperature(既定0.4), seed, rounds(既定2), agents(既定下記)`
- agents（既定）: `[{id:"SEC", domain:"security", desc:"セキュリティ・権限・情報漏洩を最優先する"}, {id:"BIZ", domain:"business-speed", desc:"事業速度・意思決定効率・ROIを最優先する"}, {id:"UX", domain:"ux", desc:"UX・ユーザーの誤用・説明責任を最優先する"}]`
- regime: `:closed | :semi | :merged`
- **コンテキスト構築は純関数**（unit-test 対象）`build_context(regime, workspace, published)`:
  - closed → **published（他者の公表懸念）のみ**。notes は絶対に含めない。
  - semi / merged → workspace 全体（**全員の notes＋懸念**）。
- **指示文**:
  - closed と semi: **完全に同一**（「あなたは {id}（{desc}）。自分の偏りを保ちつつ、まだカバーされていない観点・領域をまたぐ相互作用を埋めよ」）。
  - merged: 「自分の専門の偏りに固執せず、チームの単一の統合見解に収束せよ」。
- 各ターン: system に protocol キー `TRACEFIELD_DISSOLUTION` を含め、出力 JSON `{"notes":"思考","concerns":["…","…"]}`（≤2件、寛容パース、失敗時 concerns=[] で続行）。
- ターンごとに workspace へ `[{id} notes] …` と `[{id} concern] …` を、published へ `[{id}] {concern}` を追記。seed はターンごとに `seed + round*100 + agent_index` のように決定的に変える。
- 返り値 run: `%{regime, seed, turns: [%{agent, round, notes, concerns}], concerns_by_agent: %{id => [text]}}`

## 2. 測定 `Tracefield.Dissolution.measure(run, opts)`

within-run のみで算出（run 外とのクラスタ共有はしない）:
1. **クラスタ**: 全懸念を `Normalize.cluster/2`（既存）へ `[%{ref: "{agent}|{n}", text}]` で渡し `ref=>cluster` を得る。
2. **coverage** = チームの distinct cluster 数。
3. **diversity** = エージェント別 cluster 集合のペアワイズ `Normalize.diff/2`（既存 Jaccard 距離）の平均（agent が1人なら 0.0）。
4. **領域タグ**: protocol キー `TRACEFIELD_DOMAINS`。固定タクソノミー `["security","legal-consent","ux","business-speed","data-quality","ops-org"]` をプロンプトに列挙し、番号付き懸念ごとに関与領域(1〜3個)を JSON `{"1":["security","legal-consent"],...}` で返させる（寛容パース、未知タグは捨てる、失敗時 []）。
5. **介在的懸念** = タグ ≥2 個。**ICC** = 「メンバー懸念の過半数が介在的」なクラスタの数。
6. **bias_retention** = agent ごとに「自分の domain タグを含む懸念の割合」→ 平均。
- 返り値: `%{regime, seed, coverage, diversity, icc, bias_retention, clusters, tags, concerns_by_agent}`

## 3. mix タスク `tracefield.dissolution`

`mix tracefield.dissolution --adapter mock|ollama --seeds 3 --rounds 2 --regimes closed,semi,merged --model M --temperature T`
- 各 regime × seed(=`1000+i`) で run→measure。
- 出力: 各 run の行（regime, seed, icc, coverage, diversity, bias_retention）＋ regime ごとの **mean±sd 集計表** ＋ 仮説判定行（H1: mean ICC semi>closed? / H2: diversity semi>merged? / H3: diversity merged≈0 & coverage merged<closed?）。
- 全結果を `runs/<ts>-dissolution-<adapter>.json` に保存（`GroundTruth.to_plain/1` 再利用可）。

## 4. Mock（自己検証を成立させる決定的応答）

`TRACEFIELD_DISSOLUTION` への応答を、プロンプト中の regime 手がかり（merged 指示文の有無 / notes の有無で closed/semi を判別）＋ agent id ＋ round から決定的に生成:
- **closed**: 各 agent は**自領域のみ**の懸念2件（agent×round で異なる固定文。例 SEC r1: 「権限分離が不十分で機密が漏洩しうる(security)」）。
- **semi**: 自領域1件＋**横断1件**（例 SEC: 「監査ログの保持期間が同意撤回と矛盾する(security legal-consent)」、BIZ: 「速度優先のUI簡略化が誤操作を誘発する(business-speed ux)」、UX: 「説明可能性の欠如が法的責任を曖昧にする(ux legal-consent)」）。
- **merged**: **全 agent が同一の合意懸念2件**（例 「導入は段階的に行うべき(business-speed)」「データ品質を確認すべき(data-quality)」、全員同一テキスト）。
- `TRACEFIELD_DOMAINS`: 懸念テキスト末尾の `(...)` 内キーワードからタグを決定的に返す。
- `TRACEFIELD_CLUSTER` は既存 Mock の正規化テキスト一致クラスタで OK（同一テキスト→同一クラスタ）。
- → 期待値: closed: ICC=0, diversity=1.0 / semi: ICC=3, diversity>0 / merged: ICC=0, diversity=0.0, coverage=2 < closed の coverage。

## 5. テスト（既存は全て green のまま）

- `build_context/3`: closed に notes が**含まれない**こと、semi に含まれること、merged の指示文が偏り溶解であること、closed と semi の指示文が**同一**であること。
- パーサ: notes/concerns の寛容パース、TRACEFIELD_DOMAINS の寛容パース。
- mock e2e（seeds=1 で3 regime）: **ICC(semi)=3 > ICC(closed)=0** / **diversity(merged)=0.0 < diversity(semi)** / **coverage(merged) < coverage(closed)** / bias_retention(merged) < bias_retention(closed)。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（緑、新規テスト含む）
3. `mise exec -- mix tracefield.dissolution --adapter mock --seeds 2` ── 集計表に H1/H2/H3 の判定が表示され、mock 期待値どおりであること。

Ollama は実行しない。コミットしない。報告に変更ファイル一覧と mock 集計表を含める。
