---
name: tracefield-operator
description: Tracefield Rust CLIでシナリオ作成、flow実行、JSONL永続化、機械的集約(aggregate)、retract/supersede検証、doctor診断を行う運用ガイド。「tracefieldで相談を回して」「scenarioを作って」「flowを実行して」「集約して/aggregateして」「retractして」「問いを差し替えて/supersedeして」「doctorして」「Tracefieldの結果を確認して」と言われた時に使用する。flow.toml/agents.jsonの設計判断は tracefield-flow-design を使う。
---

# Tracefield Operator

## Overview

Use the Rust `tracefield` CLI as the active implementation. Do not use removed
Mix/Elixir commands. This skill covers **running** the CLI (doctor / new / run /
persist / aggregate / retract). For **designing** what goes into `flow.toml` /
`agents.json` (lens selection, stage topology, mechanical aggregation, denoise),
use the [tracefield-flow-design](../tracefield-flow-design/SKILL.md) skill.

Build/run from the workspace with `./target/release/tracefield` (the
`~/.cargo/bin` copy can lag behind the source — rebuild if a flag like `--force`
or a subcommand is missing; see troubleshooting).

## Workflow

1. Check the runtime:

```sh
tracefield doctor
```

2. For a new task, scaffold a scenario:

```sh
tracefield new <name> --profile consult
tracefield new <name> --profile deep_investigation
```

Edit `scenarios/<name>/task.md`, `agents.json`, `flow.toml`, `inputs/*`, and
`private/*.md`. For the `agents.json` / directory format read
[references/scenario-format.md](references/scenario-format.md); for the full
`flow.toml` field spec, valid values, and what `model` to set per adapter read
[references/flow-spec.md](references/flow-spec.md).

Fetch web pages into Field Runner inputs when URLs are part of the task:

```sh
tracefield web-input --scenario-dir scenarios/<name> --url https://example.com/source
```

3. Run a model-free smoke first:

```sh
tracefield run --scenario-dir scenarios/<name>
```

4. Run a live adapter only after the mock path works:

Set `[organs.reasoning]` in `scenarios/<name>/flow.toml`:

```toml
[organs.reasoning]
adapter = "ollama"
model = "<model>"
```

```sh
tracefield run --scenario-dir scenarios/<name>
```

Use `adapter = "cli"` for local CLI models or `adapter = "openrouter"` when
`OPENROUTER_API_KEY` is set. `TRACEFIELD_CLI_COMMAND=claude|codex` remains valid
as a prefix to `tracefield run` for CLI-backed flows.

5. Persist when provenance or later retraction matters:

```sh
tracefield run --scenario-dir scenarios/<name> --persist runs/<name>.jsonl
```

For `tracefield run`, `--persist` also resumes from an existing JSONL store.
Configured artifacts write both the exported file and a `.manifest.json` sidecar
with source entry ids.
`deep_investigation` includes source discovery, deterministic source clustering,
per-input extraction, analysis, audit, report, and deck artifact stages.

6. When the flow has an `adjudication` stage, fold the per-refutation verdicts
   into a standing conclusion mechanically (no LLM):

```sh
tracefield aggregate --store runs/<name>.jsonl
```

Reports `maintained` (with the union of conditions), `changed` (any overturning
verdict), or `indeterminate` (an unclassifiable verdict is surfaced, never
dropped). Add `--stage <id>` if the adjudication stage is named otherwise.

7. Retract or supersede by entry id and inspect the downstream closure (same
   primitive: mark id + citation closure with a terminal status). Retract when a
   premise is **wrong**; supersede when a question/claim is **replaced**:

```sh
tracefield retract --store runs/<name>.jsonl --entry e3
tracefield supersede --store runs/<name>.jsonl --entry e3 --with e9
```

`supersede` marks the old entry and its downstream closure `Superseded`
(`superseded_by=<new>`) while keeping the replacement `Active` — making a
changed question a first-class, provenance-linked event. Re-run `aggregate`
afterward: the read path filters `Active`, so the stale closure drops out and
the basis is recomputed (no silent recompute — the closure is shown).

## Output Policy

- Use the readable report for humans.
- Use `--json` when another tool will parse stdout.
- Use `--out <file>` when the user asks to save a report.
- Use `--persist <jsonl>` when the user asks about provenance, retraction,
  auditability, or later comparison.

## Command Reference

Read [references/command-map.md](references/command-map.md) when choosing flags,
mapping a user request to a command, or checking which historical commands are no
longer available.

## Troubleshooting

Read [references/troubleshooting.md](references/troubleshooting.md) when
`doctor`, `run`, `ollama`, `openrouter`, `cli`, JSONL persistence, or
retraction fails.
