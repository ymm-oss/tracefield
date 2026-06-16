# tracefield

> **Governable exploration for multi-agent systems.** A research harness for
> *semi-soluble orchestration* — letting AI agents collaborate openly while
> keeping the downstream influence of every input **traceable, isolable, and
> retractable**.

`tracefield` is an experimental Elixir project that investigates a single design
hypothesis:

> Can open-ended multi-agent exploration retain **provenance**, **reversibility**,
> and **gateability** — so that when a contaminated, false, or retracted input
> enters the system, its downstream impact can be located, isolated, excised, and
> re-evaluated?

The detailed design notes, experiment plans, and findings live in [`docs/`](./docs)
and are written in Japanese. This README is a short English entry point.

---

## The idea in one screen

Multi-agent exploration faces a well-known trade-off:

| Mode | Openness | Governability |
| --- | --- | --- |
| Free-form exploration | high — reaches interstitial blind spots nobody owns | low — contamination is hard to trace, isolate, or retract |
| Fixed-role pipeline | low — rigid, misses cross-role blind spots | high — clear ownership and stop points |
| **Semi-soluble orchestration** | retains high openness | retains provenance / reversibility / gateability |

The core value tested here is **not "find more blind spots"** — that is just a
matter of adding agents. The primary outcome is **impact recall / precision**: how
accurately the system can identify and contain the downstream influence of a bad
input once it is discovered.

"Semi"-soluble means agents share state deeply enough to collaborate beyond the
bottleneck of natural language, but not so completely that each agent's bias
(perspective, expertise, originality) dissolves into a uniform blur — because that
diversity is what makes multi-agent exploration worth doing.

See [`docs/overview.md`](./docs/overview.md) for the full conceptual background and
[`docs/glossary.md`](./docs/glossary.md) for terminology.

---

## Requirements

- [Elixir](https://elixir-lang.org/) ~> 1.18 (the repo is pinned to 1.20 / OTP 29 via [`mise`](https://mise.jdx.io/))
- For live runs: a local [Ollama](https://ollama.com/) instance, or an
  `OPENROUTER_API_KEY` for cross-family runs via [OpenRouter](https://openrouter.ai/)
- A mock adapter is built in, so the test suite and demos run with no model at all

## Quick start

```sh
# install the pinned toolchain
mise install

# fetch deps, compile, test
mise exec -- mix deps.get
mise exec -- mix compile
mise exec -- mix test

# run a phase with the mock adapter (no model needed)
mise exec -- mix tracefield.phase1 --adapter mock --n 8
```

For live runs with a local model:

```sh
ollama serve
ollama pull gemma4:12b
mise exec -- mix tracefield.phase1 --adapter ollama --n 2 --model gemma4:12b
```

See [`RUNNING.md`](./RUNNING.md) for more run notes.

## Mix tasks

The harness is driven through `mix tracefield.*` tasks. A few entry points:

| Task | Purpose |
| --- | --- |
| `mix tracefield.consult` | Consult the team; return a governed best-of-N synthesis |
| `mix tracefield.phase0` / `.phase1` | Core experiment phases |
| `mix tracefield.governance_vs_fusion` | Compare provenance-closure governance vs post-hoc fusion containment |
| `mix tracefield.hetero` | Private-document substrate-heterogeneity experiment |
| `mix tracefield.retract` | Retract an entry in a persisted store and show isolated synthesis |
| `mix tracefield.genesis` | Attractor detection and cluster scaffolding |

Run `mise exec -- mix help` to see the full list.

## Repository layout

```
lib/tracefield/     core: field, provenance, stance, synthesis, llm adapters, ...
lib/mix/tasks/      mix tracefield.* entry points
scenarios/          synthetic, fictional consulting scenarios (test fixtures)
docs/               design notes, experiment plans, findings (Japanese)
test/               ExUnit test suite
experiments/        Python analysis scripts for run outputs
```

> All scenario data under `scenarios/` — including the per-agent "private fact"
> memos under `scenarios/*/private/` — is **synthetic and fictional**. No real
> client or personal data is included.

## Status

This is a **research project**, not a stable library. APIs, task names, and scenario
formats change as experiments evolve. Findings are recorded under `docs/findings-*.md`
and summarized in [`docs/conclusions.md`](./docs/conclusions.md).

## License

Licensed under the [Apache License, Version 2.0](./LICENSE).

Copyright 2026 Ryoichi Izumita. See [`NOTICE`](./NOTICE) for attribution details.

## Contact

Ryoichi Izumita — ryoichi.a.izumita@accenture.com
