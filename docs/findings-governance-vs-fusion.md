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

## 第3データ点（load-bearing 前提 h9-capacity, 1 seed, Opus 全段）

F3 の方法論帰結に従い、**敵対エージェントが懐疑しない load-bearing な確定事実**（ピーク QPS=50,000 を「計測済の確定土台」として与え、agents に「確定値から設計せよ」と指示）を P に植え、容量/コスト/データ設計で再走（18 findings）。premise を「実は5,000＝誤り」として撤回。

| ラベル | 件数 |
|---|---|
| invalidated | **0（また 0）** |
| reinforced | 14 |
| unrelated | 4 |

GOV direct = **[]（synth findings は誰も premise を直接引用しなかった）**。GOV reachable=18(precision 0)、FUSION=7(precision 0)、いずれも空 GT に退化。

合成は load-bearing 前提でも依拠せず迂回した: 「QPS 50,000 を固定とする設計は MAU 成長と不整合」(e21)、「容量は QPS でなく MAU×7年保持で決まる」(e17/e23/e29)、「ストレージが計算費を一桁支配＝最適化の主戦場は計算でない」(e19/e25/e31)。埋め込み数値($758,040 等)は QPS 依存だが、各 finding の**結論**は QPS が誤りでも成立（しばしば補強）。

## moat 決断: governance-containment は opt-in（攻めが守りを部分代替）

**異なる前提タイプ2種（契約的 SLA + 確定事実 QPS）で invalidated=0 が再現**＝tracefield 自身の敵対的 best-of-N 合成は **post-serving の premise-falsification harm をほとんど生まない**。cross-domain の圧力が各 finding を複数角度から防御可能にし、単一前提依存を構造的に除去するため。

決断:
- **governance-containment（永続化＋撤回閉包）は default でなく opt-in が正しい**。これは**現状の実装設計を追認**する: consult は **攻め（best-of-N synth）を default-on**、**守り（`--persist`＋`mix tracefield.retract`）を opt-in** にしている。H9 はこの既定が正しいことを実データで支持した（e81 の「best-of-N を主軸・撤回追跡を opt-in」と一致）。
- **killer-context は狭い**: containment が効くのは findings が premise に無批判依存する場合だが、強い敵対的合成はそれを能動的に減らす。守りが主価値になるのは (i) 浅い/単一エージェント合成、(ii) 純粋な事実導出（cross-domain 圧力が無い）、(iii) 多段運用で前提が後から覆る頻度が高い領域、に限定される見込み。
- **新しい研究主張（F3 昇格）**: **強い攻め（敵対的 best-of-N 合成）は守り（撤回 containment）の必要を部分代替する**。これは攻め⇄守りが独立でなく相互作用することを示し、製品ポジショニング（攻めが主 moat）と一致。

## 残された検証（決断を覆し得る条件）
- 浅い合成（synth_n=1 / 単一エージェント / 弱モデル）で invalidated>0 になり containment が効くか（守りの killer-context の確定）。
- 多段運用（findings を跨ぐ長期 PJ）で前提が後から覆る自然頻度。
- F1 精緻 closure（stance/typed、#3 残りの prose stance 記録が前提）は invalidated>0 シナリオが取れて初めて意味を持つ。

## ハーネスの妥当性
測定器（`GovernanceVsFusion`）は機能した: keyword-GT のノイズ(F2)・GOV の過剰連結(F1)・そして**合成の premise 頑健性(F3)** を順に炙り出し、moat 決断を実データで導いた。再帰ドッグフーディング（tracefield で tracefield を分析→改善→検証）が、moat 戦略そのものを書き換える発見（攻めが守りを代替）に到達した。

## ハーネスの妥当性
測定器（`GovernanceVsFusion`）自体は機能：GOV の過剰連結(precision)と FUSION の保守性(recall)を同一 GT 上で定量化し、両者の不一致と GT の弱さを炙り出した。これは「測定器が研究上の本質的論点（containment precision と GT の意味論）を可視化した」＝再帰ドッグフーディングの所期の働き。
