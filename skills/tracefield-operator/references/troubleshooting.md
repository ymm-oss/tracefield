# Troubleshooting

Use this reference when a Tracefield command fails.

## `tracefield` Not Found

Check the binary:

```sh
which tracefield
cargo install --path crates/tracefield-cli --locked
```

Or run from the workspace:

```sh
./target/release/tracefield doctor
```

## Build Fails

Run the standard checks:

```sh
cargo fmt --check
cargo check -p tracefield
cargo test
```

If dependency resolution fails, retry with network access available.

## Ollama Not Reachable

`tracefield doctor` reports Ollama reachability. For a local run:

```toml
# scenarios/<name>/flow.toml
[organs.reasoning]
adapter = "ollama"
model = "<model>"
```

```sh
ollama serve
ollama pull <model>
tracefield run --scenario-dir scenarios/<name>
```

## OpenRouter Fails

Check the API key:

```sh
echo "$OPENROUTER_API_KEY"
tracefield doctor
```

Use a full model slug such as `openai/gpt-5.5` in `[organs.reasoning] model`
when `adapter = "openrouter"`.

## CLI Adapter Fails

The CLI adapter uses `cursor-agent` by default and reports `cursor-agent`,
`claude`, and `codex` availability in `doctor`.

Set the command explicitly if needed:

```sh
TRACEFIELD_CLI_COMMAND=claude tracefield run --scenario-dir scenarios/<name>
TRACEFIELD_CLI_COMMAND=codex tracefield run --scenario-dir scenarios/<name>
```

`TRACEFIELD_CLI_COMMAND=claude-code` is accepted as an alias for the `claude`
binary. Codex runs through `codex exec` and reads the final answer from
`--output-last-message`.

## Empty Or Weak Flow Output

Run mock first and inspect scenario quality:

```sh
tracefield run --scenario-dir scenarios/<name>
```

Then improve:

- `task.md`: make the decision or investigation concrete.
- `agents.json`: make `domain` and `desc` distinct.
- `private/*.md`: add factual constraints, observations, and known tradeoffs.

## Retraction Fails

Confirm the store and id:

```sh
head -5 runs/<name>.jsonl
tracefield retract --store runs/<name>.jsonl --entry e3
```

If the id is absent, rerun `tracefield run` with `--persist` and use an id from
that store.
