# strategy deck supplement

format: slides_markdown

## e136 (Synthesis)

リスク表現は「agent性能」ではなく、handoff/supervisor/tool/context/traceを成果物統制へ変換できない場合の監査不能性に集中させる。未監査claim、権限逸脱、guardrail失敗、retraction範囲不明を主要リスクとして明示する。

citations: e118, e124

## e137 (Decision)

最終スライドはdata/webpage→analysis→audit→planning review→artifact productionの分離を中核にする。productionはraw sourceを読まず、claim単位のanalysis briefとaudit findingsのみから報告書・スライドを生成する制約として描く。

citations: e119, e122, e125, e130

## e138 (Requirement)

deck_finalize gateに、orchestration各claimのsource→claim→slide DAG、外部根拠、反証/confidence、retraction影響範囲、unused sources表示を検査する項目を追加する。

citations: e120, e126, e131

