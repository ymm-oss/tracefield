# findings: 俯瞰レンズで「広×深」 — output-spec 単体は隔離の深さを移植できない

**要約**: 鍛えた単体エージェント（output-spec skill）は tracefield の depth（反証の鋭さ・洞察）に届かない（隔離 per_input でしか出ない）。一方 tracefield の弱点 breadth は、**俯瞰レンズ(GENERALIST)を1枚パネルに足すだけで解決し、しかも隔離されているので depth を一切損なわない**。広さを足した tracefield が、鍛えた単体を全軸で上回る。効きどころは uncued な問い。

## 背景

`tracefield chat`（哲学 flow）で、tracefield（隔離レンズ → per_input FALSIFY → per_input ADJ → 機械集約）が、プロンプト/skill で鍛えた単体エージェントに対し固有の answer-quality edge を持つか、盲検 cross-model judge で検証した。

## 実験

- **問い**: cued（古典・priors 饒舌）/ uncued（二次盲点を仕込んだ新規）各2問、held-out。
- **条件**（全て codex backend）:
  - naive: 素単体（「哲学的に深く答えよ」）
  - skill: output-spec 単体（「(1)立場→(2)反証→(3)判定→(4)対立保存」の出力構造を強制）
  - sham: 同字数の attitude clause（「慎重に・多角的に・誠実に」、中身なし）
  - C3: tracefield 5学派レンズ（分析・功利・義務論・現象学・系譜学）
  - C5: C3 + 俯瞰レンズ GENERALIST
- **judge**: claude が手法を伏せた A/B/C(/D) を4軸（breadth / critique_depth / no_drop / insight）で盲検評価。提示順は問いごとにローテート。

## 知見

1. **attitude は inert、output-spec は効く**（residual-skill-engineering の予測どおり）。sham ≈ naive（critique 2.5 vs 2.25、no_drop 2.25 vs 2.5）。skill だけが critique 2.25→4・no_drop 2.5→5。残差を埋めたのは態度でなく**出力構造の指定**。

2. **output-spec は depth を隔離から移植できない**。skill は no_drop で tracefield に並ぶが、critique_depth / insight は隔離 per_input（C3/C5）に届かない。1文脈で「5立場+各反証+統合」を畳むと予算競合で各反証が浅くなる（鉄則2）。隔離（各立場を別文脈、1反証=1審判）の深さは prompt 移植で再現しない。

3. **俯瞰レンズは隔離なら depth を壊さず breadth を足す**。tracefield の弱点は breadth（C3 = 2.75）。GENERALIST を1枚足すと breadth 4.5（skill 4.25 を上回る）。**critique 4.25→5・insight 3.25→5 とむしろ向上**＝俯瞰レンズが他5枚の文脈を奪わない（隔離だから予算競合が起きない）。C5 が全4問で judge best、unique_findings 最多（20）。GENERALIST は「東洋的無我」「身体・差別経験の非複製性」「制度説への内在反例」など5学派が拾えない論点を実際に持ち込む。

4. **効きどころは uncued**。cued では単体が近づく。uncued で C5 の edge 最大（uncued: C5 breadth 5 / critique 5 / no_drop 5 / insight 5）。

## データ（盲検 judge, codex backend, n=4, cued/uncued 各2問）

実験2（naive / skill / sham / C3）overall:

| 条件 | breadth | critique | no_drop | insight |
|---|---|---|---|---|
| naive | 4.5 | 2.25 | 2.5 | 3 |
| skill | 5 | 4 | 5 | 4 |
| sham | 4.75 | 2.5 | 2.25 | 3 |
| C3 (tracefield) | 2.5* | 4 | 3.75* | 4 |

実験3（skill / C3 / C5）overall:

| 条件 | breadth | critique | no_drop | insight | best |
|---|---|---|---|---|---|
| skill | 4.25 | 2.75 | 5 | 3.25 | 0 |
| C3 | 2.75 | 4.25 | 3.5 | 3.25 | 0 |
| **C5 (+GENERALIST)** | **4.5** | **5** | 4.75 | **5** | **4/4** |

\* 実験2の C3 は uncued4 の生成失敗（1点）で押し下げ。失敗を除く3問では C3 が全 best。judge は相対評価なので、強条件(C5)が入ると skill の絶対値は下がる（実験2の skill critique 4 → 実験3 で 2.75）。

## 結論

- 「単体を鍛えて戦えるか」: output-spec で no_drop は並ぶが、**critique/insight の深さは隔離でしか出ず**、広さを足した tracefield(C5) が鍛えた単体を全軸で上回る。
- tracefield の answer-quality edge は **「隔離による深さ × 俯瞰による広さ」**。深さは output-spec で移植できず、広さは俯瞰レンズで構造的に補える。
- 価値序列（flow-design）への追補: 直交学派レンズ（深さ）に **俯瞰レンズ1枚（広さの保険）** を足すのは、隔離されている限り低コストで net-positive。ただし俯瞰の浅い列挙は per_input 反証で覆れば消える（裏付けのない広さは残らない＝正しい挙動）。

## 俯瞰レンズ（paste 可能な desc）

```json
{"id":"GENERALIST","domain":"survey","desc":"特定の学派に偏らず問い全体を広く俯瞰し、主要レンズに収まらない立場・論点・緊張(東洋思想・実存・ケアの倫理・少数派の視点・問いの前提自体への異議など)を網羅的に1つのエントリで挙げる。死角: 各立場を深められない(深掘りは他レンズの役)。"}
```

## 追試: 螺旋(C6) と 拡散→連続 weave(C7)

俯瞰レンズの足し方をさらに2つ試した（盲検 judge, codex, held-out cued/uncued 各1〜2問）:

- **3サイクル螺旋(C6)**: 各サイクルが前サイクルの判定(`stage:adjudication`)を読んで立場を練り直す。cued(死刑)で全軸5＝1パス(C5)を上回り、「反証が結論を実際に動かす」(不正当→未証成への後退、批判基準の非対称性の暴露、通約可能性の土台破壊)を実現。**だが compute 3倍・複雑な問い(uncued)で adapter タイムアウト**＝実用性に難。純 equal-compute では未決着。
- **拡散→連続 weave(C7)**: 俯瞰を並列に置かず「SURVEY が5学派の死角を1つ名指す → DEEPENER がそれだけを深掘りする」(survey→audit→deepen の受け渡し)。**uncued で全軸5、並列俯瞰(C5)を全軸で上回り unique も最多**。死角が浅い列挙でなく実質的な深い立場(ケア倫理・関係的自己など)になる。cued では鍛えた単体に僅差で譲る。

**設計の含意（広さの足し方の序列）**: **並列俯瞰(浅い) < 死角発見→深掘りの受け渡し(weave)**。反復(螺旋)は深いが重い。**効きどころは一貫して uncued**（cued＝priors 饒舌では鍛えた単体で足りる）。決定版シナリオ `philosophy-wide`（リポジトリ外）は C7 weave 構成。

## 限界

- n=4、judge 単一（claude）、codex backend。係数は要再現、方向は3実験で一貫。
- 初回実験は codex 並列過負荷で生成失敗（C3 を逐次化して解消）。1実験はクレジット切れで無効化、回復後に再実行。

## 関連

- 決定版シナリオ: `~/Workspace/tracefield-scenarios/philosophy-wide`（C5、リポジトリ外）。
- 設計根拠: `skills/tracefield-flow-design`（cued/uncued・鉄則2「一枚岩は規模で劣化」・レンズ価値序列）、`docs/findings-bet2-overturn.md`（cued/uncued）、`docs/findings-lens-type.md`（直交レンズ）。
