defmodule Tracefield.Synthesis do
  @moduledoc """
  Governable best-of-N synthesis serving layer.

  Reads layer-0 entries, runs N independent synthesizer samples (Fusion-style
  ensemble; H5b — pooling averages out the single-call coin-flip variance H5
  exposed), pools their cited cross-domain findings, drops citations that do not
  ground, and absorbs the surviving findings into the store as a higher layer
  that CITES layer-0 (so retraction closure reaches them; H6 — governable
  synthesis).

  Grounding here is PRODUCTION grounding via `Tracefield.Reference.verify` (an
  LLM judges whether each cited entry actually grounds the finding), NOT the
  experiment-only planted-keyword gate used in `mix tracefield.hetero`
  (`--multilayer`), which depends on ground-truth interaction keywords that do
  not exist outside the controlled scenarios. The gate is applied BEFORE absorb,
  so the store never persists ungrounded citations (keeps retraction precise).
  """

  alias Tracefield.Reference

  @default_synth_n 3

  @doc """
  Run best-of-N governable synthesis over `layer0_entries` already present in
  `reference`.

  Options:
    * `:synth_n` — ensemble size (default #{@default_synth_n})
    * `:synth_model` — cursor-agent model slug (required unless `:synth_complete`)
    * `:synth_complete` — `fun(prompt :: String.t())` returning `{:ok, content}`
      (dependency-injection seam for deterministic tests; defaults to a
      cursor-agent CLI call with `:synth_model`)
    * `:verify_adapter` / `:verify_model` — grounding judge (default ollama/mock)
    * `:author` — store author tag for synth entries (default `"SYNTH"`)

  Returns `%{findings: [...], synth_entry_ids: [...], dropped_citations: [...],
  sample_count: n}` where each finding is `%{id, text, citations, verified}`.
  """
  @spec run(GenServer.server(), [map()], keyword()) :: map()
  def run(reference, layer0_entries, opts \\ []) do
    layer0 = Enum.reject(layer0_entries, &(value(&1, :type) == :chunk))
    id_set = MapSet.new(Enum.map(layer0, &value(&1, :id)))
    n = max(Keyword.get(opts, :synth_n, @default_synth_n), 1)

    raw =
      1..n
      |> Enum.flat_map(fn _i -> synth_sample(layer0, id_set, opts) end)
      |> Enum.reject(&(&1.text == "" or &1.citations == []))
      |> Enum.uniq_by(& &1.text)
      |> Enum.with_index(1)
      |> Enum.map(fn {finding, i} -> Map.put(finding, :id, "synth-tmp-#{i}") end)

    # Production grounding gate, BEFORE absorb. verify keys by {citing_id,
    # cited_id}; cited entries are looked up in the store (layer-0 is present),
    # so the temp-id citing maps need not be persisted yet.
    verdicts = Reference.verify(reference, raw, verify_opts(opts))
    {gated, dropped} = apply_grounding(raw, verdicts)

    survivors =
      gated
      |> Enum.reject(&(&1.citations == []))
      |> Enum.map(&Map.take(&1, [:type, :text, :citations]))

    synth_entries = Reference.absorb(reference, survivors, Keyword.get(opts, :author, "SYNTH"))

    findings =
      Enum.map(synth_entries, fn e ->
        %{id: e.id, text: e.text, citations: e.citations, verified: true}
      end)

    %{
      findings: findings,
      synth_entry_ids: Enum.map(synth_entries, & &1.id),
      dropped_citations: dropped,
      sample_count: n
    }
  end

  # --- ensemble sampling ---

  defp synth_sample(layer0, id_set, opts) do
    prompt = synth_prompt(layer0)

    case complete(prompt, opts) do
      {:ok, content} -> parse_cited(content, id_set)
      {:error, _reason} -> []
    end
  end

  defp complete(prompt, opts) do
    case Keyword.get(opts, :synth_complete) do
      fun when is_function(fun, 1) ->
        fun.(prompt)

      _ ->
        synth_model = Keyword.fetch!(opts, :synth_model)

        Tracefield.LLM.complete([%{role: "user", content: prompt}],
          adapter: Tracefield.LLM.CLI,
          cli: {"cursor-agent", ["-p", "--output-format", "text", "--model", synth_model]},
          timeout: 300_000
        )
    end
  end

  defp synth_prompt(layer0) do
    """
    あなたは半溶解チームの統合器(synthesizer)である。以下は各員が外部化した懸念・事実
    （各行 [id] 付き）。領域をまたぐ矛盾・相互作用・依存をすべて見つけ、各々について
    それを構成する事実を統合した1つの belief を簡潔に書き、その矛盾/相互作用を構成した
    entry の [id] を citations に必ず列挙せよ。引用は実際に依拠した entry だけに限れ。
    Return only JSON {"entries":[{"type":"belief","text":"...","citations":["e3","e7"]}]}.

    ENTRIES:
    #{layer0 |> Enum.map_join("\n", fn e -> "[#{value(e, :id)}] #{value(e, :text)}" end)}
    """
    |> String.trim()
  end

  defp parse_cited(content, id_set) do
    case decode_object(content) do
      {:ok, %{} = decoded} ->
        decoded
        |> Map.get("entries", [])
        |> List.wrap()
        |> Enum.filter(&is_map/1)
        |> Enum.map(fn e ->
          %{
            type: :belief,
            text: to_string(Map.get(e, "text", "")),
            citations:
              e
              |> Map.get("citations", [])
              |> List.wrap()
              |> Enum.map(&to_string/1)
              |> Enum.filter(&MapSet.member?(id_set, &1))
              |> Enum.uniq()
          }
        end)

      _ ->
        []
    end
  end

  defp decode_object(content) do
    case Jason.decode(content) do
      {:ok, obj} ->
        {:ok, obj}

      {:error, _} ->
        with {s, _} <- :binary.match(content, "{"),
             {r, _} <- content |> String.reverse() |> :binary.match("}"),
             e = byte_size(content) - r - 1,
             true <- e >= s do
          Jason.decode(binary_part(content, s, e - s + 1))
        else
          _ -> {:error, :no_json}
        end
    end
  end

  # --- grounding gate ---

  defp apply_grounding(raw, verdicts) do
    Enum.reduce(raw, {[], []}, fn finding, {kept, dropped} ->
      {good, bad} =
        Enum.split_with(finding.citations, fn cid ->
          Map.get(verdicts, {finding.id, cid}, false)
        end)

      kept = kept ++ [%{finding | citations: good}]
      dropped = dropped ++ Enum.map(bad, &%{finding_text: finding.text, cited_id: &1})
      {kept, dropped}
    end)
  end

  defp verify_opts(opts) do
    [
      judge_adapter: Keyword.get(opts, :verify_adapter, Tracefield.LLM.Mock),
      judge_model: Keyword.get(opts, :verify_model, "mock")
    ]
  end

  defp value(entry, key), do: Map.get(entry, key, Map.get(entry, to_string(key)))
end
