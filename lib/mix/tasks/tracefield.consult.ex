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

  best-of-N synth calls a strong model N times (cost/latency scales with N).
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
        synth_n: Keyword.get(opts, :synth_n, @default_synth_n)
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

        Enum.each(synth.findings, fn f ->
          Mix.shell().info("- [#{f.id}] cites=#{inspect(f.citations)}")
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
            sample_count: result.synthesis.sample_count
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
