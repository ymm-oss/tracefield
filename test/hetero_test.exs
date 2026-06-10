defmodule Tracefield.HeteroTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Hetero

  test "mock e2e discovers private-document interactions only when shared state is presented" do
    result =
      Hetero.run_experiment(
        adapter_name: "mock-test",
        adapter: Tracefield.LLM.Mock,
        seeds: 1,
        rounds: 2,
        ks: [0, 2],
        model: "mock",
        judge_model: "mock",
        embed_model: "nomic-embed-text",
        temperature: 0.4
      )

    by_k = Map.new(result.runs, &{&1.k, &1})

    assert by_k[0].discovery_count == 0
    assert by_k[2].discovery_count > by_k[0].discovery_count
    assert is_integer(by_k[2].icc)
    assert is_integer(by_k[2].coverage)
    assert is_float(by_k[2].diversity)
    assert is_float(by_k[2].collapse_rate)
  end
end
