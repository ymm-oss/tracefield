# Rust Implementation Status

Tracefield is now implemented as a Rust workspace. The previous Elixir/Mix
implementation has been removed from the active codebase.

## Build and Validate

```sh
cargo build --release -p tracefield
cargo check -p tracefield
cargo test
```

`./install.sh` runs the release build, check, and a mock flow smoke check.

## Command Surface

| Command | Status |
| --- | --- |
| `tracefield doctor` | Checks local adapter readiness: mock, Ollama reachability, OpenRouter key, CLI tools. |
| `tracefield new <name> --profile consult` | Scaffolds a consult-style scenario with `task.md`, `agents.json`, `flow.toml`, `inputs/`, and `private/*.md`. The profile defaults to `adapter = "mock"` and `[long_run] cycles = 2`. |
| `tracefield new <name> --profile deep_investigation` | Scaffolds the long-horizon investigation flow. |
| `tracefield run --scenario-dir <dir>` | Runs a configured Field Runner flow from `flow.toml`, including staged actors, organ routing, JSONL persistence, and Markdown artifact export. Adapter and model are configured under `[organs.reasoning]`. |
| `tracefield retract --store <jsonl> --entry <id>` | Marks an entry and downstream citation closure as retracted. |

## Crate Layout

| Crate | Role |
| --- | --- |
| `tracefield` | CLI binary package. |
| `tracefield-core` | Scenario loading, reference store, LLM adapters, and Field Runner / flow logic. |

## Scenario Format

Scenario directories keep the shared shape:

```text
scenarios/<name>/
├── task.md
├── agents.json
├── flow.toml
├── inputs/
│   └── example.md
├── skills/
│   └── review/
│       └── SKILL.md
└── private/
    ├── lens1.md
    └── lens2.md
```

`agents.json` may be either wrapped (`{"agents": [...]}`) or a raw agent array.
Agents may reference scenario-local user skills with `skills: ["review"]`;
referenced skills are loaded from `skills/<id>/SKILL.md` and seeded as
`procedure` entries. `SKILL.md` must include `name` and `description`
frontmatter, and `name` must match `<id>`. The Rust CLI currently injects
`SKILL.md` instructions only; bundled references, scripts, and assets are not
automatically read or executed by the flow.

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
