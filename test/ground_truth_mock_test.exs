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

  test "mock c1 condition completes with affected set and provenance" do
    scenario = Scenario.load!("scenarios/enterprise-assistant")

    {:ok, result} =
      GroundTruth.run(scenario,
        adapter: LLM.Mock,
        n: 2,
        temperature: 0.2,
        seed_base: 940,
        condition: :c1,
        persist_runs: false
      )

    assert result.condition == :c1
    assert %MapSet{} = result.affected_set
    assert %MapSet{} = result.c5_affected_points
    assert %MapSet{} = result.c5_quarantine
    assert Enum.all?(result.runs_a ++ result.runs_b, &(&1.condition == :c1))
  end

  test "explore injects selected contaminant and identical decoys in both states" do
    scenario = Scenario.load!("scenarios/enterprise-assistant")
    decoys = scenario.decoys

    {:ok, run_a} =
      Tracefield.Explore.run(scenario,
        adapter: LLM.Mock,
        state: :a,
        contaminant: "b",
        decoys: decoys,
        n_agents: 1,
        rounds: 1,
        persist_runs: false
      )

    {:ok, run_b} =
      Tracefield.Explore.run(scenario,
        adapter: LLM.Mock,
        state: :b,
        contaminant: "b",
        decoys: decoys,
        n_agents: 1,
        rounds: 1,
        persist_runs: false
      )

    injected_a = Enum.filter(run_a.transcript, &Map.has_key?(&1, :injection_id))
    injected_b = Enum.filter(run_b.transcript, &Map.has_key?(&1, :injection_id))

    assert Enum.map(injected_a, & &1.injection_id) == ["contaminant-B", "decoy-1", "decoy-2"]
    assert Enum.map(injected_b, & &1.injection_id) == ["correction-B", "decoy-1", "decoy-2"]

    assert hd(injected_a).content == scenario.contaminants["b"].contaminant.body
    assert hd(injected_b).content == scenario.contaminants["b"].correction.body
    assert Enum.map(tl(injected_a), & &1.content) == Enum.map(tl(injected_b), & &1.content)
  end

  test "mock accepts contaminant b and decoys without semantic support" do
    scenario = Scenario.load!("scenarios/enterprise-assistant")

    {:ok, result} =
      GroundTruth.run(scenario,
        adapter: LLM.Mock,
        n: 1,
        temperature: 0.2,
        seed_base: 960,
        contaminant: "b",
        decoys: scenario.decoys,
        persist_runs: false
      )

    assert result.contaminant == "b"
    assert result.decoys == ["decoy-1", "decoy-2"]
    assert %MapSet{} = result.affected_set
  end
end
