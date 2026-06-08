# Tracefield MVP Running Notes

Run Elixir through mise:

```sh
mise exec -- mix compile
mise exec -- mix test
mise exec -- mix tracefield.phase0
mise exec -- mix tracefield.phase1 --adapter mock --n 8
```

For the live adapter, start Ollama locally and make sure the model exists:

```sh
ollama serve
ollama pull gemma4:12b
mise exec -- mix tracefield.phase1 --adapter ollama --n 2 --model gemma4:12b
```

Phase 1 prints within/between distance summaries, Mann-Whitney AUC, Cliff's delta,
the counterfactual ground-truth claim set, and proxy recall/precision. It also
writes JSON run records and a phase summary under `runs/`.
