# Contributing to tracefield

Thanks for your interest. `tracefield` is a research project, so APIs, mix task
names, and scenario formats change as experiments evolve. Contributions are
welcome, but please open an issue to discuss anything substantial before sending a
large change.

## Development setup

```sh
mise install                 # installs the pinned Elixir/OTP toolchain
mise exec -- mix deps.get
mise exec -- mix compile
mise exec -- mix test
```

A built-in `mock` adapter means the full test suite runs with no model. Live runs
need a local [Ollama](https://ollama.com/) instance or an `OPENROUTER_API_KEY`.

## Before opening a pull request

- Run the formatter: `mise exec -- mix format`
- Run the tests: `mise exec -- mix test`
- Keep changes focused; explain the *why* in the PR description
- For experiment changes, record what you found under `docs/findings-*.md` so the
  result is reproducible and the reasoning is preserved

## Scenario data

All data under `scenarios/` is **synthetic and fictional**. Do not add real client,
customer, or personal data to this repository.

## Licensing

By contributing, you agree that your contributions are licensed under the
[Apache License, Version 2.0](./LICENSE), consistent with the rest of the project.
