# tracefield

> **Governable exploration for multi-agent systems.** A Rust CLI for
> semi-soluble orchestration: letting AI agents collaborate while keeping each
> input's downstream influence traceable, isolable, and retractable.

`tracefield` investigates a single design hypothesis:

> Can open-ended multi-agent exploration retain **provenance**,
> **reversibility**, and **gateability** so that when a contaminated, false, or
> retracted input enters the system, its downstream impact can be located,
> isolated, excised, and re-evaluated?

The detailed design notes, experiment plans, and findings live in [`docs/`](./docs)
and are written mostly in Japanese.

## The Idea

Multi-agent exploration faces a trade-off:

| Mode | Openness | Governability |
| --- | --- | --- |
| Free-form exploration | high | low |
| Fixed-role pipeline | low | high |
| **Semi-soluble orchestration** | retains high openness | retains provenance / reversibility / gateability |

The core value tested here is **not "find more blind spots"**. The primary
outcome is **impact recall / precision**: how accurately the system can identify
and contain the downstream influence of a bad input once it is discovered.

See [`docs/user-guide.md`](./docs/user-guide.md) for usage, [`docs/overview.md`](./docs/overview.md)
for conceptual background, and [`docs/glossary.md`](./docs/glossary.md) for
terminology.

## Installation

### Prerequisites

- [Rust](https://www.rust-lang.org/tools/install) with Cargo (the 2024-edition
  toolchain). This is the only hard requirement — the built-in `mock` adapter
  runs with no model, network, or API key.
- Optional, only for live model runs:
  - [Ollama](https://ollama.com/) for local models (`adapter = "ollama"`).
  - A CLI agent on your `PATH` — `claude` or `codex` — for `adapter = "cli"`.
  - `OPENROUTER_API_KEY` for `adapter = "openrouter"`.

### Install

```sh
git clone https://github.com/ymm-oss/tracefield.git
cd tracefield
```

Then pick one:

**Bootstrap script** — installs the CLI onto your PATH (`cargo install`) and runs a model-free smoke check:

```sh
./install.sh            # --test also runs the test suite; --no-smoke skips the smoke run
```

**Or install the `tracefield` binary onto your PATH directly:**

```sh
cargo install --path crates/tracefield-cli --locked
```

**Or build in place** and call `./target/release/tracefield` — useful while iterating on the source, since it skips the install-to-PATH step:

```sh
cargo build --release
```

> If a previously installed `~/.cargo/bin/tracefield` lags behind the source
> (e.g. an adapter errors with `unknown option '--force'`, or a subcommand is
> missing), re-run `./install.sh` or `cargo install --path crates/tracefield-cli --locked --force`.

### Verify

```sh
tracefield doctor                       # or ./target/release/tracefield doctor
tracefield new smoke                    # scaffolds scenarios/smoke with a mock flow.toml
tracefield run --scenario-dir scenarios/smoke   # mock run; needs no model or key
```

`doctor` reports adapter availability:

```text
Adapters
- mock: ok
- ollama: ok
- openrouter: OPENROUTER_API_KEY not set
- cli: claude, codex found
```

## Commands

```sh
tracefield doctor
tracefield new my-review --profile consult
tracefield new my-investigation --profile deep_investigation
tracefield web-input --scenario-dir scenarios/my-investigation --url https://example.com/source
tracefield run --scenario-dir scenarios/my-review
TRACEFIELD_CLI_COMMAND=claude tracefield run --scenario-dir scenarios/my-review
TRACEFIELD_CLI_COMMAND=codex tracefield run --scenario-dir scenarios/my-review
tracefield run --scenario-dir scenarios/my-review --persist runs/reference.jsonl
tracefield aggregate --store runs/reference.jsonl
tracefield retract --store runs/reference.jsonl --entry e3
tracefield structural-view --store runs/reference.jsonl --out runs/structural-view.json
tracefield structural-checks --store runs/reference.jsonl
```

| Adapter | Use | Config |
| --- | --- | --- |
| `mock` | structure check, no model | `adapter = "mock"` |
| `ollama` | local models | `adapter = "ollama"`, `model = "<model>"` |
| `cli` | local agents (`claude` / `codex`) | `adapter = "cli"`, `command = "claude"` (or `TRACEFIELD_CLI_COMMAND=claude` prefix) |
| `openrouter` | hosted models | `adapter = "openrouter"`, `model = "<provider/model>"`, `OPENROUTER_API_KEY` |

For live adapters, set `adapter` and `model` in `scenarios/<name>/flow.toml`
under `[organs.reasoning]`, for example `adapter = "ollama"` and
`model = "gemma4:12b"`. The `consult` profile defaults to `adapter = "mock"` and
`[long_run] cycles = 2`.

`tracefield run --persist <file>.jsonl` resumes from an existing store when the
file exists and writes Markdown artifacts plus sidecar manifests when configured.
`tracefield structural-view --store <file>.jsonl` materializes that canonical
log as a HigherGraphen-backed structural view: entries become cells, citations
become incidences / derivation morphisms, explicit `meta.refutes` becomes
obstructions, and impact cones are computed through HigherGraphen graph
analytics over the citation incidence view.
`tracefield structural-checks --store <file>.jsonl` runs deterministic checks
over that materialized view, surfacing blocking obstructions, dangling
incidences, unreviewed structural candidates, and HigherGraphen evaluator
acyclicity violations without an LLM. Pass `--check hg_graph_analytics` to
surface HigherGraphen centrality, cut-cell, and dominator candidates.
`tracefield web-input` fetches pages into `inputs/web/` with source URL,
fetched-at, content type, and byte provenance so Field Runner can consume them as
normal inputs.
Agents can feed improvements back into the runner by emitting entries with
`meta.kind = "tracefield_feedback"`; `flow.toml` routes those entries to
recollection, triage, analysis, or artifact layers.
`deep_investigation` adds source discovery, deterministic source clustering,
per-input data extraction, analysis, audit, report, and deck artifact layers.

`tracefield run` writes a readable report by default. Use `--json` for compact
JSON or `--out <file>` for a pretty JSON file.

`tracefield aggregate --store <file>.jsonl` deterministically folds the verdicts
of an `adjudication` stage into a standing conclusion **without an LLM**: any
`overturn` → conclusion changed; any unclassifiable verdict → `indeterminate`
(surfaced, never silently dropped); otherwise `maintained` under the union of
the conditional verdicts. This replaces a monolithic LLM "synthesis" step, whose
fidelity degrades at scale (see [Findings](#findings)).

## A Governed Investigation

The investigation pattern that the design findings converge on keeps every model
call inside a small, faithful context and reserves integration for deterministic
code:

```text
analysis (a panel of orthogonal lenses)
  → structural checks (deterministic obstruction / invariant / candidate scan)
  → verify (adversarial falsify / counter-example)
  → adjudication (one isolated actor per refutation, mode = "per_input")
  → tracefield aggregate (mechanical fold; no central synthesizer)
```

Persisting with `--persist` makes the result **falsifiable over time**:
`tracefield retract` on a load-bearing premise propagates a closure over every
dependent entry, and re-running `aggregate` recomputes the standing conclusion.
The [`tracefield-flow-design`](./skills/tracefield-flow-design/SKILL.md) skill
encodes how to choose lenses and wire these stages.

## Author A Scenario

```sh
tracefield new my-review --profile consult
# edit scenarios/my-review/task.md and private/*.md
tracefield run --scenario-dir scenarios/my-review
```

A scenario is:

```text
scenarios/<name>/
├── task.md
├── agents.json
├── flow.toml
├── inputs/
│   └── example.md
├── skills/
│   └── security-review/
│       └── SKILL.md
└── private/
    ├── lens1.md
    └── lens2.md
```

`agents.json` accepts either a wrapped or raw agent list:

```json
{
  "agents": [
    {"id": "A1", "domain": "risk", "desc": "Focus on risks.", "doc": "lens1.md", "skills": ["security-review"]},
    {"id": "A2", "domain": "value", "desc": "Focus on value.", "doc": "lens2.md"}
  ]
}
```

Agent skills are user-defined, scenario-local procedures. A skill id in
`agents.json` resolves to `skills/<id>/SKILL.md`. `SKILL.md` must use the agent
skill shape: YAML frontmatter with `name` and `description`, followed by
Markdown instructions. Loaded skills are seeded as `procedure` entries and are
automatically cited by entries produced by agents that use them, so skill
influence remains retractable. Tracefield currently injects `SKILL.md`
instructions only; bundled references, scripts, and assets are not automatically
read or executed by the flow.

## Skills

[`skills/`](./skills) holds Claude Code skills that capture operating and design
knowledge so it is reusable across sessions:

- [`tracefield-operator`](./skills/tracefield-operator/SKILL.md) — **running** the
  CLI: `doctor` / `new` / `run` / `persist` / `structural-view` /
  `structural-checks` / `aggregate` / `retract`, adapters, and troubleshooting.
- [`tracefield-flow-design`](./skills/tracefield-flow-design/SKILL.md) —
  **designing** `flow.toml` / `agents.json`: lens selection, stage topology,
  mechanical aggregation, and denoise patterns, distilled from the findings.

## Findings

Highlights confirmed by controlled and blind-rated experiments (full notes in
[`docs/`](./docs)):

- **Lens type** ([`findings-lens-type.md`](./docs/findings-lens-type.md)) —
  panels of mutually *orthogonal* philosophical lenses surface more
  blind-spot considerations than role lenses (blind-judge confirmed). Operations
  (synthesis, critique) belong in *stages*, not lenses.
- **Synthesis bottleneck** (same doc) — a monolithic LLM "synthesis" is faithful
  on small inputs but drops/inverts at scale, worse on weaker models; the fix is
  per-refutation isolation + the mechanical `aggregate`.
- **Diffusion-like iteration** ([`findings-diffusion-thinking.md`](./docs/findings-diffusion-thinking.md))
  — peer iteration across `long_run` cycles refines without mode collapse
  (~3 cycles is the sweet spot).
- **Long-run investigation** ([`findings-longrun-investigation.md`](./docs/findings-longrun-investigation.md))
  — the governed pattern above, run end to end with retract-based falsifiability.
- **Sedimentation** ([`findings-being-sedimentation.md`](./docs/findings-being-sedimentation.md))
  — a self-referential standpoint seeded against the model's default holds and
  self-reinforces across cycles (path-dependent, not a washed-out costume).

## Repository Layout

```text
crates/tracefield-cli/   CLI binary
crates/tracefield-core/  scenario, store, LLM adapter, Field Runner / flow logic
skills/                  Claude Code skills (operate + design)
docs/                    design notes, experiment plans, findings
experiments/             Python analysis scripts for historical run outputs
```

Scenarios you create live under a local `scenarios/` directory, which is
**git-ignored and not part of this repository**. Keep scenario data synthetic
and fictional; never commit real client, customer, or personal data.

## Status

This is a **research project**, not a stable library. APIs, command names, and
scenario formats may change as experiments evolve. Current Rust-port scope is
tracked in [`docs/rust-port.md`](./docs/rust-port.md).

## License

Licensed under the [Apache License, Version 2.0](./LICENSE).

Copyright 2026 Ryoichi Izumita. See [`NOTICE`](./NOTICE) for attribution details.

## Contact

Ryoichi Izumita — please file questions and issues via [GitHub Issues](https://github.com/ymm-oss/tracefield/issues).
