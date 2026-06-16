# Contributing to tracefield

Thanks for your interest. `tracefield` is a research project, so APIs, command
names, and scenario formats may change as experiments evolve. Please open an
issue to discuss substantial changes before sending a large patch.

## Development Setup

```sh
cargo build --release -p tracefield
cargo check -p tracefield
cargo test
```

The built-in `mock` adapter means the test suite and smoke scenarios run with no
model. Live runs need a local [Ollama](https://ollama.com/) instance or an
`OPENROUTER_API_KEY`.

## Before Opening A Pull Request

- Run the formatter: `cargo fmt --check`
- Run the checks: `cargo check -p tracefield`
- Run the tests: `cargo test`
- Keep changes focused; explain the why in the PR description
- For experiment changes, record what you found under `docs/findings-*.md`

## Scenario Data

All data under `scenarios/` is **synthetic and fictional**. Do not add real
client, customer, or personal data to this repository.

## Licensing

By contributing, you agree that your contributions are licensed under the
[Apache License, Version 2.0](./LICENSE), consistent with the rest of the
project.
