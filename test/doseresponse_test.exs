defmodule Tracefield.DoseResponseTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Doseresponse

  test "mock e2e increases ICC with k_s and validates retract smoke" do
    result =
      Doseresponse.run_experiment(
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

    assert by_k[0].icc == 0
    assert by_k[2].icc > by_k[0].icc
    assert by_k[0].diversity > 0.0
    assert by_k[2].diversity > 0.0
    assert result.retract_smoke.ok
    assert result.retract_smoke.closure_ids != []
  end
end
