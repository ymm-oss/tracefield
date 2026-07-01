# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
cargo build --release -p tracefield     # build the CLI binary (-> target/release/tracefield)
cargo check -p tracefield               # fast type-check
cargo fmt --check                       # formatting (CI gate)
cargo clippy -p tracefield-core -p tracefield   # lint both crates
cargo test                              # full workspace test suite (uses the mock adapter — no model/network/key)
cargo test -p tracefield-core --lib store::supersede   # a single test (module::name filter)
```

The `mock` adapter means tests and smoke scenarios run with no model. A model-free end-to-end smoke:

```sh
./target/release/tracefield doctor
./target/release/tracefield new smoke
./target/release/tracefield run --scenario-dir scenarios/smoke
```

`./install.sh` installs the CLI onto your PATH (`cargo install`) + runs the smoke (`--test` also runs tests, `--no-smoke` skips). Note: the `cargo` package name for the CLI crate is **`tracefield`**, not `tracefield-cli`.

> A stale `~/.cargo/bin/tracefield` can lag the source (missing flag/subcommand). Re-run `./install.sh` to refresh it, or use `cargo build --release` and invoke `./target/release/tracefield` directly when iterating.

## Architecture

Two crates. `tracefield-cli` (`crates/tracefield-cli/src/main.rs`) is a thin clap front end **plus** the mechanical aggregation logic (`classify_verdict` / `aggregate_verdicts`). `tracefield-core` is the engine; everything else is data (`scenarios/`, `docs/`, `skills/`).

Core modules (`crates/tracefield-core/src/`):
- **`flow.rs`** (the bulk) — the deterministic orchestrator. Executes stages in `flow.toml` declaration order, resolves stage inputs via `entries_for_selector` (`path:` / `stage:` / `entry_type:` / `kind:` / `all`), scales actors (`fixed` / `per_input` / `per_agent`), and runs `[long_run]` cycles. The task is **seeded exactly once** before the work loop; cycles only re-queue stages, never re-seed.
- **`store.rs`** — `ReferenceStore`, an append-only list of entries persisted as JSONL. Holds the citation reverse-BFS `downstream_closure` and the `mark_closure` primitive that `retract` (status `Retracted`) and `supersede` (status `Superseded`, keeps the replacement Active) both delegate to.
- **`entry.rs`** — `Entry` / `EntryType` / `EntryStatus` (`Active` / `Retracted` / `Superseded`) and `NewEntry`.
- **`llm.rs`** — adapters (`mock` / `ollama` / `openrouter` / `cli`). `build_cli_invocation` shapes the argv for `claude` / `codex` / `cursor-agent` / `ds4`; the prompt is passed as **text** and the agent runs read-only.
- **`codex_app_server.rs`** — the recommended codex path (read-only sandbox, approvals denied). It records the agent's tool/command/file activity as provenance entries.
- **`scenario.rs`** — loads a scenario dir (`task.md`, `agents.json`, `flow.toml`, `inputs/`, `skills/`, `private/`); `AgentSpec`.
- **`skill_tools.rs`** — scenario-local agent skills: injects `skills/<id>/SKILL.md` instructions (path-escape sandboxed); auto-cited so skill influence stays retractable.
- **`web_input.rs`** — the `web-input` subcommand (fetch pages into `inputs/web/` with provenance).

### Load-bearing invariants (the non-obvious design)

These are the design's whole point — preserve them when changing the engine:

1. **No central LLM synthesizer.** Every model call stays in a small, faithful context. Integration is **mechanical**: a flow ends with `tracefield aggregate`, which folds adjudication verdicts in rule-based code (no LLM). `classify_verdict` anchors on the canonical Japanese `判定:` label; an unclassifiable verdict becomes `indeterminate` and is surfaced — **never silently dropped**.
2. **Status drives the entire read path.** `entries_for_selector` (input selection), `aggregate_verdicts`, and `store.serve` all filter `status == Active`. So `retract` / `supersede` remove an entry (and its citation closure) from the live flow with **zero** extra wiring downstream. This is why adding a new terminal status only needs a writer, not read-side changes.
3. **Re-aggregation is manual, by design.** After a retract/supersede the basis is *not* auto-recomputed — you re-run `aggregate`. Silent recompute would erase the fact that a conclusion changed; the closure must be shown to a human (the inverse of no-silent-drop).
4. **The canonical governed-investigation flow** is `analysis (orthogonal lenses) → verify (FALSIFY/COUNTER) → adjudication (per_input: 1 refutation = 1 isolated judge) → aggregate`. `per_input`'s value is **isolation, not parallelism** (it stops a monolithic synthesizer from burying a refutation).

## Where design knowledge lives

- **`skills/`** is the authoritative operating/design guide and should be updated when engine behavior changes: `tracefield-operator` (running the CLI) and `tracefield-flow-design` (designing `flow.toml` / `agents.json`). These skills also exist as a **runtime copy under `~/.claude/skills/`** that is *not* version-controlled and must be kept in sync with the repo copies (known drift hazard — sync both when editing either).
- **`docs/findings-*.md`** are the source of truth for *why* the design is shaped this way (mostly Japanese). Record new experiment results there; the flow-design skill cites them.

## Conventions

- All `scenarios/` data is **synthetic and fictional** — never add real client/customer/personal data.
- This is a research project; CLI names, APIs, and scenario formats are unstable.
- Commit messages and PRs: keep changes focused and explain the *why*; for experiment changes, record findings under `docs/findings-*.md`.
