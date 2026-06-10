defmodule Mix.Tasks.Tracefield.Hetero do
  @moduledoc "Run the Tracefield heterogeneous private-document dose-response experiment."
  use Mix.Task

  alias Tracefield.{Discovery, Dissolution, GroundTruth, Metrics, Scenario}

  @shortdoc "Run Tracefield private-document heterogeneity experiment"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    result = run_experiment(opts)
    print_result(result)
  end

  def run_experiment(opts) do
    adapter_name = Keyword.get(opts, :adapter_name, Keyword.get(opts, :adapter, "mock"))

    adapter =
      if Keyword.has_key?(opts, :adapter),
        do: Keyword.fetch!(opts, :adapter),
        else: adapter_module(adapter_name)

    seeds = Keyword.get(opts, :seeds, 2)
    rounds = Keyword.get(opts, :rounds, 2)
    ks = Keyword.get(opts, :ks, [0, 2, 6])
    temperature = Keyword.get(opts, :temperature, 0.4)

    model =
      Keyword.get(
        opts,
        :model,
        if(adapter == Tracefield.LLM.Mock, do: "mock", else: "gemma4:12b")
      )

    judge_model = Keyword.get(opts, :judge_model, model)
    embed_model = Keyword.get(opts, :embed_model, "nomic-embed-text")

    scenario =
      Keyword.get_lazy(opts, :scenario, fn -> Scenario.load!("scenarios/enterprise-assistant") end)

    private_docs =
      Keyword.get_lazy(opts, :private_docs, fn ->
        load_private_docs("scenarios/enterprise-assistant/private")
      end)

    runs =
      for k <- ks, index <- 0..(seeds - 1) do
        seed = 2_000 + index

        run_one(scenario,
          private_docs: private_docs,
          k_s: k,
          seed: seed,
          rounds: rounds,
          adapter: adapter,
          model: model,
          judge_model: judge_model,
          embed_model: embed_model,
          temperature: temperature
        )
      end

    summary = summary_by_k(runs)
    path = persist(%{runs: runs, summary: summary}, adapter_name)

    %{
      runs: runs,
      summary: summary,
      discovery_trend: monotonic_trend(summary, ks, :discovery_count),
      diversity_trend: monotonic_trend(summary, ks, :diversity),
      path: path
    }
  end

  defp parse_args(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          adapter: :string,
          seeds: :integer,
          rounds: :integer,
          ks: :string,
          model: :string,
          judge_model: :string,
          embed_model: :string,
          temperature: :float
        ],
        aliases: [a: :adapter, m: :model, t: :temperature]
      )

    adapter_name = Keyword.get(opts, :adapter, "mock")

    [
      adapter_name: adapter_name,
      adapter: adapter_module(adapter_name),
      seeds: Keyword.get(opts, :seeds, 2),
      rounds: Keyword.get(opts, :rounds, 2),
      ks: parse_ks(Keyword.get(opts, :ks, "0,2,6")),
      model: Keyword.get(opts, :model),
      judge_model: Keyword.get(opts, :judge_model),
      embed_model: Keyword.get(opts, :embed_model, "nomic-embed-text"),
      temperature: Keyword.get(opts, :temperature, 0.4)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp run_one(scenario, opts) do
    k_s = Keyword.fetch!(opts, :k_s)
    seed = Keyword.fetch!(opts, :seed)
    rounds = Keyword.fetch!(opts, :rounds)
    adapter = Keyword.fetch!(opts, :adapter)
    model = Keyword.fetch!(opts, :model)
    temperature = Keyword.fetch!(opts, :temperature)
    private_docs = Keyword.fetch!(opts, :private_docs)

    {:ok, reference} =
      Tracefield.Reference.start_link(
        embed_adapter:
          if(adapter == Tracefield.LLM.Mock,
            do: Tracefield.Embed.Mock,
            else: Tracefield.Embed.Ollama
          ),
        embed_model: Keyword.fetch!(opts, :embed_model),
        entries: [
          %{
            type: :chunk,
            author: "TASK",
            text: scenario.task,
            meta: %{domain: "task"}
          }
        ]
      )

    agents =
      Dissolution.default_agents()
      |> Enum.with_index()
      |> Enum.map(fn {agent, index} ->
        Tracefield.Agent.new(agent.id, agent.domain, agent.desc,
          anchor: scenario.task,
          private_doc: Map.fetch!(private_docs, agent.id),
          k_s: k_s,
          adapter: adapter,
          model: model,
          temperature: temperature,
          seed: seed + index
        )
      end)

    {_agents, absorbed} =
      Enum.reduce(1..rounds, {agents, []}, fn round, {agents, absorbed} ->
        {agents, round_absorbed} = run_round(agents, reference, round)
        {agents, absorbed ++ round_absorbed}
      end)

    concerns_by_agent = concerns_by_agent(absorbed)

    measure =
      Dissolution.measure_concerns(concerns_by_agent,
        adapter: adapter,
        model: model,
        judge_model: Keyword.fetch!(opts, :judge_model),
        embed_model: Keyword.fetch!(opts, :embed_model),
        temperature: temperature,
        seed: seed
      )

    discovery =
      Discovery.score(absorbed,
        judge_adapter: adapter,
        judge_model: Keyword.fetch!(opts, :judge_model),
        temperature: temperature,
        seed: seed
      )

    %{
      k: k_s,
      seed: seed,
      discovery_count: discovery.count,
      discovery: discovery.per_interaction,
      icc: measure.icc,
      coverage: measure.coverage,
      diversity: measure.diversity,
      collapse_rate: measure.collapse_rate,
      concerns_by_agent: concerns_by_agent,
      absorbed_entries: plain_entries(absorbed),
      reference: reference
    }
  end

  defp run_round(agents, reference, round) do
    agents
    |> Enum.reduce({[], []}, fn agent, {updated_agents, absorbed} ->
      {agent, entries} = Tracefield.Agent.run_turn(agent, reference, round)
      {updated_agents ++ [agent], absorbed ++ entries}
    end)
  end

  defp concerns_by_agent(entries) do
    entries
    |> Enum.reject(&(&1.type == :chunk))
    |> Enum.group_by(& &1.author, & &1.text)
  end

  defp summary_by_k(runs) do
    runs
    |> Enum.group_by(& &1.k)
    |> Map.new(fn {k, rows} ->
      {k,
       %{
         discovery_count: Metrics.summary(Enum.map(rows, &(&1.discovery_count * 1.0))),
         icc: Metrics.summary(Enum.map(rows, &(&1.icc * 1.0))),
         coverage: Metrics.summary(Enum.map(rows, &(&1.coverage * 1.0))),
         diversity: Metrics.summary(Enum.map(rows, & &1.diversity)),
         collapse_rate: Metrics.summary(Enum.map(rows, & &1.collapse_rate))
       }}
    end)
  end

  defp monotonic_trend(summary, ks, metric) do
    values = Enum.map(ks, &(get_in(summary, [&1, metric, :mean]) || 0.0))

    cond do
      values == Enum.sort(values) -> :nondecreasing
      values == Enum.sort(values, :desc) -> :nonincreasing
      true -> :mixed
    end
  end

  defp load_private_docs(dir) do
    %{
      "SEC" => File.read!(Path.join(dir, "sec.md")),
      "BIZ" => File.read!(Path.join(dir, "biz.md")),
      "UX" => File.read!(Path.join(dir, "ux.md"))
    }
  end

  defp persist(result, adapter_name) do
    File.mkdir_p!("runs")

    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace("Z", "")

    path = "runs/#{timestamp}-hetero-#{adapter_name}.json"

    serializable =
      result
      |> Map.update!(:runs, fn runs -> Enum.map(runs, &Map.drop(&1, [:reference])) end)
      |> GroundTruth.to_plain()

    File.write!(path, Jason.encode!(serializable, pretty: true))
    path
  end

  defp print_result(result) do
    Mix.shell().info("Tracefield Hetero")
    Mix.shell().info("runs:")
    Mix.shell().info("k seed disc icc coverage diversity collapse")

    Enum.each(result.runs, fn row ->
      Mix.shell().info(
        "#{row.k} #{row.seed} #{row.discovery_count} #{row.icc} #{row.coverage} #{fmt(row.diversity)} #{fmt(row.collapse_rate)}"
      )
    end)

    Mix.shell().info("")
    Mix.shell().info("aggregate mean±sd:")
    Mix.shell().info("k disc icc coverage diversity collapse")

    result.summary
    |> Enum.sort_by(fn {k, _row} -> k end)
    |> Enum.each(fn {k, row} ->
      Mix.shell().info(
        "#{k} #{mean_sd(row.discovery_count)} #{mean_sd(row.icc)} #{mean_sd(row.coverage)} #{mean_sd(row.diversity)} #{mean_sd(row.collapse_rate)}"
      )
    end)

    Mix.shell().info("")
    Mix.shell().info("trend: discovery vs k is #{result.discovery_trend}")
    Mix.shell().info("trend: diversity vs k is #{result.diversity_trend}")
    Mix.shell().info("saved: #{result.path}")
  end

  defp plain_entries(entries) do
    Enum.map(entries, fn entry ->
      %{
        id: entry.id,
        type: entry.type,
        author: entry.author,
        version: entry.version,
        status: entry.status,
        text: entry.text,
        citations: entry.citations,
        meta: entry.meta
      }
    end)
  end

  defp adapter_module("mock"), do: Tracefield.LLM.Mock
  defp adapter_module("ollama"), do: Tracefield.LLM.Ollama
  defp adapter_module(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp parse_ks(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(fn item ->
      case Integer.parse(String.trim(item)) do
        {k, ""} when k >= 0 -> k
        _ -> Mix.raise("invalid k_s value #{inspect(item)}")
      end
    end)
  end

  defp mean_sd(summary), do: "#{fmt(summary.mean)}±#{fmt(summary.sd)}"
  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)
end
