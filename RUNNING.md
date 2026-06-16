# Tracefield Running Notes

## Build And Validate

```sh
cargo build --release -p tracefield
cargo check -p tracefield
cargo test
```

`./install.sh` runs the release build, `cargo check -p tracefield`, and a mock
consult smoke check. Add `--test` to run the Rust test suite.

## Model-Free Smoke

```sh
./target/release/tracefield doctor
./target/release/tracefield consult --scenario-dir scenarios/generic-smoke --adapter mock
```

The mock adapter is deterministic and requires no model, local service, or API
key.

## Live Local Model

Start Ollama and make sure the model exists:

```sh
ollama serve
ollama pull gemma4:12b
./target/release/tracefield consult \
  --scenario-dir scenarios/generic-smoke \
  --adapter ollama \
  --model gemma4:12b
```

## Persist And Retract

```sh
./target/release/tracefield consult \
  --scenario-dir scenarios/generic-smoke \
  --adapter mock \
  --persist /tmp/tracefield-store.jsonl

./target/release/tracefield retract \
  --store /tmp/tracefield-store.jsonl \
  --entry e1
```

The store is JSONL. Retraction marks the target entry and its downstream citation
closure as retracted.
