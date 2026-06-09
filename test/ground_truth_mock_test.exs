defmodule Tracefield.GroundTruthMockTest do
  use ExUnit.Case

  alias Tracefield.{GroundTruth, LLM, Scenario}

  test "mock end-to-end marks consent stance as affected" do
    scenario = Scenario.load!("scenarios/enterprise-assistant")

    {:ok, result} =
      GroundTruth.run(scenario,
        adapter: LLM.Mock,
        n: 6,
        temperature: 0.2,
        seed_base: 900,
        persist_runs: false
      )

    assert result.affected_set == MapSet.new([LLM.Mock.consent_topic()])
    assert result.ground_truth_set == result.affected_set
    assert result.stance_table[LLM.Mock.consent_topic()].differs
    assert result.proxy.recall == 1.0
    assert result.proxy.precision == 1.0
  end
end
