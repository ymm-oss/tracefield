# 結果 — 差延的 serve（`policy: :contrastive`）の検証と棚上げ

> 日付: 2026-06-14。設計: [`impl-brief-contrastive-serve.md`](./impl-brief-contrastive-serve.md) / [`impl-brief-theater-detector.md`](./impl-brief-theater-detector.md)。
> 問い: 「実行時に他エージェントとの関係で偏りを強化＝差延（différance）」を `serve :contrastive` として実装したとき、
> それは **genuine な横断発見**を増やすのか、それとも **diversity theater**（指標だけ動かす）なのか。

## 設定

- `mix tracefield.hetero --adapter ollama --model gemma4:12b --serve diverse,contrastive --hetero grounded,homogeneous --aware 1 --ks 2 --kp 1 --seeds 6`（24 runs）
- 一次指標 = `disc_strict`（決定的・植え込み相互作用 I1〜I3 の発見数）。theater 監視 = `diversity` / `collapse_rate`（決定的・埋め込み）。
- `grounded` = エージェント別の私的文書（矛盾が2文書にまたがる＝発見は横断を要する）。`homogeneous` = 全 agent に同一文書（全私的文書の連結＝総情報量一定・分布の異質性のみ除去）。
- provenance: パイロット `runs/20260614T014120.164017-hetero-ollama.json`（seeds=2）／確認 `runs/20260614T031001.396994-hetero-ollama.json`（seeds=6）。

## 結果（seeds=6, mean±sd）

| serve | hetero | disc_strict | diversity | collapse | coverage | icc |
| --- | --- | --- | --- | --- | --- | --- |
| diverse | grounded | **2.00 ±0.89** | 0.224 | 0.153 | 9.0 | 5.5 |
| contrastive | grounded | **1.00 ±1.26** | 0.246 | 0.028 | 8.7 | 6.3 |
| diverse | homogeneous | 2.00 ±0.89 | 0.087 | 0.827 | 3.7 | 2.2 |
| contrastive | homogeneous | 2.33 ±0.52 | 0.118 | 0.622 | 4.7 | 4.0 |

grounded 生値（disc_strict）: diverse `{2,1,1,3,3,2}`（ゼロなし）／contrastive `{2,0,0,3,1,0}`（**3/6 がゼロ発見**）。
**contrastive は全 6 seed で diverse 以下、4/6 で厳密に劣る**（sign test 片側 p≈0.06）。diversity は逆に contrastive が全 seed で僅かに高い。

## 判定 — 棚上げ（promote しない）

**contrastive は genuine 発見を surface 多様性とトレードしていた。** grounded（横断発見が成立する条件＝本命）で:
- disc_strict 2.0 → **1.0**（半減、ネット負）
- diversity 0.224 → 0.246（微増）、collapse 0.153 → 0.028（より分散）

= まさに **diversity theater**。しかも単なる no-op ではなく、**一次目的に対して有害**。
会話で立てた仮説「差延は grounded 異質性の乗数（接地ありで genuine に効く）」は **反証**された。

### 機構的説明（仮説）
`:contrastive` は「query に関連するが**チーム重心から遠い**」周縁寄与を提示する。だが植え込み矛盾の発見には、
各 agent が**自分の私的事実と衝突する特定の counterpart entry**を見る必要がある。その counterpart は重心寄り（共有的な話題）に
位置しうるため、「重心から遠い」最適化が **必要な counterpart からagentを遠ざける** ── 提示の多様性を、関連 counterpart の的中と引き換えにしている。

### 副次（過解釈しない）
- `icc`（介在懸念数）は contrastive がやや高い（6.3 vs 5.5）が、判定器飽和（§9c）で信頼度低。植え込み発見（決定的）を覆さない。
- 検証として **hetero 主効果は明瞭**: grounded ≫ homogeneous（diversity 0.23 vs 0.10、collapse ~0.1 vs ~0.7、coverage ~9 vs ~4）。§11/§14 の既知結果を再現＝**ハーネスと指標は健全**。効かないのは contrastive 軸であってハーネスではない。

## 限界

- **単一シナリオ・I1〜I3 の3件天井**（disc_strict ∈ {0,1,2,3} の粗い指標）・**gemma4:12b のみ**・n=6。**機構レベルの知見**で統計的断定ではない。
- ただし符号は seeds=2→6 で安定し、grounded で contrastive が diverse を上回る seed は**ゼロ**。「promote しない」判断には十分。

## 決定と今後

- **既定は `diverse` のまま**。`:contrastive` は `--serve contrastive` 裏の**未検証→反証オプション**として温存（コードは無害・コミット済 00760e4）。`reference.ex` の該当 clause に本書への来歴コメントを付す。
- 差延を本気で追うなら、passive な serve 側対比は不十分／有害。筋の良い次手:
  1. **天井の高いシナリオ**（植え込み相互作用 3→10+）で検出力を確保してから再判定。
  2. **能動機構（v2）**: `collapse_rate` をトリガにした**反発フィードバックループ**（passive 提示でなく、エコー検出時に差異化を促す）。
  3. counterpart を**遠ざけず**むしろ**狙って**提示する「矛盾ターゲット型」serve（重心距離でなく、自分の私的事実と最も衝突する他者 entry を選ぶ）── 機構的説明が示す修正方向。
