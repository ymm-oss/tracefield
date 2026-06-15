defmodule Mix.Tasks.Tracefield.Consult do
  @moduledoc """
  Consult the semi-soluble team and return a governed synthesis.

  Runs the multi-agent deliberation over a scenario, then (by default) a
  best-of-N synthesizer pass (`Tracefield.Synthesis`) that connects cross-domain
  findings and returns them WITH provenance (citations to layer-0 entries,
  retraction-tracked). This is the serving counterpart to the `tracefield.hetero`
  research harness — the synthesis layer is ON by default here (that is the
  point: performance), whereas the harness keeps it opt-in for clean A/B.

      mix tracefield.consult --scenario-dir scenarios/enterprise-hi
      mix tracefield.consult --scenario-dir scenarios/enterprise-hi --no-synth
      mix tracefield.consult --scenario-dir scenarios/enterprise-hi --synth-n 5 --synth-model claude-opus-4-8-medium
      mix tracefield.consult --scenario-dir scenarios/fsl-brushup --novelty --novelty-doc ../fsl/CHANGELOG.md

  best-of-N synth calls a strong model N times (cost/latency scales with N).

  `--novelty` (with `--novelty-doc <path>`) adds the novelty gate: after the
  grounding gate, each finding is judged against the ground-truth doc and
  findings already covered by it are tagged `[SHIPPED]`. This stops the synthesis
  layer from confidently re-proposing already-done work (the grounding gate only
  checks that citations support a claim, not that the claim is still open).

  `--dedupe` (optional `--dedupe-threshold`, default 0.85) clusters
  near-duplicate findings by embedding cosine and keeps one representative per
  cluster (best-of-N pools paraphrases of the same idea). Merged findings show
  `(×N merged)` and union their citations; all entries stay governable.
  """
  use Mix.Task

  alias Tracefield.{Agent, Dissolution, Reference, Scenario, Synthesis}

  @shortdoc "Consult the team; return a governed best-of-N synthesis"

  @default_model "gemma4:12b-it-qat"
  @default_synth_model "claude-opus-4-8-medium"
  @default_synth_n 3
  @default_rounds 2

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          scenario_dir: :string,
          rounds: :integer,
          synth: :boolean,
          synth_model: :string,
          synth_n: :integer,
          novelty: :boolean,
          novelty_doc: :string,
          dedupe: :boolean,
          dedupe_threshold: :float,
          adapter: :string,
          model: :string
        ]
      )

    adapter = adapter_module(Keyword.get(opts, :adapter, "ollama"))

    result =
      run_consult(
        scenario_dir: Keyword.fetch!(opts, :scenario_dir),
        adapter: adapter,
        embed_adapter: embed_adapter(adapter),
        model: Keyword.get(opts, :model, @default_model),
        rounds: Keyword.get(opts, :rounds, @default_rounds),
        synth: Keyword.get(opts, :synth, true),
        synth_model: Keyword.get(opts, :synth_model, @default_synth_model),
        synth_n: Keyword.get(opts, :synth_n, @default_synth_n),
        novelty: Keyword.get(opts, :novelty, false),
        novelty_doc: Keyword.get(opts, :novelty_doc),
        dedupe: Keyword.get(opts, :dedupe, false),
        dedupe_threshold: Keyword.get(opts, :dedupe_threshold)
      )

    print(result)
    result
  end

  @doc """
  Core consult flow (callable directly for tests). See `run/1` for CLI options.

  Required opts: `:scenario_dir`. Optional: `:adapter`, `:embed_adapter`,
  `:model`, `:rounds`, `:synth` (bool), `:synth_model`, `:synth_n`,
  `:synth_complete`, `:verify_adapter`, `:verify_model`.
  """
  def run_consult(opts) do
    scenario = Scenario.load!(Keyword.fetch!(opts, :scenario_dir))
    private_docs = load_private_docs(Path.join(Keyword.fetch!(opts, :scenario_dir), "private"))
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Ollama)
    embed_adapter = Keyword.get(opts, :embed_adapter, embed_adapter(adapter))
    model = Keyword.get(opts, :model, @default_model)
    rounds = Keyword.get(opts, :rounds, @default_rounds)

    {:ok, reference} =
      Reference.start_link(
        embed_adapter: embed_adapter,
        embed_model: "nomic-embed-text",
        entries: [%{type: :chunk, author: "TASK", text: scenario.task, meta: %{domain: "task"}}]
      )

    agents =
      Dissolution.default_agents()
      |> Enum.with_index()
      |> Enum.map(fn {agent, index} ->
        Agent.new(agent.id, agent.domain, agent.desc,
          anchor: scenario.task,
          private_doc: Map.fetch!(private_docs, agent.id),
          adapter: adapter,
          model: model,
          serve_policy: :diverse,
          aware: true,
          seed: 2000 + index
        )
      end)

    {_agents, absorbed} =
      Enum.reduce(1..rounds, {agents, []}, fn round, {agents, absorbed} ->
        {agents, round_absorbed} =
          Enum.reduce(agents, {[], []}, fn agent, {updated, acc} ->
            {agent, entries, _log} = Agent.run_turn(agent, reference, round)
            {updated ++ [agent], acc ++ entries}
          end)

        {agents, absorbed ++ round_absorbed}
      end)

    layer0 = Enum.reject(absorbed, &(&1.type == :chunk))

    synthesis =
      if Keyword.get(opts, :synth, true) do
        log_cost(opts)
        Synthesis.run(reference, layer0, synth_opts(opts))
      end

    %{
      task: scenario.task,
      deliberation: Enum.map(layer0, &%{id: &1.id, author: &1.author, text: &1.text}),
      synthesis: synthesis,
      layer0_index: Map.new(layer0, &{&1.id, &1.text})
    }
  end

  defp synth_opts(opts) do
    synth_model = Keyword.get(opts, :synth_model, @default_synth_model)

    # Grounding verify needs a STRONG judge: local gemma is unreliable here (it
    # keys verify JSON by citing_id, not the expected index → parse miss → all
    # citations dropped; bigger gemma keys right but misjudges obvious grounding).
    # Default the grounding judge to the same cursor-agent strong model as synth.
    [
      synth_n: Keyword.get(opts, :synth_n, @default_synth_n),
      synth_model: synth_model,
      verify_adapter: Keyword.get(opts, :verify_adapter, Tracefield.LLM.CLI),
      verify_model: Keyword.get(opts, :verify_model, synth_model),
      verify_cli:
        Keyword.get(
          opts,
          :verify_cli,
          {"cursor-agent", ["-p", "--output-format", "text", "--model", synth_model]}
        )
    ]
    |> maybe_put(:synth_complete, Keyword.get(opts, :synth_complete))
    |> Keyword.merge(novelty_opts(opts, synth_model))
    |> Keyword.put(:dedupe, Keyword.get(opts, :dedupe, false))
    |> maybe_put(:dedupe_threshold, Keyword.get(opts, :dedupe_threshold))
  end

  # Novelty gate (opt-in): judge each grounded finding against a ground-truth
  # corpus so the synthesis layer does not re-propose already-shipped work. Uses
  # the same strong cursor-agent model as synth/verify for the judge.
  defp novelty_opts(opts, synth_model) do
    if Keyword.get(opts, :novelty, false) do
      ground_truth =
        case Keyword.get(opts, :ground_truth) do
          gt when is_binary(gt) -> gt
          _ -> read_novelty_doc(Keyword.get(opts, :novelty_doc))
        end

      base = [novelty_check: true, ground_truth: ground_truth]

      base
      |> maybe_put(:novelty_complete, Keyword.get(opts, :novelty_complete))
      |> then(fn kw ->
        if Keyword.has_key?(kw, :novelty_complete) do
          kw
        else
          kw
          |> Keyword.put(
            :novelty_adapter,
            Keyword.get(opts, :novelty_adapter, Tracefield.LLM.CLI)
          )
          |> Keyword.put(:novelty_model, Keyword.get(opts, :novelty_model, synth_model))
          |> Keyword.put(
            :novelty_cli,
            Keyword.get(
              opts,
              :novelty_cli,
              {"cursor-agent", ["-p", "--output-format", "text", "--model", synth_model]}
            )
          )
        end
      end)
    else
      []
    end
  end

  defp read_novelty_doc(nil), do: ""

  defp read_novelty_doc(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> Mix.raise("--novelty-doc not readable: #{path}")
    end
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)

  defp log_cost(opts) do
    if Keyword.get(opts, :synth_complete) == nil do
      n = Keyword.get(opts, :synth_n, @default_synth_n)
      model = Keyword.get(opts, :synth_model, @default_synth_model)
      Mix.shell().info("[synth] best-of-#{n} #{model} synthesis = #{n} strong-model calls")
    end
  end

  defp print(result) do
    Mix.shell().info("Tracefield Consult")
    Mix.shell().info("deliberation entries: #{length(result.deliberation)}")

    case result.synthesis do
      nil ->
        Mix.shell().info("(synth disabled — deliberation only)")

      synth ->
        Mix.shell().info(
          "synth findings: #{length(synth.findings)} (samples=#{synth.sample_count})"
        )

        case Map.get(synth, :dedupe_clusters) do
          nil -> :ok
          k -> Mix.shell().info("dedupe: #{synth.dedupe_input} findings → #{k} clusters")
        end

        if Map.get(synth, :novelty_checked) do
          Mix.shell().info(
            "novelty: #{length(synth.novel_findings)} novel, #{length(synth.shipped_findings)} already-shipped"
          )

          case Map.get(synth, :novelty_error) do
            nil ->
              :ok

            reason ->
              Mix.shell().info(
                "  ⚠ novelty judge failed (#{inspect(reason)}) — all findings defaulted to novel"
              )
          end

          case Map.get(synth, :novelty_omitted, []) do
            [] ->
              :ok

            ids ->
              Mix.shell().info(
                "  ⚠ judge omitted #{length(ids)} finding(s) — defaulted to novel: #{inspect(ids)}"
              )
          end
        end

        Enum.each(synth.findings, fn f ->
          tag =
            case Map.get(f, :novelty) do
              %{shipped: true} -> " [SHIPPED]"
              _ -> ""
            end

          cluster =
            case Map.get(f, :cluster_size) do
              s when is_integer(s) and s > 1 -> " (×#{s} merged)"
              _ -> ""
            end

          Mix.shell().info("- [#{f.id}]#{tag}#{cluster} cites=#{inspect(f.citations)}")
          Mix.shell().info("  #{f.text}")
        end)

        if synth.dropped_citations != [] do
          Mix.shell().info("dropped (ungrounded) citations: #{length(synth.dropped_citations)}")
        end
    end

    Mix.shell().info(Jason.encode!(to_json(result)))
  end

  defp to_json(result) do
    %{
      task: result.task,
      deliberation: result.deliberation,
      synthesis:
        result.synthesis &&
          %{
            findings: result.synthesis.findings,
            dropped_citations: result.synthesis.dropped_citations,
            sample_count: result.synthesis.sample_count,
            novelty_checked: Map.get(result.synthesis, :novelty_checked, false),
            novel_findings: Map.get(result.synthesis, :novel_findings, []),
            shipped_findings: Map.get(result.synthesis, :shipped_findings, []),
            novelty_error: Map.get(result.synthesis, :novelty_error),
            novelty_omitted: Map.get(result.synthesis, :novelty_omitted, []),
            dedupe_input: Map.get(result.synthesis, :dedupe_input),
            dedupe_clusters: Map.get(result.synthesis, :dedupe_clusters)
          },
      layer0_index: result.layer0_index
    }
  end

  defp load_private_docs(dir) do
    %{
      "SEC" => File.read!(Path.join(dir, "sec.md")),
      "BIZ" => File.read!(Path.join(dir, "biz.md")),
      "UX" => File.read!(Path.join(dir, "ux.md"))
    }
  end

  defp adapter_module("ollama"), do: Tracefield.LLM.Ollama
  defp adapter_module("openrouter"), do: Tracefield.LLM.OpenRouter
  defp adapter_module("cli"), do: Tracefield.LLM.CLI
  defp adapter_module("mock"), do: Tracefield.LLM.Mock
  defp adapter_module(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp embed_adapter(Tracefield.LLM.Mock), do: Tracefield.Embed.Mock
  defp embed_adapter(_adapter), do: Tracefield.Embed.Ollama
end
