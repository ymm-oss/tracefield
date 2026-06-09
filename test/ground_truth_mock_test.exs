defmodule Tracefield.GroundTruthMockTest do
  use ExUnit.Case

  alias Tracefield.{GroundTruth, LLM, Provenance, Scenario}

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

  test "mock in-process provenance captures indirect chain missed by c4" do
    scenario = Scenario.load!("scenarios/enterprise-assistant")

    {:ok, result} =
      GroundTruth.run(scenario,
        adapter: LLM.Mock,
        n: 1,
        temperature: 0.2,
        seed_base: 920,
        n_agents: 4,
        rounds: 2,
        persist_runs: false
      )

    assert MapSet.subset?(result.c4_affected_points, result.c5_affected_points)
    assert MapSet.size(result.c5_affected_points) > MapSet.size(result.c4_affected_points)

    points_by_label =
      result.runs_a
      |> Kernel.++(result.runs_b)
      |> Provenance.points()
      |> Enum.flat_map(fn point ->
        case Regex.run(~r/PROV-[XYZ]/, point.text) do
          [label] -> [{label, point.id}]
          _ -> []
        end
      end)
      |> Map.new()

    assert points_by_label["PROV-X"] in result.c4_affected_points
    assert points_by_label["PROV-Y"] in result.c5_minus_c4
    assert points_by_label["PROV-Z"] in result.c5_minus_c4
  end
end
