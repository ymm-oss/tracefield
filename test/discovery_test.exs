defmodule Tracefield.DiscoveryTest do
  use ExUnit.Case

  alias Tracefield.Discovery

  test "mock judge discovers entries containing both interaction keywords" do
    both =
      Discovery.score(
        [
          %{
            id: "e1",
            text: "The retention-90d security fact contradicts the delete-72h user promise."
          }
        ],
        judge_adapter: Tracefield.LLM.Mock,
        judge_model: "mock"
      )

    one_side =
      Discovery.score(
        [
          %{
            id: "e2",
            text: "The retention-90d security fact needs operational review."
          }
        ],
        judge_adapter: Tracefield.LLM.Mock,
        judge_model: "mock"
      )

    assert both.count == 1
    assert both.per_interaction["I1"]
    refute one_side.per_interaction["I1"]
    assert one_side.count == 0
  end
end
