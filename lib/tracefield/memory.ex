defmodule Tracefield.Memory do
  @moduledoc """
  Private per-agent memory loading helpers.
  """

  def load(memory_dir, agent_id, window, opts \\ [])
  def load(_memory_dir, _agent_id, window, _opts) when window <= 0, do: {[], 0}

  def load(memory_dir, agent_id, window, opts) do
    memory_dir
    |> memory_path(agent_id)
    |> read_file()
    |> filter_stale(Keyword.get(opts, :store_entries))
    |> then(fn {entries, stale} -> {Enum.take(entries, -window), stale} end)
  end

  def read_file(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.flat_map(&decode_line/1)
    else
      []
    end
  end

  def filter_stale(entries, nil), do: {entries, 0}

  def filter_stale(entries, store_entries) do
    statuses =
      Map.new(store_entries, fn entry ->
        {entry_id(entry), entry_status(entry)}
      end)

    Enum.reduce(entries, {[], 0}, fn entry, {kept, stale} ->
      if stale?(entry, statuses) do
        {kept, stale + 1}
      else
        {kept ++ [entry], stale}
      end
    end)
  end

  def memory_path(memory_dir, agent_id), do: Path.join(memory_dir, "#{agent_id}.jsonl")

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, %{} = entry} ->
        [
          %{
            ts: Map.get(entry, "ts"),
            mode: Map.get(entry, "mode"),
            text: Map.get(entry, "text", "") |> to_string(),
            citations: normalize_citations(Map.get(entry, "citations", [])),
            raw: line
          }
        ]

      _other ->
        []
    end
  end

  defp stale?(entry, statuses) do
    Enum.any?(entry.citations, fn citation ->
      case Map.fetch(statuses, citation) do
        {:ok, :active} -> false
        {:ok, "active"} -> false
        {:ok, _status} -> true
        :error -> false
      end
    end)
  end

  defp normalize_citations(citations) do
    citations
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) or is_atom(&1) or is_integer(&1)))
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp entry_id(entry), do: entry_value(entry, :id)
  defp entry_status(entry), do: entry_value(entry, :status)

  defp entry_value(%{} = entry, key) do
    Map.get(entry, key, Map.get(entry, to_string(key)))
  end
end
