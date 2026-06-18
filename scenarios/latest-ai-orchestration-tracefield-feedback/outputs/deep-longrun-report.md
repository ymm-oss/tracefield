# deep longrun report

format: markdown

## e91 (Synthesis)

Risk synthesis: Tracefield should model orchestration as an executable run graph, not prose prompt convention. Typed layer boundaries, handoff gates, span ids, and invalidation targets reduce opaque handoffs and make retraction repair targetable.

citations: e85, e86, e88

## e92 (Decision)

Decision: enforce separation of data/webpage, analysis, audit, and artifact production. Production must not fetch or analyze directly; each layer needs tool/context allowlists and pre-run gates to preserve provenance and independent auditability.

citations: e86, e89

## e93 (Requirement)

Close e90: artifact manifests must include artifact id, section id, source ids, trace/span ids, producer stage, eval status, retraction dependencies, freshness status, and repair owner. Publish blocks on missing citations, failed eval, stale sections, unresolved retractions, or unknown repair targets.

citations: e87, e90

