# smoke report

format: markdown

## e27 (Synthesis)

Evidence: orchestration patterns combine delegation/handoffs/guardrails with graph State/Nodes/Edges. Risk: Tracefield should keep role/stage contracts distinct from runtime routing so provenance can identify collector, analyst, delegator, and validator.

citations: e21, e22, e24

## e28 (Decision)

Recommendation: finalize the report around separated layers: data/web collection, analysis, audit, and artifact production. Artifact production should consume audited claims through a manifest, not raw collection outputs.

citations: e25

## e29 (Requirement)

Add retraction support as a first-class event model: retraction_of, supersedes, affected_artifacts, and required rerun/audit policy. This closes the weak coverage left by SDK-style state and handoff models.

citations: e23, e26

