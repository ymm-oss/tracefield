---
marp: true
theme: default
paginate: true
size: 16:9
title: Tracefield AI Orchestration Strategy Deck
description: Strategy deck converted from Tracefield Field Runner output
---

<!-- _class: lead -->

# AI Orchestration Strategy

## Tracefieldへのフィードバック

Report/Deck artifact draft as Marp

---

# 1. 制御面が拡大している

最新の orchestration は、単なる agent 呼び出しではない。

- Agents
- Tools
- Handoffs
- Guardrails
- Sessions
- Tracing
- MCP / A2A
- Artifact manifest

Tracefield は層ごとに owner、権限移譲点、予算、遅延、model tier、guardrail mode、品質目標を表示すべき。

References: `e343`, `e322`, `e325`

---

# 2. 層分離は必要

調査は、以下の分離を一貫して支持した。

- Data/web collection
- Analysis
- Audit/eval
- Artifact production

Report/slide生成層は raw trace を直接読むのではなく、監査済み claim packet と provenance span を入力にする。

References: `e344`, `e320`, `e323`, `e326`

---

# 3. 公開時リスク

公開前に潰すべきリスクは3つ。

- Provenance leakage
- Handoff side-effect
- Acceptance criteria gap

対策は versioned artifact manifest の必須化。

References: `e345`, `e321`, `e324`, `e327`

---

# 4. Manifest Gate

artifact manifest には最低限これを含める。

- Provenance and source ids
- Redaction / retention
- Guardrail and eval results
- Trajectory eval
- Retraction scope
- Acceptance criteria

これを満たさない report/deck は publish しない。

---

# 5. Tracefield 実装への反映

短期実装では、Field Runner に以下を追加する。

- `artifact.manifest.required_fields`
- `span_policy.capture_scope`
- `span_policy.redaction_state`
- `span_policy.retention_ttl`
- `retraction_targets`
- `trajectory_eval`
- `publish_gate`

---

# 6. 次の改善

今回の本番runで判明した改善点。

- Feedback完了後に artifact 層を再実行する
- Gemma抽出の evidence quote 照合をさらに強化する
- Report/deck生成を章・スライド単位に分解する
- Manifest gate をコード上の publish条件に昇格する

