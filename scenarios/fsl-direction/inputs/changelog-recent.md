# Changelog

The change history of this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versioning follows [Semantic Versioning](https://semver.org/). Each version corresponds to an annotated git tag (`v1.0.x`).

## [Unreleased]

## [2.0.0] - 2026-06-18

Theme: **human-readable business/requirements dialects** (issue #21) — verification
bounds, KPIs, and refinement mappings stop masquerading as model facts, and the
requirements layer gains a readable process+data profile close to the business surface.

### Added
- (Dialects) `entity <Name>` / `number <Name>` type-kinds and a top-level
  `verify { instances E = N ; values X = lo..hi }` block that holds the bounded-model
  sizes in one honest place. Kernel `type X = lo..hi` is unchanged.
- (Requirements) A `process <Entity> with <field>: <T> { ... }` profile: business-style
  `stages`/`initial`/`transition ... by`, extended with `with <input>`, `when <guard>`,
  `set <field> = <expr>`, and `covers REQ-n "text"` traceability. It lowers to a kernel
  state machine; an empty `implements X from "..." { }` body auto-generates the identity
  refinement when names match. Acceptance gains a readable `expect <Entity> <id> in <Stage>`.
- (Requirements) `maps auto` is now allowed inside an `implements { }` block.
- (Safety) Auto-mapped process transitions are statically actor-checked against the
  business layer (the verifier cannot — actors are not refinement state), so an actor
  mismatch is a check-time error instead of a green-but-wrong refinement.
- (Explain) `fslc explain --readable` renders a deterministic text view that surfaces
  verification bounds, fairness, KPI projections, branch lowering, and the synthesized
  refinement mapping (auto-mapped entries flagged for actor/intent review).

### Changed
- (Dialects) `kpi NAME = count ENTITY in STAGE` is now a declarative derived projection
  (available in business and requirements) carried as metadata — no ghost counter, no
  per-transition increment, no auto `_kpi_*` consistency invariant.
- The "spec declares no user invariants" warning no longer fires when the spec has
  leadsTo/reachable/trans properties, acceptances, forbidden flows, or an `implements`
  refinement (those are checked too).

### Removed
- **BREAKING:** business `case X = lo..hi` (use `entity X` + `verify { instances X = N }`).
- **BREAKING:** `kpi ... counts ... in ...` (use `kpi ... = count ... in ...`); the
  KPI counter-consistency auto-invariant and the "decrement KPI unsupported" error are
  gone (a projection is exact by construction).

## [1.5.0] - 2026-06-18

Theme: **honest verification bounds, AI-legible diagnostics, and tractable liveness** —
verify/induction results now declare their `completeness`, `checked_to_depth`, and `cost`;
diagnostics gain a `faithfulness_class` routing tag, split-action `display_name`s, sharper
`insufficient_depth`/`over_constrained` reachable classification, and a new `urgency_freeze`
vacuity lane; liveness gains ranking-function (`decreases`) proofs and `symmetric type`/`enum`
reduction; and the workflow adds `fslc chain`, partial `testgen`, `--exclude-property`, and
`maps auto`, plus a compose `fair`-not-inherited warning and friendlier identifier parse errors.

### Added
- (Temporal) FSL now supports `symmetric type` and `symmetric enum` declarations
  for interchangeable entity identities. `leadsTo` lasso and stall checks use a
  canonical representative for per-entity `Map<SymmetricType, ...>` / `Set`
  rows, reducing symmetric liveness search without changing the JSON envelope.
- (Induction) `leadsTo` declarations can now include `decreases <int expr>`.
  Under `fslc verify --engine induction`, fslc proves the response unboundedly
  with a ranking argument: the measure is non-negative while `P` is pending and
  `Q` is false, pending states cannot deadlock, and every enabled action either
  establishes `Q` or keeps `P` pending while strictly decreasing the measure.
- (Refinement) Mapping files now support `maps auto`, which synthesizes identity
  mappings for same-named compatible state variables and same-named compatible
  actions unless an explicit `map` or `action ... ->` entry overrides it.
- (Testgen) `fslc testgen` now generates partial pytest scaffolds when some
  `reachable` targets are not witnessed at the requested depth. Witnessed
  scenarios are still emitted, unwitnessed targets appear in `warnings[]` with a
  depth hint, and `--strict` restores the previous `reachable_failed` abort.
- (Vacuity) `fslc verify --vacuity` now emits `kind:"urgency_freeze"` for the
  requirements time/deadline trap where Z3 proves the generated urgent condition
  holds initially and is preserved by every action, so generated `tick` is dead
  and deadline invariants are vacuous.
- (Verifier CLI) `fslc verify --exclude-property <Name>` is repeatable and
  skips named invariants, `trans`, `leadsTo`, and `reachable` properties in both
  BMC and induction runs. It mirrors the 1.4.0 cross-kind `--property` resolver;
  exclusion wins when both options name the same property.
- (Verifier JSON) `verify` / induction results now expose boundedness metadata:
  `completeness`, `checked_to_depth`, and `cost.elapsed_s`. BMC `verified` is
  explicitly `completeness:"bounded"`, induction `proved` is
  `completeness:"unbounded"`, and bounded `verified` adds a saturation hint when
  normal exploration first witnesses a reachable/vacuity/coverage fact at depth K.
- (Reachability diagnostics) `reachable_failed.unreached[]` now classifies each
  target as `insufficient_depth` or `over_constrained`; over-constrained targets
  include a `blocking_requires` unsat-core-style list naming the blocking type
  bounds/invariants. The same classification is emitted by `fslc scenarios`.
- (Diagnostic routing) Diagnostics can now carry additive `faithfulness_class`
  and `recommended_action` fields for `partial_op_unguarded`,
  `frozen_only_invariant`, `intent_unexercised`, and the reserved
  `liveness_not_refined` route.
- (Diagnostics UX) Branch-split action diagnostics keep the internal action name
  and add `display_name` such as `submit[a <= AUTO_LIMIT]`. Coverage
  `blocking_requires` hints now summarize the blocking factors after a cheap
  core-minimization pass.
- (Chain CLI) `fslc chain [fsl-project.toml]` runs a manifest-defined
  business -> requirements -> design -> implementation pipeline, reusing the
  existing `check`, `verify`, `refine`, and shell implementation commands. It
  writes a consolidated status table to stderr, JSON to stdout, supports
  `--keep-going`, and exits non-zero when any layer fails.

### Changed
- (Parser/UX) Invalid identifier characters such as `foo$bar` now produce a
  focused parse diagnostic that states the identifier rule instead of leaking raw
  Lark terminal expectations.
- (Refinement) Mapping-file action formals now accept `name: Type` annotations,
  validated against the implementation action's declared parameter types.
- (Documentation) Clarified compose synchronized-argument compatibility as structural
  over bounded value ranges rather than nominal type names, including same-range
  and narrower-target repro results. Also documented action-level
  `maps stutter` in requirements/refinement docs and clarified that distinct
  fields of the same `Map<K, Struct>` element may be updated independently in
  one action.

### Fixed
- (Explain JSON) Counterfactual violation diagnostics no longer emit redundant
  raw `internal_invariant` compose names when the public `invariant` field already
  carries the dotted display name.
- (Compose) Non-fair synchronized actions that reference fair component actions
  now emit a `fair_not_inherited` warning instead of silently hiding the dropped
  composite-level liveness assumption.

## [1.4.0] - 2026-06-17

Theme: **probing single properties and friendlier IDs** — `verify --property`
becomes a general property probe across all declaration kinds, requirement-style
IDs accept underscores, and the liveness/safety scaling trade-off is documented.

### Added
- **`verify --property <Name>` now targets any property kind**, not just
  invariants. The name is resolved across `invariant`, `trans`, `leadsTo`, and
  `reachable` declarations and checked in isolation while the full action model
  still steps, so a single property can be probed on its own (e.g. iterating on a
  slow `leadsTo` without gating the safety checks).
- **Underscores are accepted in requirement-style IDs** (`REQ_ID`): `acceptance`,
  `forbidden`, `requirement`, `policy`, and `goal` IDs now allow `AC_DONE` in
  addition to `AC-DONE`, matching the underscore already permitted in
  action/invariant/trans names. Purely widens the accepted set — existing
  hyphenated IDs are unchanged.

### Changed
- **`--property` not-found diagnostics** now read `no such property: X
  (available: …)` and list every property kind. Under `--engine induction`
  (k-induction proves safety invariants only), naming a `trans`/`leadsTo`/
  `reachable` now reports that the induction engine cannot prove it and to use the
  default `bmc` engine, instead of a misleading "no such invariant".
- **Documented the liveness/safety scaling difference** (`skills/fsl/reference.md`
  §7): `leadsTo` cost grows roughly exponentially in the number of concurrent
  entities (the textbook BMC-liveness state explosion), while safety stays cheap.
  Added the practical strategy — verify liveness on a reduced model and safety
  separately at full size, and use `--property` to isolate one liveness property
  while iterating.

## [1.3.1] - 2026-06-17

Theme: **FSL delivery orchestration skill** — making the business → requirements →
design → implementation-conformance workflow directly invokable as a lifecycle
skill, while also adding readable business-stage syntax.

### Added
- **`fsl-delivery` Agent Skill**: a lifecycle coordinator that routes multi-layer
  work across `fsl-business`, `fsl-requirements`, `fsl-design`, and
  `fsl-design-review`, keeps layer boundaries explicit, and reports business,
  requirements, design/refinement, and implementation-conformance proof states
  separately. The install script and skill documentation now include it.
- **Readable fsl-biz stage syntax for PM/consulting-facing policies and goals**:
  `policy ... every Case in Stage must eventually be Target [or Target ...]`,
  `goal ... some Case can reach Stage`, and
  `goal ... all Case can be Stage [or Stage ...]`. These are AST sugar for the
  existing `responds` / `reachable` forms, so kernel semantics and JSON output
  remain unchanged while common business-flow rules no longer require reading
  `stage(c) == ... ~> ...` formulas.

## [1.3.0] - 2026-06-16

Theme: **propagation review for layer chains (fsl-design-review)** — establishing that
refinement propagates safety but not liveness, and adding end-to-end chain checking.
Also unifies the two FSL expression evaluators behind a shared, domain-parameterized core.

### Changed
- **Unified the symbolic (`bmc.py`, Z3) and concrete (`runtime.py`, Monitor) FSL evaluators**
  behind a single shared core (`src/fslc/values.py`) parameterized by a per-evaluator domain
  object (`_SymDomain` / `_ConcDomain`). The two evaluators previously re-implemented the same
  expression semantics, a drift hazard where the verifier and the replay Monitor could disagree.
  Unified: count, sum, quant, the Option/Seq/struct comparisons, `is`-patterns, field/index access,
  and map access. Behavior-preserving — the verdict-level output is byte-identical across the whole
  spec corpus, guarded by two new safety-net tests (`tests/test_corpus_snapshot.py`,
  `tests/test_evaluator_agreement.py`). Genuinely divergent pieces (Seq/Set method evaluators,
  `compute_updates`, `_eval_requires`, display) are intentionally left per-evaluator. Internal
  refactor only — no change to the CLI, JSON output, exit codes, or grammar.
- Split the over-long `cli.main`, `dialects.expand_business`, and `compose.expand_compose` into
  named private stages (no behavior change).

### Added
- **`fslc refine` chain mode (mapping composition)**: when you line up successive `(spec mapping)`,
  it composes adjacent mappings (states α_AC = α_BC ∘ α_AB, actions a→b→c / stutter) and
  checks **bottom ⊒ top directly**. On success it returns the composed `action_map` and `chain`; on failure it returns
  the first broken link, `failed_link`. Because bounded refinement is transitive at the same depth,
  the composition check is equivalent to all adjacent links holding (`DESIGN-refinement` §7, example `examples/refinement_chain`).
  State mappings are composed at the Z3 level, and indexed maps, Option, and structs are handled by the existing eval.
- Examples `examples/refinement_liveness` (safety propagates, liveness does not, resolved with fair) and
  `examples/refinement_chain` (chain checking), each with its own checking test.
- **A set of self-specs for meta-circular dogfooding** in `examples/self/`: three specs that model fslc's own design contracts
  in FSL (`fslc_session` = CLI result classification and exit-code severity,
  `fslc_monitor` = stickiness of replay-runtime rejection, `refinement_algebra` = safety
  propagates, liveness does not). All are proved. Pinned-result test `tests/test_self_examples.py`.
- **`terminal { <predicate> }` block (addressing DOGFOOD-11 F23)**: declares a halting state satisfying the predicate
  as an "intended terminal" and excludes it from deadlock checking. Whereas `--deadlock ignore`
  uniformly ignores all halting states, this lets you single out only the intended halts, while unexpected deadlocks are
  still detected. Used by `examples/self/fslc_session` and `fslc_monitor` (LANGUAGE §1/§6).
- **`fslc verify --property <Name>` (addressing DOGFOOD-11 F27)**: checks just a single invariant.
  This makes it easier to confirm a violation of a targeted invariant with a non-vacuous probe (a nonexistent name is a usage error = exit 2).
- **Vacuity detection of dead-ghost tautologies (addressing DOGFOOD-11 F22, top priority)**: `--vacuity`
  now statically detects with Z3 an "invariant that, when a frozen state variable assigned by no action is pinned to its init value, becomes
  always true regardless of the values of dynamic variables" (kind `tautology_over_frozen`). It warns at verification time about
  hollow (always-true) invariants that previously both verify and vacuity missed, surfacing only via mutate's survival rate.
  Invariants that do not reference a frozen variable / do not reference state are out of scope. Confirmed zero false positives across the existing corpus.
- **Transition invariant `trans { }` (addressing DOGFOOD-11 F24)**: `trans Name { old(x) => ... }`
  lets you directly declare cross-action two-state safety. BMC checks each reachable transition, induction checks it in the step case,
  successful output includes `transitions_checked`, and a violation returns `violation_kind:"trans"`.

### Fixed
- **Test suite runs without a `.venv` (CI portability)**: the subprocess-based tests invoked the
  CLI through a hardcoded `ROOT/.venv/bin/python` and a macOS-only `/private/tmp` scratch path,
  which failed on the CI runners. Now use `sys.executable` and `tempfile.gettempdir()`.
- **Include the state in the deadlock warning (addressing DOGFOOD-11 F26)**: the `--deadlock warn` warning
  message now shows which state it halted in (e.g. `deadlock reachable at step 1
  (state: status=ToolFault, ...)`). The state was previously only in the JSON `deadlock.trace`.
- **Soundness bug in `fslc refine`**: when an impl's violating transition reached a terminal (deadlock) state within the bound,
  forcing a full-length trace excluded the violation from all models, so it was missed
  (a non-monotonic behavior where raising the depth reduced detection). Resolved by switching to a dedicated solver that
  checks each prefix with only the constraints up to step t. Added a regression test (a residual case of the
  "vacuous refines" bug class in `docs/DOGFOOD-6.md`).

### Documentation
- **Rescoped the layer-chain propagation claim to safety**: in `DESIGN-layers` §1/§6 and `LANGUAGE` §10,
  made explicit that refinement propagates safety (invariants, control guards, behavioral inclusion) but not liveness
  (`leadsTo`/`responds`), because of stuttering, and that liveness must be re-verified at each layer
  with `fair` required on progress actions.
- **`docs/DOGFOOD-11.md`** (meta-circular dogfooding findings): records the blind spots where `--vacuity`/single verify
  miss "an always-true invariant over a variable that is never assigned (a dead ghost)" and it surfaces only via mutate kill-rate
  (F22), the absence of syntax for declaring intended terminal states (F23), the inability to directly
  assert a forbidden transition (F24), the expressiveness limits for relational/algebraic properties (F25), the deadlock-warn
  message lacking the state name (F26), and the absence of a single-invariant selector (F27).

### License / distribution (preparing for OSS release)
- **Finalized the license as Apache License 2.0** (rights holder: Copyright 2026 Ryoichi Izumita).
  Added `LICENSE` (full text) and `NOTICE`. Updated pyproject's license to the SPDX form `Apache-2.0`
  (previously only the `MIT` label with no LICENSE file), and tidied up authors, urls, classifiers, and keywords.
  Added an `SPDX-License-Identifier: Apache-2.0` header to all Python sources. The dependencies (lark / z3-solver) are
  both MIT and compatible with Apache-2.0.
- Updated the public repository URL to `github.com/ymm-oss/fsl` (links in README / install.sh / CHANGELOG,
  and reworded private-assumption phrasing for public release). Removed the generated search index `docs/index.bleve/` from tracking,
  added it to `.gitignore`, and also added Claude Code's local settings to the ignore list.

## [1.2.10] - 2026-06-15

Theme: **audit triage (issue #12) — settling two design decisions (doc alignment)**. We analyzed that
keeping the code as-is is appropriate and aligned the DESIGN documents with the actual state and intent.

### Documentation
- **Aligned the check ordering in DESIGN-refinement §2** with reality. For t>0 (between steps), the transition correspondence is checked
  before the type-bound check; for t=0 (initial state), the type-bound check (`map_out_of_bounds`) is done before the init correspondence.
  Because at t=0 a range escape almost always accompanies an init mismatch, we prioritize `map_out_of_bounds`, which can directly point at
  a mapping-expression bug — reflecting the design intent (the purpose in §2), and resolving the
  self-contradiction in the previous ordering description.
- Made explicit in **DESIGN-seq §5** the cross-engine difference for invariants containing unguarded partial Seq operations
  (`head`/`pop`/`at`). `verify`/`prove` (BMC) read don't-cares symbolically, while the runtime
  `Monitor` concretely returns `partial_op`. Because there is essentially no guarantee that a don't-care matches between symbolic and concrete,
  we strongly recommend the size-guarded idiom (the guarded version is verified to agree across both engines).

## [1.2.9] - 2026-06-15

Theme: **audit triage (issue #12) — settling design-decision items (continuation of Batch E-c)**.
Items previously treated as deferred were addressed in line with the recommendation, after verifying on real hardware.

### Fixed
- **A `push` to a full `Seq` was reported by the runtime (Monitor) as `partial_op`**; changed to report it as
  **`type_bound`** (a violation of the implicit `_bounds_*` length invariant), to match BMC / DESIGN-seq
  (`runtime.py`). This resolved the conformance fidelity gap where the same operation split into BMC=`type_bound` / runtime=`partial_op`.
  push always appends as a total function, and exceeding capacity is detected by the post-store bounds invariant.
- Added a note about the case where **`fslc refine` returns an impl's own invariant violation as-is**
  (`refine.py`). Clarified that this is a property of the refinement *input* (the impl spec), not the refinement verdict,
  so it is not confused with `refinement_failed` (LANGUAGE §10).
- (Documentation) Added to `parse()`'s docstring that if you need compose's display names you should use `parse_src`
  (`parse()` discards `display_names`, so dotted aliases appear under their physical names).

### Kept as-is by design decision (recorded in issue #12)
- The t=0 check ordering for refinement: there is tension between the ordering description in DESIGN-refinement §2 and
  `map_out_of_bounds`'s usefulness for "directly pointing at a mapping-expression bug," and existing tests expect bounds-first.
  We keep the current behavior, which precisely points at mapping bugs, and leave the §2 interpretation to maintainer judgment.
- Don't-care handling of Seq head/pop/at in invariant context: a guarded invariant is protected by short-circuiting,
  so the practical harm is small, and `in_invariant` propagation would be a broad change, so we keep the current behavior.

## [1.2.8] - 2026-06-15

Theme: **audit triage (issue #12) — runtime/refine/doc alignment batch (Batch E-c)**.
Items requiring design interpretation were addressed selectively after verifying on real hardware.

