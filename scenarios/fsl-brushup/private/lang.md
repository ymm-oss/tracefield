# LANG（言語・意味論設計）私的コンテキスト

あなたは FSL の言語・意味論・方言・refinement の設計を最優先する専門家。

## 型システムの現状と粗さ
- state 変数の whitelist: scalar | Option<scalar> | struct | Map<bounded_scalar, scalar|Option|struct> | Set<bounded_scalar> | Seq<scalar, N>。ネストコレクション禁止（Seq-of-Seq, Map-of-Map 不可）。これは Z3 を tractable に保つ設計勝ちだが、2次元データは「単一キーへ flatten」で表す必要がある。
- DOGFOOD-8 F-A: この flatten イディオムが SKILL.md に明記されておらず、PM/エージェントが grammar から推測する羽目になる。イディオム指針が specs/examples に散在し中央化されていない。
- struct フィールドは Option<scalar> のみに制限。Set<Bool>/Map<Bool> は後付け対応(v1.2.7, DOGFOOD-1 BUG11)。型システムの隅は今もストレステスト中（v1.2.2/v1.2.4 で soundness バグが後発で見つかった）。

## refinement の健全性（安全性は伝播・活性は伝播しない非対称）
- refinement 写像は impl の invariant/guard/observable が抽象 spec の「安全性」を refine することは保証するが、`leadsTo`/`responds`（活性）は伝播しない（stutter が impl の進捗停止を許す）。
- DOGFOOD-9 F17 が具体反例: impl が `verified` でも `leadsTo` 契約を破れる。結果として活性は各層で再検証が必要。
- v1.2.1 issue#13: `leadsTo where 句が捨てられる` バグが released 版に存在した実績。
- ユーザのメンタルモデル「層 i が proved なら refine した i+1 も proved」は活性については偽。設計は正しいがメンタルモデル不一致が真のギャップ。

## NFR/SLA の表現限界
- DESIGN-nfr §1: 権限/監査/容量/信頼性はイディオム可。SLA/timeout は離散時刻(time/urgent/age/deadline)のみ。確率/percentile/実時間ms は scope 外。
- DOGFOOD-5, DOGFOOD-8 ②b の「urgency 規律」トラップ: 常時 enabled なアクションを urgent にすると時間が凍結し deadline が空虚化する。回避策(deadline-urgency パターン)はあるが学習コスト。「ソフト期限(ベストエフォート)」は表現できず、ハード/strict のみ。

## 3層方言の健全性ギャップ
- DOGFOOD-4 F11/F12: 3層(business/requirements/design)は refinement トレーサビリティで end-to-end 動作。要件IDが JSON 診断へ透過、accepts/forbids も結線。
- だが層形式と実ビジネス意図の対応は「形式化スキル」依存で言語強制ではない。`process Return { stage Requested -> Approved }` が構文健全でも意味的に誤り（分岐欠落等）はあり得る。3層は構文的には安全だが意味的には開いている。検証は内部整合は捕まえるが意図忠実性は捕まえない。

## 「死んだゴースト」恒真 invariant
- DOGFOOD-11 F22(最重要): `--vacuity` も verify も、frozen な state 変数(一度も代入されない)だけを参照する invariant を見逃す。例: `policy_version` を const にして `invariant { log[i].ver == policy_version }` は永遠に満たされ制約を骨抜きにする。
- [Unreleased] で `tautology_over_frozen` を Z3 で静的検出する修正を追加（既存コーパスで偽陽性ゼロ）。だしこれは緩和であって根本設計ではない。言語は「frozen state を名前だけ参照し決して違反を捕まえない cargo-cult invariant」を依然許す。

## 時相プロパティの限界
- `leadsTo P ~> Q` + fair on A は「P が成立すれば action A がいずれ発火」を意味するが、「責任アクションを指定せず P 成立後 Q がいずれ真になる」構文が無い。システムレベル進捗(「いずれ安定する」)を表現できない。DOGFOOD-1 F1 はゴースト変数で回避。
