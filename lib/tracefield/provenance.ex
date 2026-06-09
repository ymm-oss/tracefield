defmodule Tracefield.Provenance do
  @moduledoc """
  Point-level provenance graph for in-process dependency tracking.
  """

  def build(runs, opts \\ []) when is_list(runs) do
    injection_ids = Keyword.get(opts, :injection_ids, :all)
    points = points(runs)
    injection_nodes = injection_nodes(runs, injection_ids)
    turn_points = group_points_by_turn(points)

    injection_by_turn =
      Map.new(injection_nodes, fn node -> {{node.run_key, node.turn_id}, node.id} end)

    edges =
      points
      |> Enum.flat_map(fn point ->
        dependency_edges(point, turn_points, injection_by_turn) ++
          injection_edges(point, injection_nodes)
      end)
      |> MapSet.new()

    node_ids =
      MapSet.union(
        MapSet.new(Enum.map(points, & &1.id)),
        MapSet.new(Enum.map(injection_nodes, & &1.id))
      )

    c5_affected_points = downstream_points(edges, injection_nodes, node_ids)

    %{
      nodes: node_ids,
      point_nodes: Map.new(points, &{&1.id, &1}),
      injection_nodes: Map.new(injection_nodes, &{&1.id, &1}),
      edges: edges,
      c5_affected_points: c5_affected_points,
      c5_quarantine: c5_affected_points
    }
  end

  def compare(c5_affected_points, c4_affected_points) do
    c5 = MapSet.new(c5_affected_points)
    c4 = MapSet.new(c4_affected_points)

    %{
      c5_affected_points: c5,
      c4_affected_points: c4,
      c5_minus_c4: MapSet.difference(c5, c4)
    }
  end

  def points(runs) when is_list(runs) do
    runs
    |> Enum.flat_map(fn run ->
      run_key = Map.get(run, :run_key, Map.get(run, "run_key", "run"))

      run
      |> Map.get(:transcript, Map.get(run, "transcript", []))
      |> Enum.flat_map(&points_for_turn(&1, run_key))
    end)
  end

  defp points_for_turn(%{} = turn, run_key) do
    turn_id = turn_id(turn)

    turn
    |> Map.get(:points, Map.get(turn, "points", []))
    |> case do
      points when is_list(points) ->
        points
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {point, index} ->
          case normalize_point(point, run_key, turn_id, index) do
            nil -> []
            point -> [point]
          end
        end)

      _ ->
        []
    end
  end

  defp points_for_turn(_turn, _run_key), do: []

  defp normalize_point(%{} = point, run_key, turn_id, index) when is_integer(turn_id) do
    local_id = value(point, :point_id, "t#{turn_id}.p#{index}")
    text = value(point, :text, "")

    if is_binary(text) and String.trim(text) != "" do
      %{
        id: global_point_id(run_key, local_id),
        run_key: run_key,
        turn_id: turn_id,
        point_id: local_id,
        text: String.trim(text),
        depends_on_turns: normalize_depends(value(point, :depends_on_turns, [])),
        uses_injection: value(point, :uses_injection, false) == true
      }
    end
  end

  defp normalize_point(_point, _run_key, _turn_id, _index), do: nil

  defp injection_nodes(runs, injection_ids) do
    runs
    |> Enum.flat_map(fn run ->
      run_key = Map.get(run, :run_key, Map.get(run, "run_key", "run"))

      run
      |> Map.get(:transcript, Map.get(run, "transcript", []))
      |> Enum.flat_map(fn
        %{} = turn ->
          injection_id = value(turn, :injection_id)
          turn_id = turn_id(turn)

          if is_integer(turn_id) and injection_id != nil and
               include_injection?(injection_id, injection_ids) do
            [
              %{
                id: global_injection_id(run_key, turn_id, injection_id),
                run_key: run_key,
                turn_id: turn_id,
                injection_id: injection_id,
                text: value(turn, :content, "")
              }
            ]
          else
            []
          end

        _turn ->
          []
      end)
    end)
  end

  defp include_injection?(_injection_id, :all), do: true
  defp include_injection?(injection_id, injection_ids), do: injection_id in injection_ids

  defp group_points_by_turn(points) do
    Enum.reduce(points, %{}, fn point, acc ->
      Map.update(acc, {point.run_key, point.turn_id}, [point.id], &(&1 ++ [point.id]))
    end)
  end

  defp dependency_edges(point, turn_points, injection_by_turn) do
    Enum.flat_map(point.depends_on_turns, fn turn_id ->
      point_edges =
        turn_points
        |> Map.get({point.run_key, turn_id}, [])
        |> Enum.map(fn dep_id -> {point.id, dep_id} end)

      injection_edges =
        case Map.get(injection_by_turn, {point.run_key, turn_id}) do
          nil -> []
          injection_id -> [{point.id, injection_id}]
        end

      point_edges ++ injection_edges
    end)
  end

  defp injection_edges(%{uses_injection: true} = point, injection_nodes) do
    injection_nodes
    |> Enum.filter(&(&1.run_key == point.run_key))
    |> Enum.map(fn node -> {point.id, node.id} end)
  end

  defp injection_edges(_point, _injection_nodes), do: []

  defp downstream_points(edges, injection_nodes, node_ids) do
    reverse_edges =
      Enum.reduce(edges, %{}, fn {from, to}, acc ->
        Map.update(acc, to, MapSet.new([from]), &MapSet.put(&1, from))
      end)

    starts = MapSet.new(Enum.map(injection_nodes, & &1.id))

    closure(reverse_edges, starts, MapSet.new())
    |> MapSet.intersection(node_ids)
    |> MapSet.difference(starts)
  end

  defp closure(reverse_edges, frontier, seen) do
    if MapSet.size(frontier) == 0 do
      seen
    else
      next_seen = MapSet.union(seen, frontier)

      next_frontier =
        frontier
        |> Enum.reduce(MapSet.new(), fn node, acc ->
          MapSet.union(acc, Map.get(reverse_edges, node, MapSet.new()))
        end)
        |> MapSet.difference(next_seen)

      closure(reverse_edges, next_frontier, next_seen)
    end
  end

  defp global_point_id(run_key, point_id), do: "#{run_key}|#{point_id}"

  defp global_injection_id(run_key, turn_id, injection_id),
    do: "#{run_key}|injection:#{injection_id}:t#{turn_id}"

  defp turn_id(turn), do: parse_integer(value(turn, :turn_id))

  defp normalize_depends(depends) when is_list(depends) do
    depends
    |> Enum.map(&parse_integer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_depends(_depends), do: []

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
