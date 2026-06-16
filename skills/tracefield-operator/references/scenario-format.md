# Scenario Format

Use this reference when creating or editing a Tracefield scenario.

## Directory Shape

```text
scenarios/<name>/
├── task.md
├── agents.json
└── private/
    ├── lens1.md
    └── lens2.md
```

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
      "doc": "risk.md"
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

## private/*.md

Each file contains one agent's private lens. Keep it factual and scoped:

```markdown
Known constraints:
- Support tickets must keep audit trails for 180 days.
- Operators currently handle about 400 tickets per week.

Concerns:
- Role boundaries are ambiguous during escalation.
```

## Quality Checks

Before running live adapters:

```sh
tracefield consult --scenario-dir scenarios/<name> --adapter mock
```

If the mock output is empty or generic, improve `task.md`, `desc`, and the
private documents before using a live model.
