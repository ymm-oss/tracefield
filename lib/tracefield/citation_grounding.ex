defmodule Tracefield.CitationGrounding do
  @moduledoc """
  Deterministic citation grounding scorer for planted discovery interactions.

  A citation is grounded when the source entry strict-hits one or more planted
  interactions and the cited entry contains at least one keyword from those
  strict-hit interactions.
  """

  defmodule UngroundedCitation do
    @moduledoc "Details for a citation that did not ground in source strict-hit keywords."

    defstruct [
      :source_id,
      :cited_id,
      :source_interaction_ids,
      :source_keywords
    ]
  end

  def score(entries, interactions) do
    entries = List.wrap(entries)
    by_id = Map.new(entries, &{entry_value(&1, :id, ""), &1})

    pairs =
      entries
      |> Enum.flat_map(fn source ->
        source_keywords = strict_hit_keywords(source, interactions)

        source
        |> entry_value(:citations, [])
        |> List.wrap()
        |> Enum.map(fn cited_id ->
          cited = Map.get(by_id, citation_id(cited_id))
          grounded = grounded?(cited, source_keywords)

          %{
            source: source,
            cited_id: citation_id(cited_id),
            source_interactions: source_keywords.interactions,
            source_keywords: source_keywords.keywords,
            grounded: grounded
          }
        end)
      end)

    grounded_count = Enum.count(pairs, & &1.grounded)
    total_count = length(pairs)

    %{
      grounding_rate: rate(grounded_count, total_count),
      grounded_count: grounded_count,
      total_count: total_count,
      ungrounded:
        pairs
        |> Enum.reject(& &1.grounded)
        |> Enum.map(&ungrounded_citation/1)
    }
  end

  def to_plain(%{} = result) do
    Map.update!(result, :ungrounded, fn ungrounded ->
      Enum.map(ungrounded, &Map.from_struct/1)
    end)
  end

  defp strict_hit_keywords(source, interactions) do
    text = entry_value(source, :text, "")

    hits =
      interactions
      |> List.wrap()
      |> Enum.filter(fn interaction ->
        interaction
        |> interaction_keywords()
        |> Enum.all?(&String.contains?(text, &1))
      end)

    %{
      interactions: Enum.map(hits, &interaction_id/1),
      keywords: hits |> Enum.flat_map(&interaction_keywords/1) |> Enum.uniq()
    }
  end

  defp grounded?(nil, _source_keywords), do: false

  defp grounded?(cited, %{keywords: keywords}) do
    cited_text = entry_value(cited, :text, "")
    Enum.any?(keywords, &String.contains?(cited_text, &1))
  end

  defp ungrounded_citation(pair) do
    %UngroundedCitation{
      source_id: entry_value(pair.source, :id, ""),
      cited_id: pair.cited_id,
      source_interaction_ids: pair.source_interactions,
      source_keywords: pair.source_keywords
    }
  end

  defp rate(_grounded_count, 0), do: 0.0
  defp rate(grounded_count, total_count), do: grounded_count / total_count

  defp interaction_id(%{} = interaction),
    do: Map.get(interaction, :id, Map.get(interaction, "id"))

  defp interaction_id(_interaction), do: nil

  defp interaction_keywords(%{} = interaction) do
    interaction
    |> Map.get(:keywords, Map.get(interaction, "keywords", []))
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp interaction_keywords(_interaction), do: []

  defp citation_id(%{} = citation), do: Map.get(citation, :id, Map.get(citation, "id", ""))
  defp citation_id({id, _stance}), do: to_string(id)
  defp citation_id(id) when is_binary(id), do: id
  defp citation_id(id) when is_atom(id) or is_integer(id), do: to_string(id)
  defp citation_id(_id), do: ""

  defp entry_value(%{} = entry, key, default) do
    Map.get(entry, key, Map.get(entry, to_string(key), default))
  end

  defp entry_value(_entry, _key, default), do: default
end
