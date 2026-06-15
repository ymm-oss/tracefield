defmodule Tracefield.Coverage do
  @moduledoc """
  Advisory coverage: detect reference chunks distant from all llm/cli actors.
  """

  alias Tracefield.Embed

  # 0.2 flags chunks with no meaningful actor overlap while tolerating paraphrase.
  @default_threshold 0.2
  @default_mobilization_threshold 0.5
  @default_k 1.0
  @min_relative_samples 3

  @type chunk :: %{
          required(:id) => String.t(),
          required(:file) => String.t(),
          required(:text) => String.t()
        }
  @type actor :: %{
          required(:id) => String.t(),
          required(:domain) => String.t(),
          required(:desc) => String.t(),
          required(:kind) => atom(),
          required(:private_doc) => String.t()
        }
  @type scored_chunk :: %{
          id: String.t(),
          file: String.t(),
          nearest_actor: String.t(),
          sim: float()
        }
  @type uncovered_chunk :: scored_chunk()
  @type detection_meta :: map()

  @spec uncovered([chunk()], [actor()], keyword()) :: [uncovered_chunk()]
  def uncovered(chunks, actors, opts) do
    analyze(chunks, actors, opts) |> elem(0)
  end

  @doc false
  @spec analyze([chunk()], [actor()], keyword()) :: {[uncovered_chunk()], detection_meta()}
  def analyze(chunks, actors, opts) do
    embed_adapter = Keyword.fetch!(opts, :embed_adapter)

    measurable_actors =
      actors
      |> Enum.filter(&(&1.kind in [:llm, :cli]))
      |> Enum.map(fn actor -> {actor.id, actor_profile(actor)} end)

    cond do
      measurable_actors == [] ->
        {[], %{mode: coverage_mode(opts)}}

      chunks == [] ->
        {[], %{mode: coverage_mode(opts)}}

      true ->
        chunks
        |> score_chunks(measurable_actors, embed_adapter)
        |> then(&detect_uncovered(&1, opts))
    end
  end

  @spec detect_uncovered([scored_chunk()], keyword()) :: {[uncovered_chunk()], detection_meta()}
  def detect_uncovered(scored_chunks, opts) do
    mode = coverage_mode(opts)

    case mode do
      :absolute ->
        threshold = Keyword.get(opts, :threshold, @default_threshold)

        uncovered =
          Enum.filter(scored_chunks, fn %{sim: sim} ->
            sim < threshold
          end)

        {uncovered, %{mode: :absolute, threshold: threshold}}

      :relative ->
        sims = Enum.map(scored_chunks, & &1.sim)
        n = length(sims)

        if n < @min_relative_samples do
          {[], %{mode: :relative, insufficient_samples: true, n: n}}
        else
          k = Keyword.get(opts, :coverage_k, @default_k)
          median = median(sims)
          mad = mad(sims)
          cutoff = median - k * mad

          uncovered =
            Enum.filter(scored_chunks, fn %{sim: sim} ->
              sim < cutoff
            end)

          {uncovered, %{mode: :relative, cutoff: cutoff, median: median, mad: mad, k: k}}
        end
    end
  end

  @doc false
  @spec detection_warning(detection_meta()) :: String.t() | nil
  def detection_warning(%{insufficient_samples: true, n: n}) do
    "⚠ coverage-relative: insufficient samples (N=#{n}), skipping relative detection"
  end

  def detection_warning(%{mode: :absolute, threshold: threshold}) do
    "⚠ coverage-threshold: #{threshold}"
  end

  def detection_warning(%{mode: :relative, cutoff: cutoff, median: median, mad: mad, k: k}) do
    "⚠ coverage-relative: cutoff=#{format_stat(cutoff)} (median=#{format_stat(median)} MAD=#{format_stat(mad)} k=#{format_stat(k)})"
  end

  @spec score_chunks([chunk()], [{String.t(), String.t()}], module()) :: [scored_chunk()]
  def score_chunks(chunks, measurable_actors, embed_adapter) do
    actor_profiles = Enum.map(measurable_actors, fn {_id, profile} -> profile end)
    chunk_texts = Enum.map(chunks, & &1.text)

    {:ok, embeddings} =
      Embed.embed(chunk_texts ++ actor_profiles,
        adapter: embed_adapter,
        model: "nomic-embed-text"
      )

    {chunk_embeddings, actor_embeddings} = Enum.split(embeddings, length(chunks))
    actor_ids = Enum.map(measurable_actors, fn {id, _profile} -> id end)

    chunks
    |> Enum.zip(chunk_embeddings)
    |> Enum.map(fn {chunk, chunk_embedding} ->
      {nearest_actor, max_sim} =
        actor_ids
        |> Enum.zip(actor_embeddings)
        |> Enum.map(fn {actor_id, actor_embedding} ->
          {actor_id, Embed.cosine(chunk_embedding, actor_embedding)}
        end)
        |> Enum.max_by(fn {_actor_id, sim} -> sim end, fn -> {"", 0.0} end)

      %{id: chunk.id, file: chunk.file, nearest_actor: nearest_actor, sim: max_sim}
    end)
  end

  defp coverage_mode(opts) do
    case Keyword.get(opts, :coverage_mode, :absolute) do
      :absolute -> :absolute
      :relative -> :relative
      other -> raise ArgumentError, "invalid coverage_mode #{inspect(other)}"
    end
  end

  defp median(values) when values == [], do: 0.0

  defp median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1 do
      Enum.at(sorted, mid)
    else
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end

  defp mad(values) do
    m = median(values)

    values
    |> Enum.map(fn value -> abs(value - m) end)
    |> median()
  end

  defp format_stat(value) do
    value
    |> Float.round(3)
    |> :erlang.float_to_binary(decimals: 3)
  end

  defp actor_profile(%{domain: domain, desc: desc, private_doc: private_doc}) do
    territory_text(domain, desc, private_doc)
  end

  @doc false
  @spec detect_unowned_entries([map()], [{String.t(), String.t()}], keyword()) :: [String.t()]
  def detect_unowned_entries(entries, territories, opts) when is_list(entries) do
    measurable_actors = territories

    cond do
      measurable_actors == [] ->
        []

      entries == [] ->
        []

      true ->
        embed_adapter = Keyword.fetch!(opts, :embed_adapter)
        coverage_k = Keyword.get(opts, :coverage_k, @default_k)

        chunks =
          Enum.map(entries, fn entry ->
            %{
              id: entry.id,
              file: Atom.to_string(entry.type),
              text: entry.text
            }
          end)

        detection_opts = [
          coverage_mode: :relative,
          coverage_k: coverage_k
        ]

        chunks
        |> score_chunks(measurable_actors, embed_adapter)
        |> then(&detect_uncovered(&1, detection_opts))
        |> elem(0)
        |> Enum.map(fn %{id: id, file: type, nearest_actor: actor, sim: sim} ->
          "⚠ 無人論点: #{id} (#{type}) — nearest: #{actor} (#{format_stat(sim)})"
        end)
    end
  end

  @doc false
  @spec detect_stale_questions([map()], non_neg_integer(), non_neg_integer()) ::
          {[String.t()], non_neg_integer()}
  def detect_stale_questions(entries, current_round, stale_rounds) do
    answered_ids = answered_question_ids(entries)

    Enum.reduce(entries, {[], 0}, fn entry, {warnings, skipped} ->
      cond do
        entry.type != :question or entry.status != :active ->
          {warnings, skipped}

        MapSet.member?(answered_ids, entry.id) ->
          {warnings, skipped}

        true ->
          case entry_round(entry) do
            nil ->
              {warnings, skipped + 1}

            round when current_round - round >= stale_rounds ->
              message = "⚠ 未回答の質問: #{entry.id}（r#{round}から放置）"
              {[message | warnings], skipped}

            _round ->
              {warnings, skipped}
          end
      end
    end)
    |> then(fn {warnings, skipped} -> {Enum.reverse(warnings), skipped} end)
  end

  defp answered_question_ids(entries) do
    entries
    |> Enum.filter(&(&1.type == :answer and &1.status == :active))
    |> Enum.flat_map(& &1.citations)
    |> MapSet.new()
  end

  defp entry_round(entry) do
    meta = entry.meta || %{}

    case Map.get(meta, :round, Map.get(meta, "round")) do
      nil -> nil
      round when is_integer(round) -> round
      round when is_binary(round) -> String.to_integer(round)
    end
  end

  @doc false
  def territory_text(domain, desc, private_doc) do
    [domain, desc, private_doc]
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> String.trim()
  end

  @spec mobilization_rate([map()], [map()], keyword()) :: %{
          rate: float(),
          details: [%{title: String.t(), score: float(), mobilized: boolean()}]
        }
  def mobilization_rate(entries, sections, opts) when is_list(entries) and is_list(sections) do
    threshold = Keyword.get(opts, :threshold, @default_mobilization_threshold)

    case sections do
      [] ->
        %{rate: 1.0, details: []}

      _ ->
        active_entries = Enum.filter(entries, &(Map.get(&1, :status, :active) == :active))

        if active_entries == [] do
          details =
            Enum.map(sections, fn section ->
              %{title: section_title(section), score: 0.0, mobilized: false}
            end)

          %{rate: 0.0, details: details}
        else
          embed_adapter = Keyword.fetch!(opts, :embed_adapter)
          section_texts = Enum.map(sections, &section_body/1)
          entry_texts = Enum.map(active_entries, & &1.text)

          {:ok, embeddings} =
            Embed.embed(section_texts ++ entry_texts,
              adapter: embed_adapter,
              model: "nomic-embed-text"
            )

          {section_embeddings, entry_embeddings} =
            Enum.split(embeddings, length(section_texts))

          details =
            sections
            |> Enum.zip(section_embeddings)
            |> Enum.map(fn {section, section_embedding} ->
              score =
                entry_embeddings
                |> Enum.map(&Embed.cosine(section_embedding, &1))
                |> Enum.max(fn -> 0.0 end)

              %{
                title: section_title(section),
                score: score,
                mobilized: score >= threshold
              }
            end)

          mobilized_count = Enum.count(details, & &1.mobilized)
          rate = mobilized_count / length(details)

          %{rate: rate, details: details}
        end
    end
  end

  @doc false
  @spec mobilization_warning(String.t(), %{rate: float(), details: list()}) :: String.t() | nil
  def mobilization_warning(actor_id, %{rate: rate, details: details}) do
    unmobilized = Enum.filter(details, &(!&1.mobilized))

    if unmobilized == [] do
      nil
    else
      sections_text =
        Enum.map_join(unmobilized, ", ", fn detail ->
          "#{detail.title}(score=#{format_stat(detail.score)})"
        end)

      rate_pct =
        rate
        |> Kernel.*(100)
        |> Float.round(1)
        |> :erlang.float_to_binary(decimals: 1)

      "⚠ 未動員領土: #{actor_id} #{rate_pct}%（未動員節: #{sections_text}）"
    end
  end

  defp section_title(%{title: title}), do: to_string(title)
  defp section_title(%{"title" => title}), do: to_string(title)

  defp section_body(%{title: title, body: body}) do
    body = to_string(body) |> String.trim()

    if body == "" do
      to_string(title)
    else
      "#{title}\n#{body}"
    end
  end

  defp section_body(%{"title" => title, "body" => body}) do
    section_body(%{title: title, body: body})
  end
end
