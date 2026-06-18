---
marp: true
paginate: true
---

# ds4 complete deck

format: slides_markdown

---

## リスク: 設計単位を混ぜると監査不能になる
- Evidence: handoff、supervisor、workflow graph、tool/context protocol は同じ抽象ではない（e52/e41）。
- Evidence: OpenAI根拠で強いのは handoff、central supervisor、trace/span、guardrails/tripwires まで（e45）。
- Risk: 委譲判断、状態遷移、責任境界を1つの設定に畳むと、失敗時に誰が何を根拠に動いたか追跡できない。
- Recommendation: Field Runner config は handoff contract、supervisor decision policy、workflow state schema、guardrail policy、trace/span provenance を分離する。

Notes: Tracefieldの設計レビューでは「便利な統合」より「後から切り分けられる境界」を優先する。

<!-- citations: e52, e41, e45, e48 -->

---

## 決定: 層分離を報告書生成の前提にする
- Evidence: data/webpage、analysis、audit、artifact production を分ける戦略が支持されている（e53）。
- Evidence: 各層で input/output、tool guardrails、tripwires、trace/span id、worker behavior、sensitive-data class を記録すべき（e53）。
- Decision: artifact production 層は分析を再実行せず、監査済み entry と manifest から slide/report を組み立てる。
- Constraint: audit 層は recommendation と evidence を分離し、artifact 層はその分離を崩さない。

Notes: スライド生成AIは「考える」が、根拠生成者ではなく、監査済み材料の編集者として振る舞う。

<!-- citations: e53 -->

---

## 決定: Artifact Manifest を必須成果物にする
- Evidence: manifest には source entries、agent/layer、handoff source/target、workflow state version、guardrail results、trace/span id が必要（e54/e49/e46）。
- Evidence: retraction/rerun capability を持たない artifact は撤回影響を追跡できない（e54/e46）。
- Decision: report/slide 生成時は manifest 不在なら publish 不可にする。
- Constraint: manifest は証拠、recommendation、生成物の対応関係を固定し、撤回時に影響スライドを特定できる粒度で保持する。

Notes: 最終デッキは見た目の完成物ではなく、再生成可能な監査対象として扱う。

<!-- citations: e54, e49, e46 -->

---

## 制約: 未確定プロトコルは設定へ固定しない
- Evidence: OpenAI SDK の tool/context protocol 詳細は根拠が弱く、一次説明ページの再収集が必要（e47/e44）。
- Evidence: workflow graph の State/Node/Edge は LangGraph 側の証拠に依存し、OpenAI SDK 由来としては扱えない（e45）。
- Risk: ベンダー固有の未確定語彙を Field Runner の永続 schema に入れると、後続実装の互換性リスクが高い。
- Recommendation: protocol semantics は adapter 層に閉じ込め、manifest には観測済み event、trace/span、guardrail result として記録する。

Notes: 抽象化は「共通語彙」ではなく「撤回可能な対応表」として設計する。

<!-- citations: e47, e44, e45 -->

