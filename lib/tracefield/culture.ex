defmodule Tracefield.Culture do
  @moduledoc """
  Culture transmission measurements for a Reference store or entry list.
  """

  alias Tracefield.Embed
  alias Tracefield.Reference

  @non_distillable_types [:chunk, :procedure, :genesis, :house_view]

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

  def distill(ref, opts \\ []) do
    sources = distill_sources(ref, Keyword.get(opts, :limit, 5))

    case sources do
      [] ->
        {:error, :nothing_to_distill}

      sources ->
        predecessor = latest_house_view(ref, :any)
        version = house_view_version(predecessor) + 1
        mode = Keyword.get(opts, :mode, :extractive)
        text = distill_text(mode, sources, version, opts)
        citations = Enum.map(sources, & &1.id) ++ predecessor_citation(predecessor)

        [house_view] =
          Reference.absorb(
            ref,
            [
              %{
                type: :house_view,
                text: text,
                citations: citations,
                meta: %{house_view_version: version}
              }
            ],
            "CULTURE"
          )

        if predecessor && predecessor.status == :active do
          Reference.quarantine(ref, [predecessor.id])
        end

        {:ok, house_view}
    end
  end

  def house_view(ref), do: latest_house_view(ref, :active)

  defp distill_sources(ref, limit) do
    entries = Reference.all(ref)

    counts =
      entries
      |> Enum.filter(&(&1.status == :active))
      |> Enum.flat_map(& &1.citations)
      |> Enum.frequencies()

    entries
    |> Enum.filter(&distill_candidate?/1)
    |> Enum.map(&{&1, Map.get(counts, &1.id, 0)})
    |> Enum.sort_by(fn {entry, count} -> {-count, -entry_number(entry.id)} end)
    |> Enum.take(max(limit, 0))
    |> Enum.map(fn {entry, _count} -> entry end)
  end

  defp distill_candidate?(entry) do
    entry.status == :active and entry.type not in @non_distillable_types
  end

  defp distill_text(:extractive, sources, version, _opts), do: extractive_text(sources, version)

  defp distill_text("extractive", sources, version, opts),
    do: distill_text(:extractive, sources, version, opts)

  defp distill_text(:llm, sources, version, opts) do
    messages = [
      %{
        role: "system",
        content: "TRACEFIELD_DISTILL\n以下のチームの判断群から、チームの判断方針を3〜5箇条で蒸留せよ。日本語。"
      },
      %{
        role: "user",
        content: format_distill_sources(sources)
      }
    ]

    llm_opts =
      opts
      |> Keyword.take([:adapter, :model, :temperature, :seed, :cli])
      |> Keyword.put_new(:adapter, Tracefield.LLM.Mock)

    case Tracefield.LLM.complete(messages, llm_opts) do
      {:ok, text} ->
        text = String.trim(to_string(text))
        if text == "", do: extractive_text(sources, version), else: text

      {:error, _reason} ->
        extractive_text(sources, version)
    end
  end

  defp distill_text("llm", sources, version, opts), do: distill_text(:llm, sources, version, opts)

  defp distill_text(_mode, sources, version, opts),
    do: distill_text(:extractive, sources, version, opts)

  defp extractive_text(sources, version) do
    bullets =
      sources
      |> Enum.map_join("\n", fn entry -> "- #{truncate(entry.text, 120)}" end)

    "house view v#{version}:\n#{bullets}"
  end

  defp format_distill_sources(sources) do
    sources
    |> Enum.map_join("\n", fn entry -> "ENTRY #{entry.id} text=#{entry.text}" end)
  end

  defp truncate(text, limit) do
    text = to_string(text)
    if String.length(text) > limit, do: String.slice(text, 0, limit), else: text
  end

  defp predecessor_citation(nil), do: []
  defp predecessor_citation(entry), do: [entry.id]

  defp latest_house_view(ref, status) do
    ref
    |> Reference.all()
    |> Enum.filter(&(&1.type == :house_view))
    |> filter_house_view_status(status)
    |> Enum.sort_by(fn entry -> {-house_view_version(entry), -entry_number(entry.id)} end)
    |> List.first()
  end

  defp filter_house_view_status(entries, :active),
    do: Enum.filter(entries, &(&1.status == :active))

  defp filter_house_view_status(entries, :any), do: entries

  defp house_view_version(nil), do: 0

  defp house_view_version(entry) do
    entry.meta
    |> Map.get(:house_view_version, Map.get(entry.meta, "house_view_version", 0))
    |> normalize_version()
  end

  defp normalize_version(version) when is_integer(version), do: version

  defp normalize_version(version) when is_binary(version) do
    case Integer.parse(version) do
      {value, ""} -> value
      _other -> 0
    end
  end

  defp normalize_version(_version), do: 0

  defp entries(list) when is_list(list), do: list
  defp entries(ref), do: Reference.all(ref)

  defp candidate?(entry) do
    entry.status == :active and entry.type not in @non_distillable_types
  end

  defp entry_number("e" <> number) do
    case Integer.parse(number) do
      {value, ""} -> value
      _other -> 0
    end
  end

  defp entry_number(_id), do: 0

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
