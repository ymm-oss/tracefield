defmodule Tracefield.ProcessSpec do
  @moduledoc """
  Data schema for Tracefield knowledge-process control.

  A process spec names the stages, the entry types each stage produces, the
  typed citation edges it expects, human gates, transitions, and the typed
  ramification closure scaffold.
  """

  defstruct name: nil, stages: [], closure: %{}

  defmodule Stage do
    @moduledoc "A single process stage."
    defstruct id: nil,
              procedure: nil,
              produces: [],
              cites: [],
              gate: nil,
              on_done: nil
  end

  defmodule Edge do
    @moduledoc "A typed citation/dependency edge expected from a stage."
    defstruct type: nil, into: nil
  end

  defmodule Gate do
    @moduledoc "Human review gate data for a stage."
    defstruct review_types: [], verdicts: []
  end

  def first_stage!(%__MODULE__{stages: [stage | _]}), do: stage

  def first_stage!(%__MODULE__{name: name}) do
    raise ArgumentError, "process #{inspect(name)} has no stages"
  end

  def stage(%__MODULE__{stages: stages}, id) do
    wanted = to_string(id)
    Enum.find(stages, &(to_string(&1.id) == wanted))
  end

  def stage!(%__MODULE__{} = spec, id) do
    stage(spec, id) ||
      raise ArgumentError, "unknown stage #{inspect(id)} in process #{inspect(spec.name)}"
  end

  def next_stage(%__MODULE__{}, %Stage{on_done: nil}), do: nil
  def next_stage(%__MODULE__{} = spec, %Stage{on_done: next_id}), do: stage!(spec, next_id)

  def produces(%__MODULE__{} = spec, stage_id) do
    spec
    |> stage!(stage_id)
    |> Map.fetch!(:produces)
  end

  def gate_target_types(%__MODULE__{stages: stages}) do
    stages
    |> Enum.flat_map(fn
      %Stage{gate: %Gate{review_types: review_types}} -> review_types
      _stage -> []
    end)
    |> Enum.uniq()
  end

  def closure_action(%__MODULE__{closure: closure}, edge_type) do
    action =
      Map.get(closure, edge_type) ||
        Map.get(closure, to_string(edge_type)) ||
        closure_atom_lookup(closure, edge_type)

    normalize_closure_action(action)
  end

  defp closure_atom_lookup(closure, edge_type) when is_binary(edge_type) do
    Map.get(closure, String.to_existing_atom(edge_type))
  rescue
    ArgumentError -> nil
  end

  defp closure_atom_lookup(_closure, _edge_type), do: nil

  defp normalize_closure_action(action) when is_binary(action) do
    String.to_existing_atom(action)
  rescue
    ArgumentError -> action
  end

  defp normalize_closure_action(action), do: action
end
