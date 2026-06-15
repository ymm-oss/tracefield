# 結果 — H5: synthesizer / Generator-Verifier ステップ（Fusion 機構の移植）

> 日付: 2026-06-15。由来: OpenRouter Fusion 分析（self-fusion +6.7 ＝ 精度は「混ぜる」でなく「並列サンプル＋強い judge/synthesize」から）→ tracefield に移植して検証。
> 問い: Shared State の熟議の上に **strong synthesizer（store を読んで領域横断の矛盾を接続）** を足すと、攻めの便益（disc_strict）が上がるか。

## 設計（within-run A/B）
- **熟議**: gemma4:12b エージェント（速い・§12a で「事実を外部化するが繋げずエコー」＝潜在発見を残しやすい条件）。serve:diverse, aware:1, kp:1, ks:2, seeds=3。
- **synthesizer**: Opus 4.8（cursor-agent）が各 run で全 entries を読み、矛盾を【両キーワード明記】で belief 化。同じ熟議を **synth 有無でスコア**（`disc_strict` vs `disc_strict_synth`）。実装: `mix tracefield.hetero --synth <cursor-model>`（`synthesize/2`）。

## 結果（seeds=3）
| seed | agents disc_strict | synth disc_strict |
| --- | --- | --- |
| 2000 | 3 | 3 |
| 2001 | 1 | 1 |
| 2002 | 2 | 2 |
| mean | **2.0** | **2.0（Δ=0）** |

一見、**synth は便益を増やさない（Δ=0）**。

## だが診断で単純な null は覆る — synth は潜在矛盾を接続できるが「1回呼び出しはコイン投げ」

seed 2001（agents=1）の store を精査:
- **6つの植え込みキーワードすべてが store に存在**（retention-90d×4, delete-72h×7, upsell-q3×3, access-support-only×1, no-training-promise×1, finetune-plan×3）＝ 検索段は通っている。
- I1(delete-72h+retention-90d) は多数の entry で接続済（agents が得た 1）。**I2(upsell-q3+access-support-only) と I3(no-training-promise+finetune-plan) は両事実とも store にあるが別 entry に散在し未接続** ＝ まさに synth が繋ぐべき状況。
- **同じ store に Opus synth を再実行**すると、**I1＋I2 を接続**（entry に access-support-only と upsell-q3 を両方明記）＝ disc_strict 2 相当。**agents の 1 を上回る**。

→ **同一 store・synth 2回で結果が違う（pilot=1 / 再現=2）＝ synth 出力は非決定的**。素材は store にあり、synth は**潜在矛盾（I2）を接続できる**が、**1回の synth 呼び出しは難しい組でコイン投げ**になり、pilot の3回ではノイズが信号を覆った（Δ=0）。

## 解釈 — Fusion を過小実装していた

Fusion の精度は **single synth call ではなく、並列アンサンブル（N サンプル）→ judge → synthesize** の**分散低減**から来る（self-fusion +6.7 がその証拠）。本 H5 は **synthesize-once** で、1回の非決定性がそのまま出た。
→ **H5 は反証でも実証でもなく「現実装では不確定」**。機構（synth が潜在発見を接続する）は**実機で確認**できたが、**net 便益にはアンサンブル（best-of-N synth）が要る**。

## 次の一手（H5b）
1. **best-of-N synthesizer**: synth を K 回サンプルし union（or judge で consensus）＝ Fusion の本来形。これで分散を潰せば Δ>0 が出るか。
2. seeds 増（n=3 は粗い）。
3. **高天井シナリオ（H2）**: 3件天井だと synth の上積み余地が小さい（agents が既に 2-3/3）。植え込み 10+ で検出力確保。
4. 並列サンプリングは熟議側にも適用可（各 agent を best-of-N に）。

## 限界
- n=3・3件天井・単一シナリオ・synth 1回（非決定）。disc_judge は飽和。
- 機構の確認は seed 2001 の単一再現に基づく（1事例）。
- これは攻め（協働）の話。守り（来歴・撤回）は別軸で tracefield 固有。

## 位置づけ（セッションのアーク）
- **H1/H1b**: 「器官を異質にする」→ 反証（同系列・異系列とも）。
- **H5**: 「構造（強い統合ステップ）を足す」→ **機構は確認・net 便益は要アンサンブル（不確定）**。
- 統合: Fusion の教訓どおり **レバーは"混ぜる"でなく"並列サンプル＋選択/統合"**。H5 はその半分（synthesize）だけを実装した段階で、残り半分（parallel ensemble＝分散低減）が次。

---

## H5b — best-of-N synthesizer: 肯定（Δ=+1.0、Fusion 機構を実機で確認）

H5 の「synthesize-once は非決定でコイン投げ」を受け、**best-of-N**（synth を K 回サンプルし union を strict_score）を実装（`synthesize/3`＋`--synth-n`）。Fusion の本来形（parallel ensemble→統合＝分散低減）。

**設定**: H5 と**同一**（gemma4:12b 熟議は seed 決定的＝同じ store）＋ `--synth-n 3`、Opus synth。同じ store に対し「synth を3回 union する効果」だけを単離。

| seed | agents disc_strict | synth (best-of-3) | （H5 単発 synth） |
| --- | --- | --- | --- |
| 2000 | 3 | 3 | 3 |
| 2001 | **1** | **3** | 1 |
| 2002 | **2** | **3** | 2 |
| mean | **2.0** | **3.0（Δ=+1.0）** | 2.0（Δ=0） |

### 判定 — 肯定（攻めのレバーを実証）
**best-of-3 synth は全 seed を天井 3/3 に押し上げ（Δ=+1.0）、しかも分散ゼロ（3,3,3）vs agents（3,1,2）。** H5 単発（同一 store で Δ=0）との差が、**並列サンプルの分散低減効果そのもの**。
→ **攻めの便益のレバーは「並列サンプル＋統合（分散低減）」── Fusion の self-fusion(+6.7) と同型の機構が tracefield でも成立。** 基盤異質性（H1/H1b 反証）でも単発統合（H5 不確定）でもなく、**これ**が効く。

### 機構の物語（完成形）
agents は事実をキーワード付きで外部化するが繋げずエコー（§12a）→ 単発 synth は難しい組でコイン投げ（H5）→ **best-of-N synth の union が全ての潜在矛盾を接続**（H5b）。retrieval 段（事実が store にある）が通っていれば、best-of-N synth が expression/connection 段を解く。

### 限界
- **3件天井**: synth が 3/3 に飽和したため**真の効果量は測れていない**（Δ=+1.0 は「2.0→天井」）。H2 高天井シナリオ（植え込み 10+）で本当の上積みを測るべき。
- n=3・gemma 熟議×Opus synth（強い synth）・best-of-3＝3× synth コスト・単一シナリオ。
- retrieval 段が落ちる（counterpart 未外部化）ケースには best-of-N synth も無力（store に無いものは繋げない）。

### 含意
- **攻めの実用レバーが確定**: 強い best-of-N synthesizer ステップ。tracefield の弱い judge（§9c 飽和）の伸びしろがここ。
- **次**: (1) H2 高天井で真の効果量、(2) synthesizer をクラスタ化＝**統治可能な合成**（合成発見が layer-0 を citation し、撤回が合成層へ閉包伝播）＝ Fusion にできない tracefield 固有価値（design-cluster の scale-free 再帰）。
- セッション総括: **「混ぜる」✗（H1/H1b）／「1回統合」△（H5）／「並列サンプル＋統合」◯（H5b）** ── Fusion の教訓と完全一致。

---

## H2 — 高天井（10件）での真の効果量: synth は横断発見を約2倍に

H5b は3件天井で synth が飽和（Δ=+1.0 は「2→天井」）。真の効果量を測るため**植え込み相互作用を 3→10** に拡張（`scenarios/enterprise-hi`＋`Discovery.interactions(:hi)`、cross-agent な10組）。`mix tracefield.hetero --scenario-dir scenarios/enterprise-hi --interactions hi --synth <model> --synth-n N`。

**結果**（gemma 熟議 × Opus best-of-3 synth、seeds=3、disc_strict は /10）:
| seed | agents | synth (best-of-3) |
| --- | --- | --- |
| 2000 | 3 | 5 |
| 2001 | 3 | 5 |
| 2002 | 2 | 6 |
| mean | **2.67** | **5.33（Δ=+2.67）** |

### 判定 — synth レバーの効果量が確定（天井なし）
**best-of-N synth は横断発見を 2.67 → 5.33（約2倍、Δ=+2.67）に押し上げる。** H5b の Δ=+1.0 は3件天井が隠していた過小評価で、**頭打ちを外すと効果は ~2.7**。攻めの実用レバーとして大きい。

### synth が 10/10 でなく ~5-6 で頭打ちな理由 — retrieval 段の限界（§13 ファネルの確認）
synth は**外部化された事実しか繋げない**。entry_limit=2×2round では 20 事実すべては store に出ない → 両事実が externalize された組（~5-6）が上限。**synth は expression/connection 段を解く（agents 2.67→synth 5.33）が、retrieval 段（何が外部化されるか）は解かない**。
→ **2つのレバーは合成的**: `発見 ≈ retrieval段（serve/aware/rounds で事実を外部化）× expression段（best-of-N synth で接続）`。synth で 5.3、残りは retrieval を上げる（rounds↑/entry_limit↑/serve）次レバー。§13 のファネル分解がスケールでも成立。

### 限界
- n=3・gemma 熟議×Opus synth・best-of-3。synth は retrieval 上限（~5-6/10）で頭打ち＝効果量は「connection 段の上限」での値。
- 10組は単一シナリオの設計。disc_judge は :hi 未対応（3件基準・無視）。

### 含意（確定）
**攻めの便益 = retrieval（事実の外部化）× expression（best-of-N synth による接続）。** substrate 異質性（H1/H1b ✗）でなく、この2段ファネルの各段を上げるのが効く。synth(expression)は約2倍の効果で確定。次は retrieval 段（rounds/serve）を上げて synth の上限を押し上げる、または synthesizer のクラスタ化＝統治可能な合成（design-cluster scale-free）。
