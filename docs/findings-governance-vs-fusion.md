# H9 findings — governance vs fusion containment（依存連鎖⑤ #7）

設計: `docs/impl-brief-h9-governance-vs-fusion.md`。ハーネス: `Tracefield.GovernanceVsFusion` ＋ `mix tracefield.governance_vs_fusion`。

## 第1データ点（scenario h9-sla, 1 seed, Opus 全段）

前提 P=「AcmeCloud SLA 99.99% 稼働保証」を layer-0 に seed → 3エージェント(OPS/BIZ/SEC)×2R 熟議(Opus) → best-of-3 合成(stance-audit on) → **18 findings**。P を偽として撤回し containment を測定。

| arm | recall | precision | strong-model calls |
|---|---|---|---|
| GOV（provenance closure） | **1.0** | **0.44** | 0 |
| FUSION-posthoc（Opus 再読） | 0.25 | 0.40 | 1 |
| FUSION-naive | 0（来歴なし） | — | 全 consult 再実行 |

GT（"AcmeCloud" を含む findings = 8件）。GOV closure = 18件全部。FUSION-posthoc = 5件。

## 発見

### F1: GOV は中心前提で氾濫する（過剰連結が serving 層・実データで再現）
GOV closure は 18 findings 全部を affected と判定（recall 1.0 / precision 0.44）。前提が議論の中心なので layer-0 がほぼ全て P を引用し、推移閉包が全 findings へ波及した。これは基盤の **C5 過剰連結 precision 0.50（experiment-results §6f、depends_on_turns が参加を参照）の serving 層での再現**。④ stance-audit は非支持 *citation* を落とすが、layer-0 が前提を**正当に**引用している以上、推移閉包の氾濫は止められない。→ **closure に「依拠の強さ/種類」での減衰（stance 重み付き closure、距離減衰、typed closure の活用）が要る**。単純な到達可能性 closure は中心前提で precision が崩れる。

### F2: keyword-GT は "mentions" と "invalidated-if-false" を混同する（方法論の要修正）
GT＝「前提キーワードを含む」だが、findings の多くは**前提依存を批判**していた（例 e20「SLA を唯一の基準点とする設計は否定される」、e27「SLA 数値を唯一の基準点に据える設計は誤り」）。**P が偽なら、これら批判的 finding は無効化されず*むしろ補強される***。keyword-GT はこれらを誤って GT に含める。FUSION-posthoc の低 recall(0.25) は、Opus が批判的 findings を（妥当にも）除外した結果の可能性が高い。→ **GT は「P 偽で各 finding が invalidated / reinforced / unrelated か」の意味ラベルにすべき**。keyword 一致は不可。

## moat 判断: 保留（測定器の精緻化が先）
この1 seed は governance-as-default を支持も否定もしない。bottleneck は GT プロキシと closure の氾濫であり、**同じ測定で n≥6×3ドメインを回しても決着しない**（ノイズが増えるのみ）。先に F1（stance/typed 重み付き closure）と F2（invalidated-if-false の意味 GT）を入れて初めて、C5/C4 の serving 版を公平に測れる。

## 第2データ点（精緻測定: 意味 GT + GOV :direct, 1 seed, Opus 全段）

F2/F1 を実装し再走（22 findings）。**意味 GT ラベル結果が決定的**だった:

| ラベル | 件数 |
|---|---|
| invalidated（P 偽で無効化） | **0** |
| reinforced（P への依存を批判→補強） | **22（全部）** |
| unrelated | 0 |

| arm | affected | recall | precision |
|---|---|---|---|
| GOV reachable | 22 | 1.0 | 0.0 |
| GOV direct | 4 (e15,e21,e22,e28) | 1.0 | 0.0 |
| FUSION-posthoc | 16 | 1.0 | 0.0 |

（GT が空集合なので全 arm が recall 1.0/precision 0.0 に退化＝**測るべき harm が存在しない**。）

### F3（最重要・新規）: 敵対的合成は前提依存を減らし、containment harm の前提を消す
全 synth finding が **SLA への過依存を批判**していた（例: e21「『SLA があるので保険コスト最小化』という当初 ROI 前提は成立しない」、e28「SLA は可用性の保証にすぎず実損補填しない」、e16「RTO/RPO は SLA 数値からでなく許容実損から逆算せよ」）。多領域の敵対的熟議＋合成は **前提に依拠する object-level finding でなく、前提を疑う meta-level finding** を生む。よって P が偽でも誰も無効化されず（invalidated=0）、**むしろ全員が補強される（reinforced=22）**。

含意: **post-serving の「前提が偽→依拠 findings が破綻」という harm は、tracefield の攻め（敵対的合成）が強いほど稀になる**。攻めが「単一前提への過依存」をその場で炙り出すため、守り（撤回 containment）が救うべき依存 finding がそもそも生成されにくい。**攻めと守りが相互作用し、強い攻めは守りの必要を部分的に代替する**（深い・要追検証の主張）。

### 方法論の帰結
containment を**測れる**ようにするには、植え込む前提を **load-bearing かつ無批判に build される事実**（findings が疑わず計算の土台にする数値・データフィード等）にせねばならない。ベンダー SLA 保証のような **agents が自然に懐疑する前提**では、合成が批判 finding を生み invalidated=0 になる。

## moat 判断: 条件付き → opt-in 寄り（ただし要・追検証）
2 データ点が示すのは: **governance-containment の価値は findings が前提依存であることに条件付き**で、tracefield の攻め過程はその依存を能動的に減らす。よって**敵対的合成の文脈では containment harm は稀**＝`--governance` opt-in 寄り（e81 と整合）。containment が効くのは「findings が無批判に build する load-bearing 前提（事実フィード等）」に限定される可能性が高い。**この限定こそが製品上の killer-context の特定**になる。

## 次手（順序・改訂）
1. **load-bearing 前提シナリオ**: findings が疑わず土台にする事実（例: 確定した法規制値・計測データ）を P に植え込み、invalidated>0 を成立させて初めて GOV vs FUSION を測る。
2. **F1 精緻 closure（残）**: stance/typed 重み付き closure（H7 typed_closure_effects、contradicts→flag・relies_on→invalidate）。prose の stance 記録（#3残り）が前提。
3. **F3 追検証**: 「攻めの強さ↑で premise-dependence↓」を複数シナリオ・premise 種別で測る（攻め⇄守りの代替関係の定量）。
4. 上記後に n≥6×複数ドメインで moat 決断（promote/opt-in）。

## ハーネスの妥当性
測定器（`GovernanceVsFusion`）自体は機能：GOV の過剰連結(precision)と FUSION の保守性(recall)を同一 GT 上で定量化し、両者の不一致と GT の弱さを炙り出した。これは「測定器が研究上の本質的論点（containment precision と GT の意味論）を可視化した」＝再帰ドッグフーディングの所期の働き。
