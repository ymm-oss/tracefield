# Command Map

Use this reference when mapping a user request to the Rust `tracefield` command
surface.

## Core Commands

| User intent | Command |
| --- | --- |
| Check local setup | `tracefield doctor` |
| Create a consult-style scenario | `tracefield new <name> --profile consult` |
| Create a deep investigation scenario | `tracefield new <name> --profile deep_investigation` |
| Fetch web pages into scenario inputs | `tracefield web-input --scenario-dir scenarios/<name> --url <url>` |
| Run the configured flow | `tracefield run --scenario-dir scenarios/<name>` |
| Run Ollama-backed flow | Set `[organs.reasoning] adapter = "ollama"` and `model = "<model>"` in `flow.toml`, then run. |
| Run CLI-backed flow | Set `[organs.reasoning] adapter = "cli"` and `model = "<model>"` in `flow.toml`, then run. |
| Run Claude Code flow | `TRACEFIELD_CLI_COMMAND=claude tracefield run --scenario-dir scenarios/<name>` after setting `adapter = "cli"`. |
| Run Codex CLI flow | `TRACEFIELD_CLI_COMMAND=codex tracefield run --scenario-dir scenarios/<name>` after setting `adapter = "cli"`. |
| Run OpenRouter flow | Set `[organs.reasoning] adapter = "openrouter"` and `model = "<provider/model>"` in `flow.toml`, then run. |
| Set rounds/cycles | Set `[long_run] cycles = <N>` in `flow.toml`. |
| Emit compact JSON | add `--json` |
| Write pretty JSON report | add `--out <file>` |
| Persist reference store | add `--persist <file>.jsonl` to `run` |
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

- use the available `run`/`retract` workflow, or
- implement a new Rust command before trying to run it.
