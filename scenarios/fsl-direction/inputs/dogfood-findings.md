# Dogfooding Round 1 — Findings (2026-06-11)

We field-tested v1.0 against four real-domain specs (`specs/auth_lockout.fsl`, `specs/inventory_reservation.fsl`,
`specs/payment.fsl`, `specs/rate_limiter.fsl`) plus seven edge probes.

## Results Summary

| Spec | Result |
|---|---|
| auth_lockout (depth 8) | verified. witness: LockedOut@3, RecoveredAfterLock@5. coverage all true |
| inventory_reservation (depth 5) | verified (48s). AllHeld@3. **depth 8 aborted after an estimated 30+ minutes** (PERF1) |
| payment (depth 6) | verified (4.3s). FullyRefunded@3. coverage all true |
| rate_limiter (depth 6) | verified (0.2s). Exhausted@4. coverage all true |

## New Bugs

### BUG11: check passes a composite struct field type, then verify hits an internal error

- `struct S { v: Option<K> }` → at the time, check ok, but verify hit `kind: "internal", message: "'s__v'"` (raw KeyError).
  In v2.1 this is now formally legalized as an `Option<scalar>` field.
- `struct Outer { i: Inner }` (struct nesting, explicitly marked "not allowed in v1" in design §3.4) → likewise `"'o__i'"`
- `struct S { members: Set<K> }` → verify raises a misleading semantics error
- **Expected behavior**: `check_spec` validates struct field types and rejects anything other than domain / enum / Bool / Int /
  `Option<scalar>` (Set / Map / Seq / struct / nested Option) with `kind: "type"` + hint
  (e.g. "struct fields must be scalar or Option<scalar>; use a separate Map for Set/Map/Seq/struct fields").
  This follows the "every failure has a next move" principle of the repair protocol (§8).

### BUG12: exclusive branches of a nested if/else mis-detected as a "double assignment"

```fsl
action step() {
  if x == 0 { x = 1 }
  else { if x == 1 { x = 2 } else { x = 0 } }
}
```

- → `semantics: double assignment to 'x' on the same execution path` (wrong; the three assignments are all on exclusive paths)
- Cause: `run_into_if` in `bmc.py` (used for nested ifs) does not save/restore `scalar_writes` between the then/else evaluations.
  The outer if's `run_branch` (L572-576) resets it correctly.
- **Expected behavior**: `run_into_if` should also save and restore `scalar_writes` per branch,
  permitting the same variable to be assigned across exclusive paths (true same-path double assignment is still detected).

### BUG13: when an invariant containing `is some(x)` is violated, JSON serialization crashes

```fsl
invariant Match { c is some(j) => j == target }   // when violated…
```

- → raw traceback `TypeError: Object of type ArithRef is not JSON serializable`.
  The violation is detected, but output dies (the worst failure mode for an LLM repair loop).
- Cause: the is-pattern in `eval_expr` leaves a Z3 expression (ArithRef) in `binds`, and
  `violating_bindings` (bmc.py:935-937) passes the raw Z3 AST into the result dict via `_public_bindings(dict(binds))`.
- **Expected behavior**: bindings values should be concretized via `model.eval(...)`, with enums reverse-mapped to display names on output.
  Alternatively, exclude pattern-bound variables from bindings. The violation JSON must always be serializable.

### BUG14: an assignment after an if silently overwrites a write inside the branch (asymmetric detection)

```fsl
action go() {
  if flag { x = 1 }
  x = 2          // ← no error, and x = 1 silently disappears
}
```

- Placing `x = 2` **before** the if correctly raises a double assignment error, but placing it **after** lets it
  pass through, and x ends up 2 even when flag is true (a silent divergence from the author's intent = a soundness problem).
- Cause: the if handling in `compute_updates` restores `scalar_writes` to its pre-if state after evaluating the branches,
  so writes recorded inside a branch are invisible to subsequent statements. Present in both top-level
  (`run`'s if) and nested (`run_into_if`) handling.
- **Expected behavior**: after handling an if, record the **union** of scalar keys written in the then/else branches into
  `scalar_writes`, so a subsequent assignment to the same variable is an error.

### PERF1: BMC is exponential in depth (about 4x per step)

- `inventory_reservation.fsl`: state = Map×2 (including struct values), 3 actions (~36 instances/step),
  and one invariant containing sum(). Measured: depth 2 = 0.46s, depth 4 = 7.8s, depth 5 = 48s
  (about 4x per step). depth 8 aborted after an estimated 30+ minutes.
- Structural factors (bmc.py):
  1. each `reachable` **redoes the full unrolling in a fresh Solver** (verify body + R times × full unrolling)
  2. the ensures check re-evaluates `_eval_requires` and does push/pop for every instance × ensures
  3. every struct assignment generates an ite tree, and expressions can compound and blow up along depth
- Mitigation approaches considered for v1.1 (incremental solver sharing, expression caching, intermediate-variable assignments, etc.).

## Expressiveness Findings (feedback for language design)

- **F1: reachability that talks about the "past" requires a ghost variable.** auth_lockout's
  "can recover after being locked out" was expressed with an `ever_locked` ghost variable.
  As a workaround it is straightforward, but recorded as a concrete example motivating v2.0's `leadsTo`.
- **F2: the binding scope of `is some(j)` reaches the right-hand side of `=>`** (confirmed in probe2; verified is also correct).
  However, design doc §3.3 has no scoping rule — it should be made explicit that "within a logical expression containing `is`,
  the binding is in effect only in contexts where the `is` evaluation is true".
- **F3: a real example surfaced where not being able to write an Option field in a struct is inconvenient.** (resolved in v2.1)
  inventory_reservation really wanted to be written as `Res { item: Option<ItemId> }`, but it was worked around with an
  enum state (item is a meaningless 0 when Free). In v2.1, `Option<scalar>` fields are handled directly via synthetic lowering.
- **F4: orthogonal feature combinations are largely sound.** lvalue subscripts via let, bulk struct assignment,
  sum with an arithmetic-expression body + composite where, count/min/max/abs, Set<Enum>, ghost variables,
  and clamping via const + min — all behave as expected (confirmed in probe2/4/5 and auth_lockout).

## Probe List (candidates for regression tests)

| Probe | Content | Result |
|---|---|---|
| probe1 | Option as a struct field | OK in v2.1 (`Option<scalar>` only) |
| probe2 | does the `is some(j)` binding reach the RHS of `=>` | OK (verified) |
| probe2n | negative case of probe2 (should be violated) | BUG13 (JSON crash) |
| probe3 | `else { if … else … }` nesting | BUG12 (false double assignment) |
| probe4 / 4n | positive/negative case of Set<Enum> | OK / OK (violated@1) |
| probe5 | count/max/abs + count under reachable | OK (witness@2) |
| probe6 | struct nesting (not allowed by design) | same class as BUG11 (internal error) |
| probe7 | Set as a struct field | same class as BUG11 (wrong message) |
| probe8 / 8r | same-variable assignment after/before an if | BUG14 (after: pass-through / before: detected) |

## Status

- BUG11 / BUG12 / BUG13: **fixed** (codex round, 6 regression tests added).
  Of BUG11, `Option<scalar>` fields are legalized in v2.1; the other composite fields are a type error.
- BUG14: **fixed** (propagates the union of branch writes to subsequent statements; regression test added)
- PERF1: **resolved**. Sharing the unrolling (invariant/reachable/deadlock/coverage all ride on a single unrolling),
  Implies-form transitions, expression caching, and strengthening with proven invariants give:
  - inventory depth 5: 48s → 2.2s, depth 8: 30+ min → **5.4s**
  - whole test suite: 57s → **3.5s**
  - profiling conclusion: the bottleneck is Z3 solver time, not the Python side
    (full re-unrolling per reachable was dominant)
- 33 tests green in total. Results unchanged for all sample specs.
# DOGFOOD-10: Fault-Injection Benchmark — Measuring Detector Catch Rate by Type × Mechanism (2026-06-14)

issue #8. We ran the detector suite implemented in #3–#7 by **injecting known errors into correct specs and
measuring what catches what**. An effectiveness measurement that makes roadmap #1's own proposal verifiable.

Harness: `tests/test_injection_bench.py` (extends the gallery's "expectation declaration → JSON match" to multiple
detectors). Corpus: `examples/gallery/injected/` (3 domains × 7 injection kinds = 21 specs. Each spec has a
`// inject:` `// expect-detector:` `// expect-signal:` declaration header). The measured matrix is regenerated into
`examples/gallery/injected/MATRIX.json`.

Domains: `bank` (specs/bank*), `order_workflow` (specs/order_workflow),
`return_system` (the returns domain in examples/layers).

## Result: Catch-Rate Matrix (stable 3/3, exact match with prediction)

Each injection is caught **only in the predicted lane**, and all other detectors pass it through (each cell's
caught/not-caught matches across all 3 domains. `surprises: []` = zero divergence from prediction).

| Injection (type) | verify | --vacuity | --strict-tags | strict-tags +ids | mutate | forbidden/acc |
|---|---|---|---|---|---|---|
| guard over-strengthening (over-constraint 3) | **✓** | – | – | – | – | – |
| invariant with unreachable antecedent (vacuous 5) | – | **✓** | – | – | – | – |
| adding a constraint not in the NL (fabrication 7) | – | – | **✓** | – | – | – |
| dropping a requirement (omission 7) | – | – | **✗** | **✓** | – | – |
| invariant weakening (under-constraint 4) | – | – | – | – | **✓** | – |
| boundary flip `<=↔<` (mistake 6) | – | – | – | – | – | **✓** |
| guard weakening (under-constraint 4) | – | – | – | – | – | **✓** |

(✓ = caught, ✗ = the same detector but the condition is not met so not caught, – = not applicable)

## Insights

- **F18: each detector has a non-overlapping lane.** None of the 7 injections ends up in a "everything catches it"
  state; **exactly one mechanism** caught each. A design that is neither redundant nor leaving gaps was backed up by
  measurement. verify (over-constraint) / vacuity (vacuous) / strict-tags (fabrication) / mutate
  (under-constraint = invariant) / forbidden (under-constraint = guard, mistake) divide up the territory.

- **F19: a mistake (boundary flip) and guard weakening are caught only by an independent channel
  (forbidden/acceptance).** verify, vacuity, strict-tags, and mutate all pass them through. These are
  "internally perfectly consistent but different from intent" errors, and **positive/negative traces written from
  the NL by someone other than the spec's author** are the only net. The reason for #3 forbidden / D4 to exist is
  fixed numerically.

- **F20: pure omission is undetectable in principle without a requirements registry.** The dropped-requirement
  injection is **not caught** with `--strict-tags` (plain), and caught only with `strict-tags +ids` given
  `--requirements ids.txt`. The absence of a requirement the spec never once mentions becomes visible only with an
  external declaration (ids registration / an empty requirement block).

- **F21: invariant weakening is visible only in mutate's delta.** Standalone verify of the weakened spec passes
  (a weaker invariant). It is detected by `fslc mutate`'s survivor count increasing relative to baseline (this
  harness judges a survivor increase from baseline → injected as caught). A single run only says "many survivors",
  so **comparison against baseline is the condition**.

## Holes in the Detection Net (→ remaining territory)

On the matrix "every injection is caught in one lane", but per F19/F20 **it does not close with automation alone**:

1. **Mistake / guard weakening**: forbidden/acceptance is needed, and its positive/negative traces are input
   **written from the NL by a human or an independent agent**. Not auto-generated.
2. **Omission**: a maintained ids registry is the prerequisite.
3. The final bastion for these is **back-translation diff (D5, the skills/fsl workflow)** — an agent that has not
   seen the original text renders the `.fsl` into natural language and reconciles items against the requirements.
   This benchmark fixes the "territory of the automatic detectors" and demonstrates the picture in which the
   **outside** of it is borne by the independent channel / back-translation.

There is **no "uncovered type"** requiring a new issue (every injection has a corresponding lane). However, 1–3
above are not "holes in the detectors" but operating conditions of "**human / independent-channel input is the
prerequisite**", and are already recorded in skills/fsl and #2.

## Out of Scope (future)

The original idea of "measuring generation quality by skill version" (have a different AI formalize with the plain
skill / +memo / +positive-example pair and compare error rates) was separated out from this benchmark because it is
a non-deterministic live experiment (lineage of DOGFOOD-8 blind writability. A separate manual DOGFOOD in the
future).

## Reproduction

```bash
./.venv/bin/python -m pytest tests/test_injection_bench.py -q   # regenerates the matrix into MATRIX.json
```

A calibration asset that can be re-run when the model/detectors are updated. Measures 21 injections × 6 detectors in
about 60 seconds.
# DOGFOOD-11: Meta-Circular Dogfooding — Verifying fslc's Own Design Contract in FSL to Expose the Detectors' Blind Spots (2026-06-15)

DOGFOOD 1-10 targeted external domains such as banking, reservation, and SLA. This time, for the first time, we
modeled fslc's own behavioral contract — meta-circular dogfooding. The artifacts are the 3 specs in
`examples/self/`.

## Results

- `fslc_session` formally proved the CLI exit-code severity classification: success requires check pass,
  proved⊒verified, internal errors non-repairable.
- `fslc_monitor` proved replay reject-stickiness: once nonconformant is irreversible, conformant only when all steps
  ok.
- After the fix, `refinement_algebra` non-trivially checks "safety propagates, liveness does not".

## Insights

- **F22 (most important, a detector blind spot):** neither --vacuity nor a single verify detects a "tautological
  invariant over a state variable that is never assigned (a dead ghost)". The first draft of refinement_algebra was
  verified with 0 vacuity warnings, yet its mutate kill-rate was 6.4% (73/78 survived). The other 2 were 71%/67%.
  The mutate survival rate was the only indicator of hollowing (an extension of DOGFOOD-10 F21 "invariant weakening
  is visible only in mutate"). Improvement candidate: it closes cheaply if the vacuity check can statically warn on
  an "invariant/consequent that references only variables that are assigned by no action".

- **F23 (design/language gap):** there is no syntax to declare an intended terminal state (proved/conformant/
  tool_fault, etc.), so the only option is to apply --deadlock ignore globally → unintended deadlocks get hidden at
  the same time. repair_loop.fsl also requires --deadlock ignore for the same reason. A per-state/per-action
  terminal/final annotation would distinguish intended halting from a bug.

- **F24 (language gap):** there is no property syntax to directly assert "from this state this action cannot fire /
  this transition is forbidden", so it can only be expressed indirectly with ghost+guard. Occurred in all 3
  (RejectIsSticky / NoStepAfterReject / ToolFaultNotRepairable).

- **F25 (expressiveness):** relational/algebraic properties like reflexivity and transitivity of refinement cannot
  be written as axioms; one can only "simulate the process" as a state machine. This tends to invite the dead-ghost
  trap of F22 (demonstrated by refinement_algebra).

- **F26 (minor):** the --deadlock=warn warning message string lacks the deadlock state name ("deadlock reachable at
  step N" only). The JSON deadlock.trace contains the full final state (bmc.py:2851 just doesn't put it in the
  string).

- **F27 (testability):** there is no means to check targeting a single invariant only (an equivalent of
  --property/--invariant). verify checks all invariants at once and reports "the first violation found", so even
  when you want to confirm a violation of a specific invariant (e.g. SafetyPropagates) with a non-vacuity probe, a
  more general invariant (SafetyPreservedAtEveryLayer) gets reported first, requiring effort to narrow conditions so
  the targeted invariant becomes the reported one. A single-property option is a candidate to improve probe
  precision.

## Modification Status

Of the findings the investigation surfaced, those for which code modification was begun:

| Finding | Action | Status |
|---|---|---|
| F23 (declaring intended halting) | Added a new `terminal { <predicate> }` block (grammar/model/bmc). Halting states satisfying the predicate are excluded from the deadlock check. Made examples/self terminal and removed the `--deadlock ignore` dependency | **done** (`94cf68f`) |
| F26 (deadlock state display) | Include the state in the warn message. E.g. `deadlock reachable at step 1 (state: status=ToolFault, ...)` | **done** (`94cf68f`) |
| F27 (single-invariant check) | Added `verify --property <Name>`. A nonexistent name is a usage error (exit 2) | **done** (`94cf68f`) |
| F22 (dead-ghost tautology) | Added to `--vacuity` a Z3 static detection of an "invariant that becomes a tautology regardless of the dynamic variables' values, when frozen variables assigned by no action are fixed to their init values" (kind `tautology_over_frozen`). Invariants that reference no frozen variable / reference no state are excluded. Tidied refinement_algebra's trivial baseline ghosts (mutate kill-rate held at 77.2%). Confirmed zero false positives across the entire existing corpus | **done** |
| F24 (transition-forbidden syntax) | Added a new transition invariant `trans { old(x) => ... }` (grammar/model/bmc/runtime). Two-state safety across actions can be declared directly, expressing the self-spec's sticky/irreversibility properties without a ghost. Checked by BMC + induction step-case + replay (DESIGN-trans.md) | **done** |
| F25 (expressiveness of algebraic properties) | An essential limit of the language. Out of scope for modification | deferred |

## Anchoring to Implementation Conformance (Model Verification → Implementation Verification)

Initially the self-spec was **a model describing fslc's design contract**, and what `verify`/induction proved was
only **the model's internal consistency**. There was no link between the model and the real code (`src/fslc/cli.py`),
so "does the implementation uphold this contract" was unverified — the core gap of this project (what fslc
guarantees is "internal consistency of the written spec", not "fidelity of the spec to reality") applied to the
self-spec too.

`tests/test_self_conformance.py` filled this gap. It runs the real CLI pipeline (check → verify → induction) over a
spec corpus producing diverse outcomes, and:
1. each result and the process exit code match `exit_code()`'s severity table (the real exit code is checked
   directly),
2. `ProvedImpliesVerified` / `SuccessRequiresCheck` hold on the real results,
3. the real result sequence is mapped onto `fslc_session`'s action sequence and `fslc replay` is **conformant**
   (the real CLI's transitions conform to the model state machine),
4. a hand-written contract-violating trace is **nonconformant** (`verify_ok` alone is rejected by
   `requires status==CheckOk` = the anchor has teeth, a negative control).

With this, meta-circular dogfooding was lifted from "model verification" to "**implementation-conformance
verification**".

Coverage was then extended further:
- **fslc_session**: in addition to the core check→verify→induction, a verify-time user error
  (added a `verify_user_error` action; check passes only syntax/type but verify becomes a semantics error, e.g.
  no_actions.fsl), and the auxiliary subcommands (scenarios/explain/mutate/typestate/refine success·failure/replay
  conformant·nonconformant) are run against the real CLI, mapped onto actions, and confirmed conformant.
- **fslc_monitor**: runs the real `Monitor`/`run_replay` on a guarded spec (cart_v1) for normal / mid-way reject /
  empty log, directly asserting that "halt on the first reject and process nothing afterward (confirmed via
  `failed_at_event` and log length)" matches NoStepAfterReject + replays it into the monitor. The negative controls
  (step_ok after reject, etc.) are nonconformant.

The only unanchored case is **tool_fault (internal error = exit 3)** — because internal errors are not triggered
deliberately (it is kept in the model). Within the current corpus, there is no discrepancy between the model
contract and the real behavior.

## Reproduction

```bash
E=examples/self

# fslc_session / fslc_monitor have terminal { } declarations, so --deadlock ignore is not needed
./.venv/bin/python -m fslc check  $E/fslc_session.fsl
./.venv/bin/python -m fslc verify $E/fslc_session.fsl
./.venv/bin/python -m fslc verify $E/fslc_session.fsl --engine induction
./.venv/bin/python -m fslc mutate $E/fslc_session.fsl

./.venv/bin/python -m fslc check  $E/fslc_monitor.fsl
./.venv/bin/python -m fslc verify $E/fslc_monitor.fsl
./.venv/bin/python -m fslc verify $E/fslc_monitor.fsl --engine induction
./.venv/bin/python -m fslc mutate $E/fslc_monitor.fsl

./.venv/bin/python -m fslc check  $E/refinement_algebra.fsl
./.venv/bin/python -m fslc verify $E/refinement_algebra.fsl
./.venv/bin/python -m fslc verify $E/refinement_algebra.fsl --engine induction
./.venv/bin/python -m fslc mutate $E/refinement_algebra.fsl
```
# Dogfooding Round 2 — Findings (2026-06-11)

We put all of v1.1's features (Seq / k-induction / unsat core diagnostics / scenarios) into real use and
evaluated **"a workflow where proved is the standard"** (not stopping at BMC verified, but going all the way
to an unbounded-depth proof via CTI → auxiliary invariants). Three specs: `specs/mutex_queue.fsl`
(FIFO mutex), `specs/job_pipeline.fsl` (job pipeline with retries),
`specs/audit_log.fsl` (append-only audit log).

## Results Summary

| Spec | BMC (depth 8) | induction | CTI rounds |
|---|---|---|---|
| mutex_queue | verified, coverage all true | **proved (k=1)** | 0 (the first draft was already inductive) |
| job_pipeline | verified, coverage all true | **proved (k=1)** | 1 (added NoDupQueue) |
| audit_log | verified | **proved (k=1)** | 0 (even with the strict invariant) |

Including the round 1 specs, **all 10 correct specs in the repository are proved at k=1**.

## Evaluation of the proved Workflow

- **The job_pipeline CTI made its cause obvious on first read**: a ghost state `queue = [0, 0, 0]` (the same job
  entered three times). Since pop removes only the single front element, the state transition over the remaining
  duplicates breaks `QueuedAreQueued`. A single auxiliary invariant `NoDupQueue` (no duplicates in the queue)
  flipped it to proved. Together with round 1's auth_lockout / payment, **the CTI → auxiliary invariant loop
  converged in one round 3/3**. The display quality of the CTI (logical values, enum names, changes) directly
  drives this convergence speed.
- Every auxiliary invariant was "itself a domain truth" (no duplicates in the queue, refunds only from Captured,
  locked when attempts=3) and never became an artifact existing only for the proof. A nice side effect is that
  spec quality goes up.

## New Discoveries

### F5: a Seq aggregation idiom using an index domain type (a pleasant surprise)

At design time we assumed "you can't write aggregation (sum) over a Seq", but in practice:

```fsl
type Idx = 0..3   // a domain type covering up to capacity-1
invariant BalanceMatchesLog {
  balance == sum(i: Idx of log.at(i) where i < log.size())
}
```

The combination of `at()` being total in property contexts (out-of-range is don't-care) plus the `where` guard
lets you **fold over the live prefix**. audit_log's strict invariant (balance = log sum) can be written this way,
and it even came out proved at k=1. This should be documented as a standard idiom in the LANGUAGE doc.

### F6: scenarios' shortest trace correctly solves the chain of preconditions

`cover_finish_fail` generates `submit → start → finish_retry → start → finish_fail`.
finish_fail requires `tries >= 1`, and to get there it correctly assembles the 5-step shortest sequence that
passes through retry first. Practical quality as an integration test skeleton.

### F7: "a handoff happened" cannot be stated by state alone (re-confirming F1)

mutex_queue's `HandoffHappened` was written as `holder == some(1)`, but acquire_free(1) also satisfies it at step 1,
so it cannot pin down "the result of a handoff". Same root as round 1's F1 (properties about the past need a ghost
variable). Added as a motivating example for v2.0's `leadsTo`.

## Bugs

For these three specs + probes, **0 new bugs**.
(In review during the Seq implementation round, BUG15 (false detection of partial_op inside an if guard) and
two check pass-throughs (a capacity-overflow literal, `Map<K, Set<K>>`) were detected and fixed beforehand.
Details in DESIGN-seq.md and commit d8e2ecf.)

## Performance

For all three specs, BMC + induction at depth 8 finished within a few seconds. The post-PERF1-fix encoding is
stable even with Seq's shift ites added.
# Dogfooding Round 3 — Full Workflow Demonstration (2026-06-11)

We ran "the development flow FSL envisions" — penetrating every layer of v2.0/v2.1 — end to end on a new domain
(a bank account with a two-tier ledger + audit log).

## Workflow and Results

| Stage | Artifact | Result |
|---|---|---|
| 1. Abstract spec | `specs/bank.fsl` (an account with immediate balance) | **proved (k=1)** on the first try |
| 2. Refinement | `specs/bank_impl.fsl` (a two-tier cleared + pending ledger) | **proved (k=1)** on the first try |
| 3. Faithfulness check | `specs/bank_refines.fsl` (`balance = cleared + pending`) | **refines** on the first try. settle is a stutter, and the strengthened withdraw guard (cleared only) is correctly permitted |
| 4. Composition | `specs/bank_system.fsl` (bank_impl + audit_log, synchronized actions + internal) | verified + **proved (k=1)**. The cross-cutting invariant `audit.balance == cleared + pending + withdrawn` is inductive while coexisting with the components' Seq aggregation invariant |
| 5. Implementation hookup | `examples/bank/` (a plain Python implementation + testgen-generated harness + Adapter wiring) | **8/8 passed** (7 scenario replays + a 100-step random walk with Monitor as the oracle) |

`examples/bank/bank.py` is ordinary app code that knows nothing about FSL. With only the Adapter wiring (about 20 lines),
conformance tests generated from the spec check the implementation's correctness — this is the finished form of the
"bridge between spec and implementation" envisioned since DESIGN-v1.

## Discoveries (2 — both fixed)

### BUG16: testgen mixes display-name dots into the generated function names (SyntaxError)

The composed spec's scenario names (`reach_bank.Settled`) became function names verbatim, making the generated
file un-importable. Fixed with identifier sanitization + collision-numbering + preserving the original name in a
docstring. A "display-layer boundary" bug of the same family as round 2's F6 — a missed propagation of compose's
display-name handling (`__` → `.`).

### BUG17: testgen embeds a cwd-relative path / Monitor mis-classifies path vs. source

The artifact embeds `SPEC_PATH = 'specs/...'`, so it cannot run from anywhere but the repository root. Furthermore,
Monitor parses a nonexistent path string as FSL source, so a failure that should be an io error becomes
UnexpectedCharacters (a repair-protocol violation). Fixed with relative-path resolution anchored at the generated
file + path classification in Monitor.

## Findings

- **F8: every stage of the workflow passed "on the first try".** Unlike rounds 1 and 2, no spec-induced CTIs or
  counterexamples appeared. "Stepwise refinement" — proceeding through abstract → detailed → composed while keeping
  proved at each stage — holds up as the actual feel of using this toolchain.
- **F9: a conditional expression cannot be written in a refinement mapping expression.** (resolved in v2.2) The
  seat-reservation domain we initially considered needed something equivalent to
  `map seats[s] = (st == Sold ? some(holder) : none)`, and since FSL had no conditional expression, it could not be
  expressed as a mapping, so we changed the domain.
  → Implemented as an **`if-then-else` expression restricted to mapping expressions** (DESIGN-refinement §2.5).
  The abandoned seat-reservation domain itself became a second concrete example, and we confirmed that
  `map seats[s] = if slots[s].st == Sold then slots[s].holder else none` passes refines in
  `specs/seat_booking{,_impl}.fsl` + `seat_refines.fsl` (the abstract side's count aggregation evaluates correctly
  over the conditional mapping value). It is not opened up to the ordinary spec expression grammar.
- **F10: the Adapter wiring convention is clear enough.** observe()'s projection (display-name keys, Seq as list,
  Option as None|value) follows the LANGUAGE.md convention with no hesitation. It is practically powerful that the
  random walk automatically reconciles settle's "nothing to settle" guard with the spec's `requires pending > 0`.

## Statistics

- 5 new specs (bank / bank_impl / bank_refines / bank_system / examples), bringing the repository's proved specs to
  13 total (everything except the 2 buggy samples)
- The 2 new bugs (BUG16/17) are both in the generation/bridge subsystems. Zero defects in the verification core
  (BMC / induction / refine / compose semantics) this round.
# Dogfooding Round 4 — Penetrating the 3-Dialect Stack (2026-06-11)

After implementing the kernel + 3 dialects (DESIGN-layers.md / DESIGN-dialects.md), we built up a returns domain
across four files — **business → requirements → design fsl → mapping** — and verified every stage
(`examples/layers/`).

## Results

| Stage | Result |
|---|---|
| business (3 process transitions + KPI + 2 policies + goal) | proved (KPI recorded as projection metadata; no generated `_kpi_*` invariant) |
| requirements (branches, acceptance, implements) | verified + implements: **refines** (upper-layer check included in a single verify command) + proved |
| design layer (two-stage payment + notification queue) | proved + **refines** to the requirements layer |
| variant that breaks a requirement | the counterexample carries `requirement: {REQ-3, original text}` and `implements: violated` **simultaneously** |
| acceptance AC-1 | verified by a Monitor replay at check time, and flows into scenarios |

## Discoveries

- **BUG18 (fixed)**: an identifier with a keyword prefix (`notify` → `not` + `ify`) was tokenized incorrectly.
  Found during the layer spike, fixed in stage 2.
- **F11: the downstream reference to a branches-split action is the internal name.** The design-layer mapping has to
  reference the requirements-layer split action as `submit__b1` (it cannot be written with the display name
  `submit[a <= AUTO_LIMIT]`). It works but is ugly as UX — reference by display name / original name + when-condition
  is filed as future work.
- **F12: cross-layer diagnostics line up in a single JSON.** The requirement (with original text) and implements
  (propagation to the upper layer) ride on the same counterexample — an agent can read "which requirement broke,
  and what business-level thing it violates" in one round trip. The design's aim (transparent composition) holds up
  on the diagnostics side.
- The dialect expander is stable even as compose's third example (BMC/induction/scenarios/Monitor/refine all worked
  on the dialect specs unmodified). The great principle of the unchanged kernel was upheld across all four stages.
# Dogfooding Round 5 — Non-Functional Requirements (Discrete-Time SLA) (2026-06-12)

Verification record for the implementation answering "can FSL handle non-functional requirements?" (DESIGN-nfr.md).

## Results

| Item | Result |
|---|---|
| Hand-written kernel version (examples/nfr/sla_worker_kernel.fsl) | BMC verified + **induction proved** (6 auxiliary invariants, 4 CTI rounds) |
| Dialect version (examples/nfr/sla_worker.fsl, `time` + `deadline`) | BMC verified (the automatic tick appears in coverage) |
| Variant with urgent removed | **violated** — a starvation trace `submit → tick×5` + `requirement: NFR-1 (original text)` |
| Static checks | unused age / unknown urgent / tick name collision / duplicate time / undeclared deadline → type error |

## Insights

- **An SLA can be checked as a safety property**: "within K ticks" = an upper-bound invariant on the age counter.
  This lets you write a stronger "with a deadline" property than leadsTo (eventually).
- **Urgency discipline is essential**: "while an urgent action is enabled, time does not advance" is woven into
  tick's guard. A spec that forgets this gets a starvation trace back from the verifier — a correct, mechanical
  detection that "the scheduling assumption is not written", and it becomes a finding as-is in an NFR review.
- **Proof cost is higher than for untimed specs**: a ladder of time-budget invariants
  (`age[serving] + busy <= 4`, the waiters' budget, age=0 before service starts) is needed, with 4 CTI rounds
  (the prior track record was 1 round). The default workflow is the BMC check; proof being opt-in is the correct
  positioning.
- The boundary of which NFRs are handled (DESIGN-nfr §1) is unchanged after implementation:
  authorization, audit, capacity, reliability behavior (from today) / SLA, timeout (this feature) /
  probability, percentiles, real-time ms (out of scope — to the docs).
# DOGFOOD-6: Example Gallery Bug Hunt

Each file in `examples/gallery/` declares its expected result, and `tests/test_gallery.py`
compares it against the actual `fslc` JSON. Ordinary spec-authoring mistakes have been fixed.
The following are cases where the expectation and the actual output disagreed, left as candidates
on the `fslc` side rather than the spec side.

## BUG-001: refinement misses a requires violation of an abstract action

- reproduction file: `examples/gallery/errors/refinement_failed_map.fsl`
- command:
  `./.venv/bin/python -m fslc refine examples/gallery/errors/refinement_failed_impl.fsl examples/gallery/errors/refinement_failed_abs.fsl examples/gallery/errors/refinement_failed_map.fsl --depth 3`
- expected: `{"result":"refinement_failed","kind":"abs_requires_failed"}`
- actual:

```json
{
  "result": "refines",
  "impl": "GalleryRefinementImpl",
  "abs": "GalleryRefinementAbs",
  "checked_to_depth": 3,
  "action_map": {
    "approve_i": "approve",
    "quick_pay_i": "pay"
  }
}
```

- estimated cause: `quick_pay_i(k)` is enabled in the initial implementation state
  while mapped abstract action `pay(k)` has `requires approved == true`, false under
  `map approved = approved_i`. `src/fslc/refine.py` does build a
  `Not(requires_ok)` violation condition, so the likely issue is in how the explored
  implementation step / action instance / singleton parameter binding is constrained
  when checking the mapped transition.
- test status: `tests/test_gallery.py` verifies the expected `refinement_failed`/`abs_requires_failed` (xfail removed).
- **fixed**: refine was reusing `_bmc_explore`'s "exactly depth" full-unrolling solver, so when the impl deadlocked before reaching depth, the unrolling became unsat → every violation check came out unsat = missed. Changed refine to build each reachable prefix incrementally and stop at the depth where it becomes unsat (src/fslc/refine.py).

## BUG-002: refinement map out-of-bounds is missed when impl/abs type names collide

- reproduction file: `examples/gallery/adversarial/refine_mapping_boundary_map.fsl`
- command:
  `./.venv/bin/python -m fslc refine examples/gallery/adversarial/refine_mapping_boundary_impl.fsl examples/gallery/adversarial/refine_mapping_boundary_abs.fsl examples/gallery/adversarial/refine_mapping_boundary_map.fsl --depth 2`
- expected: `{"result":"refinement_failed","kind":"map_out_of_bounds"}`
- actual:

```json
{
  "result": "refines",
  "impl": "GalleryAdversarialRefineImpl",
  "abs": "GalleryAdversarialRefineAbs",
  "checked_to_depth": 2,
  "action_map": {
    "jump": "bump"
  }
}
```

- estimated cause: the abstract spec defines `type N = 0..1`, while the implementation
  defines `type N = 0..2`, and the mapping is `map n = n_i`. After `jump(0)`, the
  mapped abstract value is `2`, outside the abstract bound. The likely issue is that
  refinement bound checking or static map typing is resolving the shared type name
  through the implementation type environment instead of the abstract one, or otherwise
  treating the mapped alpha value as already abstract-bounded.
- test status: `tests/test_gallery.py` verifies the expected `refinement_failed`/`abs_state_mismatch` (xfail removed).
- **fixed**: the root cause is the same "full-unrolling deadlock → vacuous refines" as BUG-001. Resolved by incremental prefix unrolling. We confirmed the expected kind is `abs_state_mismatch`, not `map_out_of_bounds` (the mismatch between bump's update result n=1 after jump and α(n)=2 is detected before the bound check), and aligned the gallery's expectation to the actual result (both being refinement_failed is unchanged).
# DOGFOOD-7: Correctness Oracle Test Suite

## Summary

Added a bounded correctness suite for `fslc` without modifying `src/fslc`.

New collected tests by category:

| Category | Files | Collected |
|---|---:|---:|
| Monitor BFS oracle agreement | `tests/oracle.py`, `tests/test_oracle_agreement.py` | 37 |
| Trace and witness soundness | `tests/test_trace_soundness.py` | 105 |
| Independent refinement oracle | `tests/test_refine_oracle.py` | 11 |
| Metamorphic checks | `tests/test_metamorphic.py` | 5 |
| JSON/CLI robustness | `tests/test_robustness.py` | 3 |
| Total |  | 161 |

Observed new-test execution: `91 passed, 70 skipped in 88.02s`; wall time `88.24s`.
Full suite execution: `299 passed, 70 skipped in 255.13s`; wall time `255.34s`.
The prior suite baseline was 208 passed at about 170s, so the measured increase is about 85s.

## Oracle Scope And Limitations

`tests/oracle.py` is a pure Python bounded oracle that enumerates reachable states by driving
`fslc.runtime.Monitor.enabled()` and `Monitor.step()`. It does not import Z3 or use BMC.

Limitation: BMC encoding bugs are detectable only when they disagree with Monitor's concrete
single-step semantics. Bugs shared by BMC and Monitor step semantics are not detectable by this
oracle. LeadsTo lasso reasoning is also outside finite Monitor replay, so leadsTo traces are
explicitly skipped in trace soundness.

One deterministic corpus spec, `specs/job_pipeline.fsl`, is skipped by the BFS oracle because
`Monitor.enabled()` raises on a guarded `let queue.head()` before enumeration can proceed.

## Hypothesis

`./.venv/bin/python -c "import hypothesis"` failed with `ModuleNotFoundError`.
`tests/test_robustness.py` therefore uses a fixed-seed deterministic generator.

## Mutation Proof

### Historical `refine.py` Mutation

Mutation:

```bash
git show de9d919^:src/fslc/refine.py > src/fslc/refine.py
```

Result:

| Harness | Result |
|---|---|
| `tests/test_refine_oracle.py -q` | Failed: 5 failures. Historical refine reported `refines` for known `refinement_failed` cases, including the depth-short-of-deadlock fixtures. |
| `tests/test_oracle_agreement.py -q` | Failed: 2 failures. Gallery refinement false-negative fixtures reported `refines` instead of `refinement_failed`. |
| Other new harnesses | Not targeted for this mutation. |

Restoration: original `src/fslc/refine.py` was restored from `/private/tmp/fslc_refine_original.py`.

### Monitor Invariant-Check Mutation

Mutation: temporarily changed the Monitor invariant check in `src/fslc/runtime.py` from:

```python
if not _as_bool(cond):
```

to:

```python
if False and not _as_bool(cond):
```

Result:

| Harness | Result |
|---|---|
| `tests/test_oracle_agreement.py tests/test_trace_soundness.py -q` | Failed: 8 total failures. |
| `tests/test_oracle_agreement.py` | Failed: 4 failures where the mutated Monitor oracle missed invariant/type-bound violations reported by BMC. |
| `tests/test_trace_soundness.py` | Failed: 4 failures where BMC traces replayed through mutated Monitor as `ok`. |
| Other new harnesses | Not targeted for this mutation. |

Restoration: original `src/fslc/runtime.py` was restored from `/private/tmp/fslc_runtime_original.py`.

## Final Verification

Commands run after restoring all mutations:

```bash
/usr/bin/time -p ./.venv/bin/python -m pytest tests/oracle.py tests/test_oracle_agreement.py tests/test_trace_soundness.py tests/test_refine_oracle.py tests/test_metamorphic.py tests/test_robustness.py -q
/usr/bin/time -p ./.venv/bin/python -m pytest tests/ -q
git diff -- src/fslc
```

Final `git diff -- src/fslc` was empty.

## Bug Found By This Suite

- **BUG-020 (Monitor robustness)**: `Monitor.enabled()` raises `_PartialOp`
  on `specs/job_pipeline.fsl`, which `fslc verify` proves/verifies cleanly.
  Cause: `enabled()` eagerly evaluates `let j = queue.head()` while testing
  whether `start()` is enabled; in states reachable during enumeration the
  guard `requires queue.size() > 0` should gate it, but the let is evaluated
  before/independent of the guard, so `head()` on a (possibly empty) Seq
  raises instead of the action being treated as simply not-enabled.
  Impact: runtime Monitor / replay / testgen for any spec with a guarded
  partial-op (`head`/`pop`/`at`) inside a `let`. The BFS oracle skips this
  spec for now. Independently reproduced; not fixed in this test-only round.
  fixed: short-circuit requires guards in Monitor.enabled() before evaluating let bindings
# DOGFOOD-8: Blind Writability Test (External Validation of G1 — Round 1)

## Goal
To measure this project's one unverified core proposition, **G1 "can anyone other than the author write FSL?"**.
Concretely: "relying on **the skill docs alone (SKILL.md + reference.md)**, can a separate agent with none of the
author's context turn natural-language requirements for **a new domain not in the existing examples** into a proved
spec, without syntax hand-holding?"

## Design (constraints for fairness)
- Subject: a separate agent with none of this session's context (general-purpose, same model family).
- References are the **2 documents only**: `skills/fsl/SKILL.md` and `skills/fsl/reference.md`.
  Reading `specs/`, `examples/`, `docs/`, and `src/` is forbidden (to exclude copying examples verbatim and to
  measure "whether the skill alone is a sufficient teacher").
- Subject matter: meeting-room booking (3 rooms × 4 slots × 3 people, no double booking, cancellation frees a slot,
  at most 2 per person, reaching full / holding 2). A new domain not in the existing specs.
- Hollowing out the invariant to make it green is forbidden. The process is logged.
- The result is independently re-verified by the observer (me) + audited with a semantic gallery (does it capture
  the requirements).

## Result: success
- The subject reached **proved** (induction k=1, no auxiliary invariant needed) with **3 fslc runs (check / verify /
  induction) and 0 fixes in the verification phase**.
- Independent re-verification (reproduced in a separate directory): check ok / verify verified (both coverage true,
  reachable witnessed by RoomFull@4 and SomeoneHoldsTwo@2) / induction proved.
- **Confirmed non-hollowing**: removing the guard of `AtMostTwoPerUser` gives violated@3 → it is proved with a
  substantive safety property.
- All 6 requirements were faithfully expressed. No double booking is prevented **structurally** by
  `Map<Cell, Option<UserId>>` (1 cell ≤ 1 holder = two holders are unrepresentable as a type) + reserve's
  empty-slot guard — stronger than an explicit invariant, and the subject honestly reported "there is no explicit
  line" as a reservation (the judgment not to add a hollow invariant was appropriate).

## Improvement Points Surfaced (the main product of this test)
- **F-A (a documentation gap in the skill)**: there is no standard recipe for 2-dimensional data. The naive
  `Map<RoomId, Map<SlotId, …>>` violates the state whitelist (nested Map not allowed). The subject figured this out
  on its own from reference.md §2 and worked around it by flattening (room, slot) into a single domain type `Cell`,
  but a one-liner in SKILL.md saying **"when you want to nest, flatten to a single key or use a struct value"** would
  reduce the snag. A cheap improvement.
- **F-B (an expressiveness gap in the language)**: there is no division or modulo (`+ - *` only). When you flatten
  Cell, you cannot "recover the room from Cell" (`c / SLOTS`), so we had to hard-code "room 0 is full" as the
  literal range `c <= 3`. A spot where the SKILL.md advice "don't hard-code boundaries" clashes with the feature
  set. Candidates: adding `/` and `%` (boundable, so expandable), or presenting a recipe for specs that require
  flattening.

## Limits (so as not to overstate)
- **n=1**: 1 domain, 1 trial. A positive signal, not a proof.
- The subject is an AI of the same model family, not a human PM. What was measured is "whether the skill alone can
  support the **AI authoring** that the README touts as the main path", which matches the real main use case. Human
  writability needs a separate subject.
- The domain is relatively straightforward (easy to cast as a state machine). A follow-up is needed on subject
  matter that requires more tangled requirements, larger boundaries (hitting PERF), or history/responsiveness
  properties.

## Next Moves (in priority order)
1. Add F-A to the skill (cheap, immediately effective).
2. A few more blind follow-up tests with varied domains/difficulty (increase n). Especially "history"-type matter
   that needs leadsTo/ghost variables, and time-based matter that needs an SLA.
3. F-B (division/modulo) is a language decision. After a second real need surfaces.
4. A blind test with a human PM as the subject (not executable by me; on the operations side).

---

# Round 2 (2026-06-12): Harder Follow-up Tests ×2 (to n=3)

With the skill updated to reflect F-A (2D recipe) and F-B (`/` `%`), we ran 2 new domains requiring harder
properties under the same conditions (the 2 skill docs only, reading existing examples forbidden).

## Results Summary

| Subject | Domain (required features) | Result | Fix rounds |
|---|---|---|---|
| ②a | incident ticketing (history ghost + leadsTo/fair) | **proved** (first draft, one try) | 0 |
| ②b | support first-response SLA (time/urgent/age/deadline) | **proved** | 2 (+4 self-initiated experiments) |

Both specs were independently reproduced by the observer and **audited as non-vacuous**: ②a goes violated when a
reopen action is added (with requirement tag REQ-4), and ②b goes violated when deadline is lowered to `<= 2` and
violated when urgent is removed (the boundary is exactly effective).

## Main Product ②b: Discovery of the "Vacuous SLA Trap" (found by the subject, independently confirmed)

Making an action that can always be enabled (the response itself) `urgent` causes **time to freeze, and even
`deadline <= 0` comes out verified** (vacuous). The subject detected this through a self-initiated vacuity
experiment (sweeping deadline over 0/2) and re-invented the **deadline-urgency pattern** (make only a guarded action
of the `respond_due` type, which becomes enabled only when the deadline is reached, urgent). On the observer's
check, this trap is explicitly stated nowhere in the existing docs or examples/nfr — it was the **biggest semantic
gap in the skill alone**. → We documented the trap and the pattern in reference.md / LANGUAGE.md and made the
subject's spec an official example as `examples/nfr/support_sla.fsl` (proved).

## Documentation Gaps Reflected (pointed out by both subjects)

- Placement rules for time/deadline (time directly under requirements, deadline inside a requirement), the
  semantics of age (+1 on tick, 0 when the while is false, readable from a guard), urgent = time freeze.
- leadsTo stays bounded even when proved → for an acyclic system, a `--depth` longer than the longest execution
  covers all executions, a guideline. `--depth K` includes step K.
- A constant-expression type upper bound (`0..ROOMS*SLOTS-1`) is valid (the observer confirmed) — unified the
  literal examples in reference into constant expressions to resolve the inconsistency between the 2 docs.
- Recorded as unaddressed: there is no means to express conditional fairness (only instances under a specific
  condition are fair) (②a; the current workaround is to split into a separate guarded action). Documenting the
  relationship between deadlock and leadsTo stagnation checking also has room for improvement.

## Observer-Side Learnings

In the ②a non-vacuity audit, the probe "removing fair should produce a starvation violated" missed (it stayed
verified) — in a monotone, acyclic system there is no lasso, so every maximal execution ends with everything
resolved, and thus **leadsTo holds structurally even without fairness**. A lesson that designing the audit probe
itself also requires understanding the domain structure.

## Overall Assessment After Update (n=3)

In all 3 domains (booking, history/response, SLA), a blind subject with the 2 skill docs only reached proved.
The snags were consistently **a lack of semantics documentation, not syntax**, and in all 3 the fslc diagnostics
(the expected list, the counterexample trace, the requirement linkage) supported self-recovery. Confidence in G1
strengthened, but it is still AI subjects only — human PM unverified.
# DOGFOOD-9: Running the Validation Workflow (2026-06-12)

We ran from start to finish — on a new domain (order payment / cancellation / refund flow, with inventory) — the
workflow added to skills/fsl in issue #2 (validation roadmap for AI formalization): **formalization memo → NL→syntax
mapping → spec → positive-example pair → repair**. The artifact is `examples/validation/order_refund.fsl`.

The verifier (fslc) is unchanged since v1.0.3. What this round verifies is **the workflow, not code** — whether the
new discipline can catch "a spec that passes internal consistency but drifts from intent", before and after it is
written.

## Original Natural-Language Requirements (assumed PM input)

1. An order can be cancelled after payment, and cancellation refunds the full amount
2. It cannot be cancelled after shipping
3. Refunds only for paid orders. Double refunds are forbidden
4. On payment, reserve 1 from inventory; on cancellation, return it to inventory
5. Refunds only within a certain period from payment

## Formalization Memo (put in chat. not made into a file)

The moment we normalized the requirements into trigger / constraint / exception / **boundary implication**, two mines
became visible:

- **R2's boundary**: the "after" in "cannot cancel after shipping" **includes** Shipped.
  → `cancel requires order[o] == Paid` (excludes Shipped). Stated in ASSUME-2.
- **R5 is undefined**: the value, origin, and boundary (within = inclusive?) of "a certain period" are all absent
  from the original text. After filing it as a question for the human, we noted the suspicion "if this is a
  discrete-time SLA, it's a time+deadline matter in the requirements layer, not the design layer".

We held the assumptions as ASSUME-1 through 4 and decided to fold them into the spec (see below).

## Run Log

| Version | Operation | Result |
|---|---|---|
| v1 | naively modeled R5 with a `window_open: Map<OrderId,Bool>` flag | `check` ok |
| v1 | `verify --depth 8` | **reachable_failed**. `FullyRefunded` unreachable, `action_coverage.refund = false` |
| v1 | refund coverage diagnostic | hint: "these requires are unsatisfiable at any step up to depth 8. **Add an action that makes them hold.**" |
| → repair | removed the window flag; refund is just `requires order[o] == Cancelled`. R5 delegated to an upper layer as ASSUME-5 | |
| v2 | `verify --depth 8` | **verified**. coverage all true (refund too). `FullyRefunded` witnessed at step 3: `pay(0) → cancel(0) → refund(0)` |
| v2 | `verify --engine induction` | **proved (k=1)**, 0 CTI rounds. `_bounds_stock` is also inductive under `StockConserved` |

## Insights

- **F13: the positive-example pair (P4) made a "silently verified" visible (the focus of this round).**
  v1's safety invariants (StockConserved / RefundLedger) **both hold** — even with the refund path entirely dead,
  they cannot be broken if you look at safety alone. By having attached a single `reachable FullyRefunded`, `verify`
  returned reachable_failed instead of verified, and coverage named `refund`. With an invariant-only spec, this
  "the refund feature doesn't work" would have passed both CI and review. Separate from the decision to keep P4 a
  recommendation (don't mandate heavy procedures), we confirmed in practice that **attaching one is highly valuable
  for actions involving a boundary**.

- **F14: the formalization memo's "boundary implication" column flagged R5 as a mine before writing it.**
  R5's ambiguity (the period's value, origin, implication) came up as a human question at the memo stage. But
  naively bringing it into the design layer "with a window flag for now" forgot to write a way to open it, making
  refunds impossible. The 3 points **suspect in the memo, demonstrate with the positive-example pair, settle with
  ASSUME** meshed. The boundary "don't casually expand an ambiguous NFR into design-layer state" (DESIGN-nfr's SLA
  is the requirements layer) was reproduced on the workflow as well.

- **F15: the repair weakened the spec, but the ASSUME tag kept the "why".**
  The repair removed one of refund's guards (weakening). The distinction between hollowing and a legitimate repair
  is borne by ASSUME-5 ("the period check is left to an upper layer" + the history). The discipline of appending the
  repair log to the assumptions ledger (SKILL.md repair protocol) was exactly what worked for this weakening.

- **F16: writing a conservation-law invariant made the automatic bound inductive in one shot.**
  `_bounds_stock` (stock ≤ CAP) is non-inductive on its own (a ghost state with stock=CAP and a Paid order present
  could be a CTI), but the moment we wrote the domain truth `StockConserved` (stock + held count == CAP), it became
  proved at k=1. 0 CTI rounds. Re-confirms "auxiliary invariants are themselves domain truths" (DOGFOOD-2).

## Workflow Assessment

- **Before writing (the memo)**: put R2/R5's boundary implications in a form a human could confirm in plain language,
  before dropping them into logical formulas. The aim of not imposing logical-formula review on the human holds.
- **After writing (the positive-example pair)**: caught **over-constraint / a dead path**, not under-constraint.
  This is a kind of error that verify (safety) alone cannot see in principle, and it became the shortest example
  demonstrating P4's reason for existing.
- **Limit**: this round, a positive-example pair written by the formalizer themselves caught the formalizer's own
  judgment error ("bring R5 into the design layer"). If the positive-example pair had also been written under the
  same misunderstanding (that refunds are essentially unnecessary), it would not have been caught. An independent
  channel (a separate agent writing positive/negative traces from the NL = issue #3 forbidden / D4) is the next
  defensive layer.

## Connection to Remaining Work

- v1's "safety passes but the path dies" is the kind of thing issue #4 (vacuity checking) should emit as a warning
  at the verify stage (`always_true_requires` / unreachable). This round the positive-example pair substituted, but
  a detector is needed for specs where one forgets to write the pair.
- The existence of ASSUME tags is the remit of issue #5 (`--strict-tags`); their semantic binding force is the remit
  of issue #6 (`fslc mutate`).

## Addendum (2026-06-13): Mechanical Verification of ASSUME-5 — Running a Design Review

Using the fsl-design-review skill's procedure, we inspected this round's deferral decision itself. ASSUME-5's premise
was "the period restriction can be added later without breaking the frozen design contract":

| Check | Result |
|---|---|
| Windowed variant (`order_refund_windowed.fsl`: age map + tick + a time guard on refund) | **proved** standalone. FullyRefunded@3 (refund within the window is possible) + WindowExpired@4 (expiry actually occurs too) |
| Windowed variant ⊑ contract (`fslc refine`, tick → stutter) | **refines** — the period restriction goes in without editing a single line of the abstract contract. **ASSUME-5 is sound** |
| Negative probe "instant refund" (skip cancel, Paid → Refunded) | standalone **verified** (conservation law and ledger both intact), but refine is **abs_requires_failed**: the shortest 2-step `pay(0) → instant_refund(0)` bypasses "refund only from Cancelled" |

- **F17: a variant that "passes standalone verify but breaks the contract" is turned into a shortest counterexample
  by refinement.** As a counterpart to the main F13 (the positive-example pair broke the silence of reachability),
  refine breaks the silence of **design deviation**. The picture is complete in which, as validation tooling,
  the three layers verify / reachable / refine each handle a different kind of "silently verified".
- The naive formulation `type Age = 0..WINDOW` + `requires age[o] <= WINDOW` becomes a **tautological dead guard**
  because of the type bound (this variant adopts `< WINDOW`). We note this is the kind of error issue #4's
  `always_true_requires` mechanically detects.
- The artifacts are `examples/validation/order_refund_{windowed,instant}*.fsl`.
