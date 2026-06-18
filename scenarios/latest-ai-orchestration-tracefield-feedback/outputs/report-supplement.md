# executive report supplement

format: markdown

## e109 (Synthesis)

最終リスクは、調査結果をagent/tool/handoff/guardrail/trace単位で構造化せず、散文ログと内部相互引用だけで報告書/スライド生成へ渡すこと。権限境界、context境界、監査結果、retraction範囲、外部根拠が説明不能になる。

citations: e94, e100, e106

## e110 (Decision)

Field Runnerはdata/webpage、analysis、audit、artifact productionを固定層に分離し、productionはraw sourceを直読せず、analysis briefとaudit findingsのみを入力にする。production前に企画レビューとcitation coverage gateを通す。

citations: e95, e98, e108

## e111 (Requirement)

artifact manifestはsource→claim→artifact DAG、trace/span/tool/handoff、guardrail/eval/audit、目的・読者・意思決定、unused_sources、version、retraction/rebuild履歴を持ち、重複統合・独立根拠数・retraction伝播規則・停止条件を機械検証する。

citations: e96, e104, e105, e107

