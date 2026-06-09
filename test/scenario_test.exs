defmodule Tracefield.ScenarioTest do
  use ExUnit.Case, async: true

  alias Tracefield.Scenario

  test "load returns scenario and strips harness-only injection text" do
    scenario = Scenario.load("scenarios/enterprise-assistant")

    assert %Scenario{} = scenario
    assert scenario.contaminant.id == "contaminant-A"
    assert scenario.correction.id == "correction-A"
    refute String.contains?(scenario.contaminant.body, "この入力の性質")
    refute String.contains?(scenario.contaminant.body, "注入方法")
    assert String.starts_with?(scenario.contaminant.body, "**事業責任者より")
  end

  test "load returns contaminant choices and decoys" do
    scenario = Scenario.load("scenarios/enterprise-assistant")

    assert Map.keys(scenario.contaminants) |> Enum.sort() == ["a", "b", "c"]
    assert scenario.contaminants["a"].contaminant.id == "contaminant-A"
    assert scenario.contaminants["b"].contaminant.id == "contaminant-B"
    assert scenario.contaminants["b"].correction.id == "correction-B"
    assert scenario.contaminants["c"].contaminant.id == "contaminant-C"

    assert Enum.map(scenario.decoys, & &1.id) == ["decoy-1", "decoy-2"]
    assert Enum.all?(scenario.decoys, &(&1.type == "decoy"))
    assert Enum.all?(scenario.decoys, &(&1.condition_state == "both"))
    refute Enum.any?(scenario.decoys, &String.contains?(&1.body, "この入力の性質"))
  end
end
