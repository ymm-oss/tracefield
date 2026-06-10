defmodule Tracefield.Meta do
  @moduledoc """
  Helpers for publishing to, discovering from, and pulling through a meta Reference.
  """

  alias Tracefield.Reference

  def publish(meta_ref, cluster_name, source_ref, opts \\ []) do
    ids =
      case Keyword.fetch(opts, :ids) do
        {:ok, ids} -> Enum.map(List.wrap(ids), &to_string/1)
        :error -> default_publish_ids(source_ref, Keyword.get(opts, :limit, 5))
      end

    exported = Enum.flat_map(ids, &Reference.export(source_ref, [&1]))
    Reference.import(meta_ref, exported, cluster_name)
  end

  def discover(meta_ref, query_text, opts \\ []) do
    k = opts |> Keyword.get(:k, 3) |> max(0)
    exclude_cluster = Keyword.get(opts, :exclude_cluster)
    all_count = meta_ref |> Reference.all() |> length()

    meta_ref
    |> Reference.serve(query_text, k: all_count, policy: :similar)
    |> reject_cluster(exclude_cluster)
    |> Enum.take(k)
    |> Enum.map(fn entry ->
      %{
        entry: entry,
        source_cluster: meta_value(entry.meta, :source_cluster),
        source_id: meta_value(entry.meta, :source_id)
      }
    end)
  end

  def pull(target_ref, meta_ref, entry_ids) do
    meta_ref
    |> Reference.export(List.wrap(entry_ids))
    |> then(&Reference.import(target_ref, &1, "META"))
  end

  defp default_publish_ids(source_ref, limit) do
    entries = Reference.all(source_ref)

    counts =
      entries
      |> Enum.filter(&(&1.status == :active))
      |> Enum.flat_map(& &1.citations)
      |> Enum.frequencies()

    entries
    |> Enum.filter(&(&1.status == :active))
    |> Enum.reject(&(&1.type in [:chunk, :procedure]))
    |> Enum.map(&{&1, Map.get(counts, &1.id, 0)})
    |> Enum.sort_by(fn {entry, count} -> {-count, -entry_number(entry.id)} end)
    |> Enum.take(max(limit, 0))
    |> Enum.map(fn {entry, _count} -> entry.id end)
  end

  defp reject_cluster(entries, nil), do: entries

  defp reject_cluster(entries, cluster_name) do
    prefix = "#{cluster_name}/"
    Enum.reject(entries, &String.starts_with?(&1.author, prefix))
  end

  defp meta_value(meta, key) when is_map(meta) do
    value = Map.get(meta, key, Map.get(meta, to_string(key)))
    if is_nil(value), do: nil, else: to_string(value)
  end

  defp meta_value(_meta, _key), do: nil

  defp entry_number("e" <> number) do
    case Integer.parse(number) do
      {value, ""} -> value
      _other -> 0
    end
  end

  defp entry_number(_id), do: 0
end
