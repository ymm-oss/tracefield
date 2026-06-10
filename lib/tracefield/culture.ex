defmodule Tracefield.Culture do
  @moduledoc """
  Culture transmission measurements for a Reference store or entry list.
  """

  alias Tracefield.Embed
  alias Tracefield.Reference

  def transmission(ref_or_entries, charter_text, opts \\ []) do
    entries =
      ref_or_entries
      |> entries()
      |> Enum.filter(&candidate?/1)

    charter_embedding = embed_one(charter_text, opts)

    aligned =
      Enum.map(entries, fn entry ->
        {entry, Embed.cosine(entry.embedding, charter_embedding)}
      end)

    %{
      alignment: mean(Enum.map(aligned, fn {_entry, score} -> score end)),
      per_author: per_author(aligned),
      member_diversity: member_diversity(entries),
      n: length(entries)
    }
  end

  defp entries(list) when is_list(list), do: list
  defp entries(ref), do: Reference.all(ref)

  defp candidate?(entry) do
    entry.status == :active and entry.type not in [:chunk, :procedure, :genesis]
  end

  defp per_author(aligned) do
    aligned
    |> Enum.group_by(fn {entry, _score} -> entry.author end, fn {_entry, score} -> score end)
    |> Map.new(fn {author, scores} -> {author, mean(scores)} end)
  end

  defp member_diversity(entries) do
    entries_by_author = Enum.group_by(entries, & &1.author)

    if map_size(entries_by_author) < 2 do
      0.0
    else
      distances =
        for {author_a, entries_a} <- entries_by_author,
            {author_b, entries_b} <- entries_by_author,
            author_a < author_b,
            entries_a != [],
            entries_b != [] do
          (1.0 - sym_mean_max_cos(entries_a, entries_b))
          |> zero_near_zero()
        end

      mean(distances)
    end
  end

  defp sym_mean_max_cos(entries_a, entries_b) do
    (mean_max_cos(entries_a, entries_b) + mean_max_cos(entries_b, entries_a)) / 2.0
  end

  defp mean_max_cos(source, target) do
    source
    |> Enum.map(fn entry ->
      target
      |> Enum.map(&Embed.cosine(entry.embedding, &1.embedding))
      |> Enum.max(fn -> 0.0 end)
    end)
    |> mean()
  end

  defp embed_one(text, opts) do
    case Embed.embed([to_string(text)], embed_opts(opts)) do
      {:ok, [embedding]} -> embedding
      {:error, _reason} -> []
    end
  end

  defp embed_opts(opts) do
    [
      adapter: Keyword.get(opts, :embed_adapter, Tracefield.Embed.Mock),
      model: Keyword.get(opts, :embed_model, "nomic-embed-text")
    ]
  end

  defp mean([]), do: 0.0
  defp mean(values), do: Enum.sum(values) / length(values)

  defp zero_near_zero(value) when abs(value) < 1.0e-12, do: 0.0
  defp zero_near_zero(value), do: value
end
