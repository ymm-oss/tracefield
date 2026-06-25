# Design — Tracefield Field Runner

> Goal: define a generic staged execution runtime for Tracefield. The runner is
> profile-agnostic: long-horizon investigation, consulting analysis, development
> pipelines, QA loops, and other governed multi-agent flows are all expressed as
> `flow.toml` profiles.

## 1. Core Positioning

`tracefield run` is the generic command. It executes a configured field flow:

```text
input entries
  -> stage A
  -> stage B
  -> stage C
  -> output entries
```

The runner itself does not know about research, web pages, hypotheses, reports,
coding tasks, or QA. Those are profile concepts. The core runner only knows:

- stages;
- actor spawning;
- organ/model routing;
- budgets;
- feedback edges;
- gates;
- artifacts;
- persisted entries;
- citation-based provenance and retraction.

Every intermediate product is an addressable `Entry`. A profile defines which
entry types and metadata are expected at each stage. Because all outputs cite
their inputs, any retracted input can quarantine downstream entries through the
existing citation closure.

## 2. Core Execution Model

The runner loads:

```text
scenarios/<name>/
  task.md
  agents.json
  flow.toml
  inputs/
  private/
```

`agents.json` remains the static actor seed. `flow.toml` defines dynamic actors,
stage order, organ routing, budgets, feedback, and gates. `inputs/` is generic:
profiles may interpret it as web sources, product specs, issues, test logs,
customer documents, or any other source material.

Core loop:

```text
load scenario
seed task, inputs, private docs, and procedures into ReferenceStore
for each stage selected by FlowPolicy:
  resolve organ
  resolve actor scaling
  select input entries
  run actors or deterministic stage handler
  absorb output entries
  evaluate gates
  enqueue feedback edges if configured
persist store after each stage or budget batch
```

## 3. Flow Config

Minimal generic shape:

```toml
[flow]
profile = "deep_investigation"
policy = "fixed"
budget = 200
max_feedback_cycles = 3

[actor_scaling]
default_mode = "fixed"
max_total_actors = 24

[organs.local_data]
adapter = "cli"
command = "/path/to/ds4/ds4"
model = "/path/to/ds4/ds4flash.gguf"

[organs.reasoning]
adapter = "cli"
command = "codex"
model = "codex"

[feedback]
enabled = true
max_requests_per_cycle = 12
dedupe_by = ["normalized_request", "target_entry", "stage"]

[stages.<stage_id>]
organ = "reasoning"
budget = 20
inputs = ["entry_type:chunk"]
outputs = ["claim", "question"]

[stages.<stage_id>.actors]
mode = "auto"
min = 1
max = 4
scale_by = ["budget", "input_count", "open_questions"]
```

The concrete stage ids are profile-defined. Examples:

- `deep_investigation`: `source_discovery`, `source_cluster`, `source_extract`,
  `hypothesis`, `lens_analysis`, `audit`, `report`.
- `dev_pipeline`: `refine_issue`, `design`, `implement`, `qa`, `human_gate`.
- `qa_loop`: `collect_results`, `classify_failures`, `reproduce`, `fix_plan`,
  `verify`.

## 4. Stages

A stage is a typed transformation over the store:

```text
Stage {
  id,
  profile,
  organ,
  actor_policy,
  input_selector,
  output_contract,
  budget,
  gates,
  feedback_edges
}
```

Stage outputs are normal `Entry` values. The core runner should not special-case
profile terms. It should validate only generic contracts:

- output JSON is parseable;
- output entry types are allowed by the stage;
- citations point to known entries unless the profile allows external pending
  references;
- stage metadata records actor, organ, budget, and config version.

## 5. Organ Routing

Organs are named execution backends. Stages reference organs by name, not by
hard-coded model:

```toml
[organs.local_data]
adapter = "cli"
command = "/path/to/ds4/ds4"
model = "/path/to/ds4/ds4flash.gguf"

[organs.reasoning]
adapter = "cli"
command = "codex"
model = "codex"

[stages.extract]
organ = "local_data"

[stages.analyze]
organ = "reasoning"
```

The runner records the resolved organ and model in metadata for auditability.
Profiles decide why a stage uses a local or remote organ. For example,
`deep_investigation` may keep raw source extraction local and use Codex for
higher-level reasoning.

## 6. Actor Scaling

Actor count is stage-specific and config-driven.

| Mode | Meaning | Typical use |
| --- | --- | --- |
| `fixed` | use exactly `count` actors | known lens panel, final output |
| `per_input` | create actors from selected input entries | document extraction, log classification |
| `per_cluster` | create actors from profile-defined clusters | many web pages, many failing tests |
| `auto` | choose `min..max` actor count from signals | exploration, audit, triage |
| `none` | deterministic stage with no LLM actor | gates, export, simple validation |

Example:

```toml
[stages.analyze.actors]
mode = "auto"
min = 2
max = 8
scale_by = ["budget", "input_count", "open_questions"]
```

Automatic scaling must be explainable. Each stage records:

```json
{
  "actor_scaling": {
    "mode": "auto",
    "chosen_count": 4,
    "signals": {
      "input_count": 18,
      "open_questions": 6,
      "budget": 40
    }
  }
}
```

## 7. Feedback Edges

Flows are not restricted to one-way pipelines. Any stage can emit entries that
route work back to an earlier stage:

```text
stage C emits question/audit/failure
  -> feedback edge
  -> stage A reruns with a targeted request
  -> new entries
  -> stage C resumes
```

Generic config:

```toml
[feedback]
enabled = true
max_requests_per_cycle = 12
dedupe_by = ["normalized_request", "target_entry", "stage"]

[[feedback.edge]]
from = ["analyze", "audit"]
to = "collect"
entry_types = ["question", "audit"]
trigger_when = ["needs_evidence", "needs_refutation", "low_coverage"]
```

Every feedback request must cite the entry that caused it. This is the mechanism
that makes "why did the runner go back and collect more?" auditable.

## 8. Policies

`FlowPolicy` decides the next action:

```text
FlowPolicy::select_next_action(store, config, budget, open_work) -> FlowAction
```

Initial policies:

- `fixed`: execute configured stages in order, with bounded feedback cycles.
- `best_first`: prioritize open work with high score and weak evidence.
- `adaptive_branching`: allocate budget between broadening, deepening,
  verifying, refuting, and synthesizing.
- `multi_organ_adaptive`: like adaptive branching, but organ choice is also a
  policy decision when allowed by config.

The core policy interface is generic. Profile-specific actions are represented
as stage ids and entry metadata, not as Rust enum variants hard-coded for one
domain.

## 9. Gates

Gates are profile-defined checks over candidate entries. Core gate primitives:

- cited entries exist;
- cited entries are active;
- output entry type is allowed;
- required metadata exists;
- actor and organ are allowed for the stage;
- budget and actor caps are respected.

Profiles add domain gates:

- investigation: high-confidence synthesis requires audit pass;
- investigation: report and slide sections cite active findings;
- development: implementation output must cite accepted design entries;
- QA: pass verdict must cite test results;
- consulting: recommendation must cite client facts and risk review.

## 9.1 Artifact Production Layer

Artifacts are exported views over entries, not independent truth sources.
However, producing a strong report or deck is itself a reasoning workflow, not a
formatting step. The core runner therefore treats artifact production as a
generic layer with profile-defined stages:

```text
evidence entries
  -> artifact intent
  -> artifact plan
  -> artifact critique
  -> artifact draft
  -> citation/claim audit
  -> editorial revision
  -> export
```

The layer is generic. A profile may use it to create executive reports, slide
decks, QA summaries, release notes, design briefs, or implementation plans.

```toml
[artifacts.executive_report]
format = "markdown"
from_stage = "report_finalize"
path = "outputs/report.md"

[artifacts.strategy_deck]
format = "slides_markdown"
from_stage = "deck_finalize"
path = "outputs/deck.md"
```

Profiles define artifact contracts. The core runner only enforces that exported
artifact sections cite active entries and record their source entry ids. Possible
formats:

- `markdown`
- `json`
- `slides_markdown`
- `pptx` or `keynote` through a future exporter
- `html`

High-quality artifacts should be generated in layers:

```text
findings -> narrative strategy -> outline -> section drafts -> critique -> revision -> citation audit -> export
findings -> deck storyline -> slide specs -> slide drafts -> critique -> revision -> citation audit -> export
```

The exported file is reproducible presentation material. The authoritative
claims remain the cited Tracefield entries.

Every artifact export writes a sidecar manifest:

```text
outputs/report.md
outputs/report.md.manifest.json
```

The manifest records `source_entry_ids`, per-entry citations, the producing
stage, and artifact metadata. This keeps reports and decks auditable even after
they leave the JSONL store.

Recommended artifact actor roles:

- `artifact_strategist`: decides audience, objective, storyline, and decision
  framing.
- `artifact_architect`: designs report sections or slide sequence.
- `artifact_writer`: drafts sections, slide titles, takeaways, notes, and
  exhibits.
- `artifact_critic`: checks narrative coherence, missing caveats, executive
  usefulness, and overclaiming.
- `citation_auditor`: verifies that every artifact claim maps back to active
  entries.
- `artifact_editor`: applies critique and produces the final cited artifact
  entries.

## 10. Metadata

Recommended generic metadata:

```json
{
  "flow": "deep_investigation",
  "stage": "audit",
  "actor": "RISK-2",
  "organ": "reasoning",
  "model": "codex",
  "budget_step": 37,
  "parent": "e12",
  "actor_scaling": {
    "mode": "auto",
    "chosen_count": 4,
    "signals": {
      "input_count": 18,
      "open_questions": 6,
      "budget": 40
    }
  },
  "feedback": {
    "cycle": 2,
    "requested_by": "e42",
    "reason": "needs_refutation",
    "target_entry": "e31"
  },
  "artifact": {
    "kind": "strategy_deck",
    "section_or_slide": "slide_05",
    "export_path": "outputs/deck.md"
  },
  "profile": {
    "source_cluster": "CLUSTER:REGULATORY-JP",
    "lens": "market",
    "score": 0.71
  }
}
```

Profile-specific metadata lives under `profile` unless it is a core runner field.

Tracefield self-feedback is also a normal entry. It is routed by
`[feedback_entries]` when `meta.kind` matches:

```json
{
  "type": "change",
  "text": "Add one Codex web-discovery actor before Gemma source extraction.",
  "citations": ["e12", "e18"],
  "meta": {
    "kind": "tracefield_feedback",
    "target": "flow.stage.source_discovery",
    "action": "add",
    "priority": "high",
    "status": "proposed",
    "source_stage": "audit"
  }
}
```

Feedback targets are intentionally generic: `input.web`, `flow.stage.*`,
`flow.organ.*`, `artifact.*`, `gates.*`, and `profile.*`.

## 11. Core Invariants

The Field Runner should enforce these invariants for every profile:

1. Every generated entry records stage id, actor id or deterministic handler,
   organ, and config version.
2. Citations must point to known entries unless explicitly marked as external
   pending references.
3. Durable outputs must not depend on retracted entries.
4. Automatic actor scaling must respect configured `min`, `max`, and
   `max_total_actors`.
5. Every automatic scaling decision must record the input signals that produced
   the chosen actor count.
6. Feedback loops must respect `max_feedback_cycles`, `max_requests_per_cycle`,
   and global budget limits.
7. Feedback-generated work must cite the entry that requested it.
8. Exported artifacts must record the entry ids used by each section, slide, or
   output unit and write a machine-readable manifest.
9. Tracefield self-feedback must be persisted as cited entries before it is
   routed or applied.
10. Given the same store snapshot, config, and deterministic policy, planning
   decisions should be reproducible.

## 12. Profile: Deep Investigation

`deep_investigation` is the Marlin-like profile. It is not the core runner.

Profile flow:

```text
topic
  -> source_discovery
  -> source_cluster
  -> source_extract
  -> hypothesis
  -> lens_analysis
  -> audit
  -> artifact_strategy
  -> report_architecture
  -> report_draft
  -> report_critique
  -> report_finalize
  -> deck_storyline
  -> slide_spec
  -> slide_draft
  -> deck_critique
  -> deck_finalize
  -> artifact_export
```

Feedback:

```text
hypothesis/lens/audit question
  -> source_discovery
  -> source_cluster
  -> source_extract
  -> hypothesis/lens/audit resumes
```

Profile config excerpt:

```toml
[flow]
profile = "deep_investigation"
policy = "adaptive_branching"
budget = 200
max_feedback_cycles = 3

[organs.data]
adapter = "cli"
command = "/path/to/ds4/ds4"
model = "/path/to/ds4/ds4flash.gguf"

[organs.reasoning]
adapter = "cli"
command = "codex"
model = "codex"

[[feedback.edge]]
from = ["hypothesis", "lens_analysis", "audit"]
to = "source_discovery"
entry_types = ["question", "audit"]
trigger_when = ["needs_evidence", "needs_refutation", "low_evidence_coverage"]

[stages.source_discovery]
organ = "reasoning"
budget = 20

[stages.source_discovery.web]
enabled = true
profile = "balanced"
initial_target_pages = 40
hard_max_pages = 300
max_depth = 3
expand_when = ["open_questions", "low_evidence_coverage", "cluster_imbalance"]

[stages.source_cluster.clustering]
enabled = true
max_clusters = 16
by = ["source_cluster", "path_parent", "path"]

[stages.source_extract]
organ = "data"
budget = 40

[stages.source_extract.actors]
mode = "per_cluster"
min = 1
max = 12

[stages.artifact_strategy]
organ = "reasoning"
budget = 10
outputs = ["synthesis"]

[stages.artifact_strategy.actors]
mode = "fixed"
count = 1
roles = ["artifact_strategist"]

[stages.report_architecture]
organ = "reasoning"
budget = 10
outputs = ["synthesis"]

[stages.report_architecture.actors]
mode = "fixed"
count = 1
roles = ["artifact_architect"]

[stages.report_draft]
organ = "reasoning"
budget = 30
outputs = ["synthesis", "decision"]

[stages.report_draft.actors]
mode = "auto"
min = 1
max = 4
scale_by = ["section_count", "budget"]
roles = ["artifact_writer"]

[stages.report_critique]
organ = "reasoning"
budget = 10
outputs = ["audit"]

[stages.report_critique.actors]
mode = "fixed"
count = 2
roles = ["artifact_critic", "citation_auditor"]

[stages.report_finalize]
organ = "reasoning"
budget = 15
outputs = ["synthesis", "decision"]

[stages.report_finalize.actors]
mode = "fixed"
count = 1
roles = ["artifact_editor"]

[stages.report_finalize.artifact]
kind = "executive_report"
format = "markdown"
audience = "executive"
min_sections = 6
require_citations = true

[stages.deck_storyline]
organ = "reasoning"
budget = 10
outputs = ["synthesis"]

[stages.deck_storyline.actors]
mode = "fixed"
count = 1
roles = ["artifact_strategist"]

[stages.slide_spec]
organ = "reasoning"
budget = 10
outputs = ["synthesis"]

[stages.slide_spec.actors]
mode = "fixed"
count = 1
roles = ["artifact_architect"]

[stages.slide_draft]
organ = "reasoning"
budget = 30
outputs = ["synthesis"]

[stages.slide_draft.actors]
mode = "auto"
min = 2
max = 6
scale_by = ["target_slide_count", "budget"]
roles = ["artifact_writer"]

[stages.deck_critique]
organ = "reasoning"
budget = 10
outputs = ["audit"]

[stages.deck_critique.actors]
mode = "fixed"
count = 2
roles = ["artifact_critic", "citation_auditor"]

[stages.deck_finalize]
organ = "reasoning"
budget = 15
outputs = ["synthesis"]

[stages.deck_finalize.actors]
mode = "fixed"
count = 1
roles = ["artifact_editor"]

[stages.deck_finalize.artifact]
kind = "strategy_deck"
format = "slides_markdown"
audience = "executive"
target_slide_count = 12
require_speaker_notes = true
require_citations = true

[artifacts.executive_report]
format = "markdown"
from_stage = "report_finalize"
path = "outputs/report.md"

[artifacts.strategy_deck]
format = "slides_markdown"
from_stage = "deck_finalize"
path = "outputs/deck.md"
```

Discovery profiles:

- `quick`: 20-40 initial pages, hard cap around 80.
- `balanced`: 40-80 initial pages, hard cap around 300.
- `exhaustive`: 100-200 initial pages, hard cap set by operator policy.

Artifact stages:

- `artifact_strategy`: decides audience, objective, message hierarchy, and
  decision framing for the full artifact package.
- `report_architecture`: turns audited findings into an executive narrative
  outline, section hierarchy, key exhibits, and unresolved caveats.
- `report_draft`: writes report sections as cited `synthesis`/`decision`
  entries.
- `report_critique`: reviews the draft for narrative gaps, unsupported claims,
  missing caveats, and executive usefulness.
- `report_finalize`: applies critique and produces final report entries. The
  Markdown export is generated from these entries.
- `deck_storyline`: turns the same finding graph into a slide storyline,
  deciding what the deck must persuade the audience to understand or decide.
- `slide_spec`: defines each slide's purpose, takeaway, evidence, exhibit idea,
  and citation set.
- `slide_draft`: writes slide titles, takeaways, body bullets, exhibit notes,
  speaker notes, and citations.
- `deck_critique`: reviews storyline, slide order, claim strength, and citation
  support.
- `deck_finalize`: applies critique and produces final slide entries.
- `artifact_export`: exports Markdown or slide Markdown first; `pptx`, Keynote,
  or HTML exporters can be added later without changing the evidence model.

The deck and report may share findings but should not be identical. The report
optimizes for traceable detail and caveats; the deck optimizes for executive
storyline, decision framing, and visual exhibit specifications.

Deep investigation profile invariants:

- source discovery respects `hard_max_pages`, `max_depth`, and allow/deny
  domains;
- source clusters record member source entries;
- source extraction creates citable `observation` entries;
- high-confidence `synthesis` entries require audit pass;
- recommendations require at least one refutation attempt;
- report sections cite audited findings and source-backed observations;
- slide specs cite the entries that support the slide takeaway;
- slide titles must not introduce claims that are absent from the cited entries;
- finalized reports and decks require artifact critique and citation audit
  entries;
- retraction of a source page quarantines cluster observations and downstream
  conclusions, report sections, and slides that relied on it.

## 13. Other Profile Sketches

### Development Pipeline

```text
issue -> refine_issue -> design -> implement -> qa -> human_gate
```

Profile-specific feedback examples:

- QA failure -> implement;
- design uncertainty -> refine_issue;
- human rejection -> design or implement.

### QA Loop

```text
test_logs -> classify_failures -> reproduce -> fix_plan -> verify
```

Profile-specific actor scaling:

- `per_cluster` by failure signature;
- `auto` for reproduction attempts based on failure count and flakiness.

### Consulting Analysis

```text
client_docs -> fact_extract -> lens_analysis -> risk_review -> recommendation
```

Profile-specific gates:

- recommendations cite client facts;
- recommendations cite risk review;
- high-impact recommendations cite financial or operational evidence.

## 14. First Useful Slice

Build the core runner first, then one profile.

Core slice:

1. load `flow.toml`;
2. seed generic `inputs/`;
3. execute configured stages with fixed policy;
4. route stages to named organs;
5. record actor scaling metadata;
6. persist after each stage;
7. enforce core citation and retraction gates.

First profile slice:

1. implement `deep_investigation` with local source files, not live web;
2. create one source cluster;
3. extract observations with `organs.data`;
4. analyze and audit with `organs.reasoning`;
5. generate cited report entries;
6. generate cited slide specs;
7. export Markdown report and slide Markdown deck;
8. retract one input and show affected report sections and slides.
