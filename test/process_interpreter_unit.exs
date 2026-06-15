defmodule Tracefield.ProcessInterpreterTest do
  use ExUnit.Case, async: true

  alias Tracefield.ProcessInterpreter
  alias Tracefield.ProcessSpec
  alias Tracefield.ProcessSpec.{Edge, Gate, Stage}

  test "routes stage transitions from process spec" do
    spec = sample_spec()

    assert {:start, %Stage{id: "design"}} =
             ProcessInterpreter.route(spec, %{"stage" => "refine", "status" => "done"})

    assert {:resume, %Stage{id: "design"}} =
             ProcessInterpreter.route(spec, %{"stage" => "design", "status" => "awaiting_human"})

    assert {:complete, %Stage{id: "qa"}} =
             ProcessInterpreter.route(spec, %{"stage" => "qa", "status" => "done"})

    assert {:blocked, %Stage{id: "design"}, %Stage{id: "implement"}, :missing_workspace} =
             ProcessInterpreter.route(
               spec,
               %{"stage" => "design", "status" => "done"},
               can_enter?: fn %Stage{id: "implement"} -> false end,
               block_reason: fn %Stage{id: "implement"} -> :missing_workspace end
             )
  end

  test "derives produces, gate target types, and typed closure from spec data" do
    spec = sample_spec()

    assert ProcessSpec.produces(spec, "refine") == [:requirement, :question]
    assert ProcessSpec.produces(spec, "qa") == [:verdict]

    assert ProcessSpec.gate_target_types(spec) == [
             :requirement,
             :question,
             :decision,
             :observation
           ]

    assert ProcessSpec.closure_action(spec, :grounds) == :invalidate
    assert ProcessSpec.closure_action(spec, :verifies) == :reopen
  end

  defp sample_spec do
    %ProcessSpec{
      name: "dev-test",
      stages: [
        %Stage{
          id: "refine",
          procedure: "refine",
          produces: [:requirement, :question],
          cites: [%Edge{type: :grounds, into: :reference_doc}],
          gate: %Gate{review_types: [:requirement, :question], verdicts: [:approve]},
          on_done: "design"
        },
        %Stage{
          id: "design",
          procedure: "design",
          produces: [:decision],
          cites: [%Edge{type: :realizes, into: :requirement}],
          gate: %Gate{review_types: [:decision, :observation], verdicts: [:approve, :reject]},
          on_done: "implement"
        },
        %Stage{
          id: "implement",
          produces: [:change],
          cites: [%Edge{type: :realizes, into: :decision}],
          gate: %Gate{review_types: [], verdicts: [:approve]},
          on_done: "qa"
        },
        %Stage{
          id: "qa",
          produces: [:verdict],
          cites: [%Edge{type: :verifies, into: :change}],
          gate: %Gate{review_types: [], verdicts: [:pass, :fail]},
          on_done: nil
        }
      ],
      closure: %{grounds: :invalidate, realizes: :invalidate, verifies: :reopen}
    }
  end
end
