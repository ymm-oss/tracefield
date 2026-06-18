# Scenario Format

Use this reference when creating or editing a Tracefield scenario.

## Directory Shape

```text
scenarios/<name>/
├── task.md
├── agents.json
├── flow.toml
├── inputs/
│   ├── example.md
│   └── web/
│       └── 01-source.md
├── skills/
│   └── review/
│       └── SKILL.md
└── private/
    ├── lens1.md
    └── lens2.md
```

`tracefield web-input --scenario-dir scenarios/<name> --url <url>` creates
`inputs/web/*.md` files with `source_url`, `fetched_at`, `content_type`, and
`bytes` frontmatter. Field Runner seeds those files as normal `kind:input`
entries.

## task.md

Write the shared task. Keep it concrete enough that every agent can answer from
its lens.

Good task:

```markdown
Evaluate the proposed internal support workflow and identify risks, missing
requirements, and operational tradeoffs.
```

Avoid mixing private facts into `task.md`; put role-specific evidence in
`private/*.md`.

## agents.json

Use either wrapped or raw form. Wrapped form is preferred:

```json
{
  "agents": [
    {
      "id": "RISK",
      "domain": "risk",
      "desc": "Focus on failure modes, compliance, and operational constraints.",
      "doc": "risk.md",
      "skills": ["review"]
    },
    {
      "id": "VALUE",
      "domain": "value",
      "desc": "Focus on user value, adoption, and business outcomes.",
      "doc": "value.md"
    }
  ]
}
```

Fields:

- `id`: short stable author id used in entries.
- `domain`: retrieval/query hint.
- `desc`: role instruction.
- `doc`: file name under `private/`.
- `model`: optional per-agent model override.
- `skills`: optional list of scenario-local skill ids. Each id must use
  lowercase ASCII letters, digits, or `-`, and resolves to
  `skills/<id>/SKILL.md`.

## private/*.md

Each file contains one agent's private lens. Keep it factual and scoped:

```markdown
Known constraints:
- Support tickets must keep audit trails for 180 days.
- Operators currently handle about 400 tickets per week.

Concerns:
- Role boundaries are ambiguous during escalation.
```

## inputs/*

`inputs/` contains generic source material for `tracefield run`. Markdown, text,
JSON, and JSONL files are seeded as `corpus_chunk` entries with `meta.kind =
"input"`.

Use this for web page captures, source notes, issue text, logs, client docs, or
other profile-specific input material.

Stage `inputs` selectors support `kind:input`, `stage:<id>`,
`entry_type:<type>`, `path:<inputs/...>`, `source_url:<url>`, and `all`. Use
`path:` or `source_url:` for small smoke runs and targeted recollection.

## flow.toml

`flow.toml` configures the Field Runner. It defines stages, organ routing, actor
scaling, feedback, and artifacts.

`tracefield new <name>` creates the default mock flow. Use
`tracefield new <name> --profile consult` for a consult-style flow with
`[organs.reasoning] adapter = "mock"` and `[long_run] cycles = 2`. Use
`tracefield new <name> --profile deep_investigation` for the long-horizon
investigation template with source discovery, source clustering, data
extraction, hypothesis, lens analysis, audit, report, and deck stages.
`per_input`, `per_source`, and `per_cluster` actor modes shard selected entries
across actors. A stage with `[stages.<id>.clustering]` creates deterministic
cluster entries with `source_cluster` metadata and citations to the source
entries.

`[stages.<id>.actors] roles` is the single source that binds an actor to a lens.
When a role string matches an `agents.json` `id`, that agent drives the actor:
its `domain`/`desc`/`private` document and the `actor_role` label all come from
that one agent, so each entry's authoring lens stays unambiguous in provenance.
Role strings that do not match an agent id stay free-text labels (the agent is
assigned by position, as before). When `roles` is omitted, the bound agent's
`domain` becomes the role automatically — define a lens once in `agents.json`
instead of restating it per stage.

Agent-produced feedback for Tracefield itself is represented as normal entries
with `meta.kind = "tracefield_feedback"`. Configure routing with
`[feedback_entries]`:

```toml
[feedback_entries]
enabled = true
kind = "tracefield_feedback"
accepted_types = ["change", "requirement", "question", "audit"]
status_field = "status"
dedupe_by = ["target", "action", "normalized_request"]

[[feedback_entries.route]]
target_prefix = "input.web"
to = "source_discovery"

[[feedback_entries.route]]
target_prefix = "flow."
to = "feedback_triage"
```

Recommended feedback metadata:

```json
{"kind":"tracefield_feedback","target":"flow.stage.source_extract","action":"change","priority":"high","status":"proposed"}
```

Minimal mock flow:

```toml
[flow]
profile = "default"
policy = "fixed"

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "per_input"
max = 2

[stages.analyze]
organ = "reasoning"
inputs = ["stage:collect"]
outputs = ["synthesis", "question"]

[stages.analyze.actors]
mode = "fixed"
count = 1

[artifacts.summary]
format = "markdown"
from_stage = "analyze"
path = "outputs/summary.md"
```

## skills

Use skills for user-defined procedures that should influence an agent and remain
auditable. Referenced skills are loaded as `procedure` entries and every entry
produced by the agent automatically cites those procedure entries.

```markdown
---
name: review
description: Check claims against explicit evidence before recommending changes.
---

# Review

Before recommending a change, check whether the claim depends on an explicit
source, a private lens, or an assumption that should be stated separately.
```

The folder name, `agents.json` id, and frontmatter `name` must match. In the
example above, the file must be `skills/review/SKILL.md` and agents reference it
with `"skills": ["review"]`.

Skill delivery depends on the adapter:

- **Ollama and OpenRouter** use progressive disclosure via function calling. The
  prompt lists only each skill's name and description, and the agent pulls the
  rest through tools: `read_skill` loads `SKILL.md` or any bundled `references/`
  file, and `run_skill_script` executes a file under the skill's `scripts/`
  directory (confined to that directory, with the skill folder as cwd). Every
  tool call is recorded as an `observation` entry citing the skill, so the field
  captures exactly which material the agent read or ran. Use a tool-capable
  model.
- **mock and CLI** inject the full `SKILL.md` instructions into the prompt and
  do not read `references/` or run `scripts/`. (The CLI's own runtime only
  discovers skills in its environment, not scenario-local ones, so injection is
  how scenario skills reach it.)

In all cases the skill is tracked as a `procedure` entry.

## Quality Checks

Before running live adapters:

```sh
tracefield run --scenario-dir scenarios/<name>
```

If the mock output is empty or generic, improve `task.md`, `desc`, and the
private documents before using a live model.
