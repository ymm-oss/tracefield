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
end
