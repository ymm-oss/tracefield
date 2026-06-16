---
name: tracefield-operator
description: Tracefield Rust CLIでシナリオ作成、consult実行、JSONL永続化、retract検証、doctor診断を行う運用ガイド。「tracefieldで相談を回して」「scenarioを作って」「retractして」「doctorして」「Tracefieldの結果を確認して」と言われた時に使用する。
---

# Tracefield Operator

## Overview

Use the Rust `tracefield` CLI as the active implementation. Do not use removed
Mix/Elixir commands.

## Workflow

1. Check the runtime:

```sh
tracefield doctor
```

2. For a new task, scaffold a scenario:

```sh
tracefield new <name>
```

Edit `scenarios/<name>/task.md`, `agents.json`, and `private/*.md`. For the exact
format and agent-design rules, read [references/scenario-format.md](references/scenario-format.md).

3. Run a model-free smoke first:

```sh
tracefield consult --scenario-dir scenarios/<name> --adapter mock
```

4. Run a live adapter only after the mock path works:

```sh
tracefield consult --scenario-dir scenarios/<name> --adapter ollama --model <model>
```

Use `--adapter cli` for local CLI models or `--adapter openrouter` when
`OPENROUTER_API_KEY` is set.

5. Persist when provenance or later retraction matters:

```sh
tracefield consult --scenario-dir scenarios/<name> --adapter mock --persist runs/<name>.jsonl
```

6. Retract by entry id and inspect the downstream closure:

```sh
tracefield retract --store runs/<name>.jsonl --entry e3
```

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
`doctor`, `consult`, `ollama`, `openrouter`, `cli`, JSONL persistence, or
retraction fails.
