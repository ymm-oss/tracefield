# Rust Implementation Status

Tracefield is now implemented as a Rust workspace. The previous Elixir/Mix
implementation has been removed from the active codebase.

## Build and Validate

```sh
cargo build --release -p tracefield
cargo check -p tracefield
cargo test
```

`./install.sh` runs the release build, check, and a mock consult smoke check.

## Command Surface

| Command | Status |
| --- | --- |
| `tracefield doctor` | Checks local adapter readiness: mock, Ollama reachability, OpenRouter key, CLI tools. |
| `tracefield new <name>` | Scaffolds `task.md`, `agents.json`, and `private/*.md`. |
| `tracefield consult --scenario-dir <dir>` | Runs a governed consult using `mock`, `ollama`, `cli`, or `openrouter`. |
| `tracefield retract --store <jsonl> --entry <id>` | Marks an entry and downstream citation closure as retracted. |

## Crate Layout

| Crate | Role |
| --- | --- |
| `tracefield` | CLI binary package. |
| `tracefield-core` | Scenario loading, reference store, LLM adapters, and consult logic. |

## Scenario Format

Scenario directories keep the shared shape:

```text
scenarios/<name>/
├── task.md
├── agents.json
└── private/
    ├── lens1.md
    └── lens2.md
```

`agents.json` may be either wrapped (`{"agents": [...]}`) or a raw agent array.

## Current Gaps

- Historical experiment runners such as phase comparisons, heterogeneity
  experiments, genesis, field, bridge, evidence, and ideation are not yet
  reimplemented as Rust commands.
- Python analysis scripts under `experiments/` remain historical artifacts.
- Older implementation briefs under `docs/mvp-impl-brief*.md` may reference the
  removed Mix task surface.

## Compatibility Notes

- Persisted stores are JSONL.
- Entry ids are generated as `e1`, `e2`, ...
- Retraction follows citation edges from the target entry to downstream entries.
