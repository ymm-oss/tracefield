# Command Map

Use this reference when mapping a user request to the Rust `tracefield` command
surface.

## Core Commands

| User intent | Command |
| --- | --- |
| Check local setup | `tracefield doctor` |
| Create a scenario | `tracefield new <name>` |
| Run model-free consult | `tracefield consult --scenario-dir scenarios/<name> --adapter mock` |
| Run Ollama consult | `tracefield consult --scenario-dir scenarios/<name> --adapter ollama --model <model>` |
| Run CLI-backed consult | `tracefield consult --scenario-dir scenarios/<name> --adapter cli --model <model>` |
| Run Claude Code consult | `TRACEFIELD_CLI_COMMAND=claude tracefield consult --scenario-dir scenarios/<name> --adapter cli --model <model>` |
| Run Codex CLI consult | `TRACEFIELD_CLI_COMMAND=codex tracefield consult --scenario-dir scenarios/<name> --adapter cli --model <model>` |
| Run OpenRouter consult | `tracefield consult --scenario-dir scenarios/<name> --adapter openrouter --model <provider/model>` |
| Emit compact JSON | add `--json` |
| Write pretty JSON report | add `--out <file>` |
| Persist reference store | add `--persist <file>.jsonl` |
| Retract an entry | `tracefield retract --store <file>.jsonl --entry <id>` |

## Build Commands

```sh
cargo build --release -p tracefield
cargo check -p tracefield
cargo test
```

Install to Cargo's bin directory:

```sh
cargo install --path crates/tracefield-cli --locked
```

## Removed Surface

Do not call historical Mix tasks. The active implementation has no `mix.exs`,
`lib/`, or `test/*.exs`.

If a user asks for an old experiment runner such as `phase1`, `hetero`,
`ideate`, `genesis`, `bridge`, or `field`, explain that it is not yet exposed in
the Rust CLI and either:

- use the available `consult`/`retract` workflow, or
- implement a new Rust command before trying to run it.
