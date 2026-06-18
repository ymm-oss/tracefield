# Tracefield Running Notes

## Build And Validate

```sh
cargo build --release -p tracefield
cargo check -p tracefield
cargo test
```

`./install.sh` runs the release build, `cargo check -p tracefield`, and a mock
flow smoke check. Add `--test` to run the Rust test suite.

## Model-Free Smoke

```sh
./target/release/tracefield doctor
./target/release/tracefield run --scenario-dir scenarios/generic-smoke
```

`scenarios/generic-smoke/flow.toml` uses `adapter = "mock"`, which is
deterministic and requires no model, local service, or API key.

## Choosing An Adapter And Model

The adapter and model are set per organ in `flow.toml`, not via CLI flags:

```toml
[organs.reasoning]
adapter = "ollama"        # mock / ollama / cli / openrouter / codex-app-server
model = "gemma4:12b"
```

- `ollama` — start `ollama serve` and `ollama pull <model>` first.
- `cli` — set `command = "claude"` / `"codex"` / `"cursor-agent"` and a matching `model`.
- `openrouter` — `model = "provider/slug"`, requires `OPENROUTER_API_KEY`.
- `codex-app-server` — codex via JSON-RPC; supports `web_search = true` with search provenance.

Full field reference: `skills/tracefield-operator/references/flow-spec.md`.

## Persist And Retract

```sh
./target/release/tracefield run \
  --scenario-dir scenarios/generic-smoke \
  --persist /tmp/tracefield-store.jsonl

./target/release/tracefield retract \
  --store /tmp/tracefield-store.jsonl \
  --entry e1
```

The store is JSONL. Retraction marks the target entry and its downstream citation
closure as retracted; re-running `run` regenerates aggregates and artifacts.
