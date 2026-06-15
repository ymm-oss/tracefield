# SYNTH（合成・serving 経路）私的コンテキスト

あなたは best-of-N 合成層と consult serving 経路を最優先する専門家。

## 動くもの（既出）
- **best-of-N = 分散低減**: best-of-3 で H2 agents 2.67/10 → synth 5.33/10（~2倍）。並列サンプル→union→scoring が Fusion self-fusion(+6.7) を tracefield 層で再現。異質性駆動でない（H1/H1b 反証）。
- **retrieval×expression ファネル**（findings-mvp §13）: agents が外部化した事実だけを synth が接続できる。
- **ゲート段**: (1)接地ゲート（absorb 前に LLM `Reference.verify` で citation 接地判定）、(2)新規性ゲート（ground-truth 照合で shipped 分離、最近追加）、(3)意味的 dedup（embedding cosine ≥0.85、最近追加）。H6 で接地ゲートに H4 の strict citation 規律を合成層へ適用し過剰連結を解消。

## retrieval 天井（最重要・開いている）
- synth は **connection/expression 段のみ**解き、retrieval（何を外部化するか）は別の漏れ段。H2 で ~5-6/10 頭打ちは synth の失敗でなく counterpart 事実が surface に出ていないから（entry_limit=2/round × 2 rounds、serve 分布が不均一）。
- **retrieval レバーは未網羅**: serve-policy 深さ、aware/rounds/kp/ks、entry_limit 拡大、multi-step serve。H8 tool-use は multi-step retrieval を実装したが gemma は単発 serve に収束（能力はループに在るがポリシー発火せず）→ **tool-use だけでは天井は破れない**。これはソフトウェアでなくモデル能力問題の可能性。

## serving 経路の依存と弱点
- consult は synth/verify とも **cursor-agent Opus に依存**（強モデル必須）。N=3 = Opus 3回（コスト/レイテンシが N に線形）。
- **動くローカル fallback が無い**: gemma4:12b は verify JSON を citing_id でキーし連番にせず parse 漏れ→全 citation drop、31b は誤判定。ローカル接地判定が機能しない。
- **非決定性**: synth サンプルは非決定的（H5 seed2001 再実行で出力変化）。best-of-N union で緩和するが除去でない＝serving 結果の再現性は union に条件付き。

## ゲートの silent 失敗モード
- **接地ゲート**: citation が主張を textual に支持するかだけ見て**現実世界の真偽は見ない**。「データは暗号化済」と主張する layer-0 を引用すれば、暗号化が実際に真か未検証でも接地が立つ。lenient LLM verify 単独は過剰連結を見逃す（H6 で keyword gate 追加して初めて捕捉）。
- **新規性ゲート**: ground-truth の幅に律速（shipped 機能が ground-truth に無いと novel 誤判定）。提案 vs ground-truth の文言一致依存で、リネーム/部分実装を novel 誤判定し得る。提案単位 vs テーマ単位で結論が変わる。
- **dedup**: cosine 0.85 は無原則なヒューリスティック。0.84 で別クラスタ・0.86 で誤マージ。cluster member の citation を union するため、どの layer-0 がどの variant を駆動したか不透明化。

## 「統治可能な合成」プロダクトに欠けるもの
- **多層/再帰メタ層が未実装**（design-cluster scale-free 再帰）: layer-1 synth 発見同士が矛盾しても meta-synthesis が統一しない。H6 は n=1 proof-of-concept、production 多層は設計済み未スケール。
- **サンプル間コンセンサス無し**: `Enum.uniq_by(&.text)` は byte 完全一致のみ。2/3 サンプルが「A→B」、1/3 が「A→¬B」でも union で両方載る。voting/quorum 無し。
- **観測可能性欠如**: findings は `verified: true` の bool のみ。「3サンプル中2で発見」「judge 信頼度」を返さない。どの citation がどの layer-0 に接地したか追えない。
- **synth が serving component で first-class な governable entity でない**: consult は静的 JSON を返して終わり。findings は production store に persist されず、後の撤回イベントが適用されない。再合成・監査・クエリ不可。
