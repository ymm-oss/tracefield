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
`--output-last-message`. Inline `command = "claude"` in `[organs.reasoning]` is
equivalent to the env prefix.

### Stale installed binary

If the `claude` adapter errors with `unknown option '--force'`, or a subcommand
like `run`/`aggregate` is missing, the `~/.cargo/bin/tracefield` copy predates
the current source (it carries `cursor-agent`-only flags or the old `consult`
surface). Rebuild and prefer the workspace binary:

```sh
cargo build --release
./target/release/tracefield doctor
# or reinstall: cargo install --path crates/tracefield-cli --locked
```

## Empty Or Weak Flow Output

Run mock first and inspect scenario quality:

```sh
tracefield run --scenario-dir scenarios/<name>
```

Then improve:

- `task.md`: make the decision or investigation concrete.
- `agents.json`: make `domain` and `desc` distinct.
- `private/*.md`: add factual constraints, observations, and known tradeoffs.

## Retraction / Supersession Fails

Confirm the store and id(s):

```sh
head -5 runs/<name>.jsonl
tracefield retract --store runs/<name>.jsonl --entry e3
tracefield supersede --store runs/<name>.jsonl --entry e3 --with e9
```

If an id is absent, rerun `tracefield run` with `--persist` and use an id from
that store. For `supersede` the replacement `--with <id>` must also exist in the
store (and differ from `--entry`).

## Aggregate Shows Fewer Overturns Than Fired

`tracefield aggregate --stage <s>` counts only **Active** verdicts. With
`retract_overturned = true`, an `overturn` verdict sits in the *downstream closure
of the claim it overturns* (verdict → cites refutation → `meta.refutes` target), so
`reconcile_overturned` retracts the verdict **together with** the target. The final
store can therefore show `overturn=0` even though overturns fired. To count what
actually fired, read the reconcile log, not `aggregate`:

```sh
tracefield run --scenario-dir scenarios/<name> --persist runs/<name>.jsonl > runs/<name>.log 2>&1
grep -c "overturned-claim" runs/<name>.log     # how many fired
grep    "overturned-claim" runs/<name>.log     # which claim ids
```

Also: overturn *count* does not by itself separate a real problem from manufactured
drama (a position tournament always overturns something). Judge by *what axis* was
overturned, not how many.

## Agent Returns Prose Instead Of A Code/File Artifact

`codex-app-server` is read-only and records the agent's reasoning; for a "produce
this code" task it often returns a **prose summary, not a runnable code block** (fine
for analysis/judgement, unusable when you must extract and run the output). For
artifacts you execute (e.g. generated test suites), use an `ollama` organ — raw text
returns reliable fenced code:

```toml
[organs.deep]
adapter = "ollama"
model = "qwen3.6:27b"
timeout_seconds = 600
```

Run ollama flows **sequentially** (one `tracefield run` at a time; `max_parallel_actors = 1`
for heavy models) — concurrent requests to a single ollama server time out on large
models. Raw `codex exec` as a one-shot judge can hang; prefer the in-harness
`codex-app-server` path for *reasoning/prose*, and `ollama` for *code artifacts*.
