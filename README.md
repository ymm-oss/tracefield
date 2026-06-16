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

## Requirements

- [Rust](https://www.rust-lang.org/tools/install) with Cargo
- For live local model runs: [Ollama](https://ollama.com/)
- For OpenRouter runs: `OPENROUTER_API_KEY`

The built-in `mock` adapter runs with no model, no network service, and no API
key.

## Quick Start

```sh
git clone https://github.com/ymm-oss/tracefield.git
cd tracefield
./install.sh
```

`install.sh` builds the Rust CLI, runs `cargo check -p tracefield`, and runs a
model-free smoke check unless `--no-smoke` is passed.

Manual commands:

```sh
cargo build --release -p tracefield
cargo check -p tracefield
cargo test
```

Run the CLI:

```sh
./target/release/tracefield doctor
./target/release/tracefield consult --scenario-dir scenarios/generic-smoke --adapter mock
```

Install it into Cargo's bin directory:

```sh
cargo install --path crates/tracefield-cli --locked
tracefield doctor
```

## Commands

```sh
tracefield doctor
tracefield new my-review
tracefield consult --scenario-dir scenarios/my-review --adapter mock
tracefield consult --scenario-dir scenarios/my-review --adapter ollama --model gemma4:12b
tracefield consult --scenario-dir scenarios/my-review --adapter mock --persist runs/reference.jsonl
tracefield retract --store runs/reference.jsonl --entry e3
```

`consult` writes a readable report by default. Use `--json` for compact JSON or
`--out <file>` for a pretty JSON file.

## Author A Scenario

```sh
tracefield new my-review
# edit scenarios/my-review/task.md and private/*.md
tracefield consult --scenario-dir scenarios/my-review --adapter mock
```

A scenario is:

```text
scenarios/<name>/
├── task.md
├── agents.json
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
read or executed by `consult`.

## Repository Layout

```text
crates/tracefield-cli/   CLI binary
crates/tracefield-core/  scenario, store, LLM adapter, consult logic
scenarios/               synthetic, fictional consulting scenarios
docs/                    design notes, experiment plans, findings
experiments/             Python analysis scripts for historical run outputs
```

All scenario data under `scenarios/` is **synthetic and fictional**. Do not add
real client, customer, or personal data to this repository.

## Status

This is a **research project**, not a stable library. APIs, command names, and
scenario formats may change as experiments evolve. Current Rust-port scope is
tracked in [`docs/rust-port.md`](./docs/rust-port.md).

## License

Licensed under the [Apache License, Version 2.0](./LICENSE).

Copyright 2026 Ryoichi Izumita. See [`NOTICE`](./NOTICE) for attribution details.

## Contact

Ryoichi Izumita — ryoichi.a.izumita@accenture.com
