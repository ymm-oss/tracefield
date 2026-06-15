defmodule Tracefield.ProcessInterpreter do
  @moduledoc """
  Generic state-machine interpreter for `Tracefield.ProcessSpec`.

  The interpreter returns a route description. Callers keep ownership of
  stage-specific execution and side effects.
  """

  alias Tracefield.ProcessSpec
  alias Tracefield.ProcessSpec.Stage

  def route(%ProcessSpec{} = spec, state, runtime \\ []) when is_map(state) do
    cond do
      adopt_recruit = Keyword.get(runtime, :adopt_recruit) ->
        {:external, :adopt_recruit, adopt_recruit}

      Keyword.get(runtime, :status?, false) ->
        {:external, :status}

      true ->
        route_stage(spec, state, runtime)
    end
  end

  defp route_stage(spec, state, runtime) do
    current_stage = ProcessSpec.stage(spec, Map.get(state, "stage"))
    status = Map.get(state, "status")

    case {current_stage, status} do
      {nil, _status} ->
        {:start, ProcessSpec.first_stage!(spec)}

      {%Stage{} = stage, "done"} ->
        route_done(spec, stage, runtime)

      {%Stage{} = stage, "awaiting_human"} ->
        {:resume, stage}

      {%Stage{} = stage, _status} ->
        route_incomplete(spec, stage)
    end
  end

  defp route_done(spec, stage, runtime) do
    case ProcessSpec.next_stage(spec, stage) do
      nil ->
        {:complete, stage}

      %Stage{} = next_stage ->
        if can_enter?(runtime, stage, next_stage) do
          {:start, next_stage}
        else
          {:blocked, stage, next_stage, block_reason(runtime, stage, next_stage)}
        end
    end
  end

  defp route_incomplete(spec, stage) do
    first_stage = ProcessSpec.first_stage!(spec)

    cond do
      stage.id == first_stage.id ->
        {:start, stage}

      is_nil(stage.on_done) ->
        {:start, first_stage}

      true ->
        {:resume, stage}
    end
  end

  defp can_enter?(runtime, from_stage, next_stage) do
    case Keyword.get(runtime, :can_enter?) do
      nil -> true
      fun when is_function(fun, 1) -> fun.(next_stage)
      fun when is_function(fun, 2) -> fun.(from_stage, next_stage)
    end
  end

  defp block_reason(runtime, from_stage, next_stage) do
    case Keyword.get(runtime, :block_reason) do
      nil -> :blocked
      fun when is_function(fun, 1) -> fun.(next_stage)
      fun when is_function(fun, 2) -> fun.(from_stage, next_stage)
    end
  end
end
