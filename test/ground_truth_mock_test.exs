defmodule Tracefield.GroundTruthMockTest do
  use ExUnit.Case

  alias Tracefield.{GroundTruth, LLM, Scenario}

  test "mock end-to-end separates contaminant signal from noise" do
    scenario = Scenario.load!("scenarios/enterprise-assistant")

    {:ok, result} =
      GroundTruth.run(scenario,
        adapter: LLM.Mock,
        n: 6,
        temperature: 0.2,
        seed_base: 900,
        persist_runs: false
      )

    assert result.between_summary.mean > result.within_summary.mean
    assert result.auc > 0.8
    assert result.ground_truth_set == MapSet.new(LLM.Mock.signal_claim_ids())
    assert result.proxy.recall == 1.0
  end
end
