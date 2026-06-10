defmodule Mix.Tasks.Tracefield.Doseresponse do
  @moduledoc "Run the Tracefield shared-state dose-response experiment."
  use Mix.Task

  alias Tracefield.{Dissolution, GroundTruth, Metrics, Scenario}

  @shortdoc "Run Tracefield state-axis dose-response experiment"

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

    runs =
      for k <- ks, index <- 0..(seeds - 1) do
        seed = 2_000 + index

        run_one(scenario,
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
    retract_smoke = retract_smoke(runs)
    path = persist(%{runs: runs, summary: summary, retract_smoke: retract_smoke}, adapter_name)

    %{
      runs: runs,
      summary: summary,
      trend: monotonic_trend(summary, ks),
      retract_smoke: retract_smoke,
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
          k_s: k_s,
          adapter: adapter,
          model: model,
          temperature: temperature,
          seed: seed + index
        )
      end)

    {agents, absorbed} =
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

    %{
      k: k_s,
      seed: seed,
      icc: measure.icc,
      coverage: measure.coverage,
      diversity: measure.diversity,
      collapse_rate: measure.collapse_rate,
      concerns_by_agent: concerns_by_agent,
      absorbed_entries: plain_entries(absorbed),
      reference: reference,
      agents: agents
    }
  end

  defp run_round(agents, reference, round) do
    agents
    |> Enum.reduce({[], []}, fn agent, {updated_agents, absorbed} ->
      {agent, entries, _perception} = Tracefield.Agent.run_turn(agent, reference, round)
      {updated_agents ++ [agent], absorbed ++ entries}
    end)
  end

  defp concerns_by_agent(entries) do
    entries
    |> Enum.reject(&(&1.type == :chunk))
    |> Enum.group_by(& &1.author, & &1.text)
  end

  defp retract_smoke(runs) do
    run = Enum.find(runs, &(&1.k == 2))
    first = run && List.first(run.absorbed_entries)

    if run && first do
      closure = Tracefield.Reference.retract(run.reference, first.id)

      %{
        k: 2,
        seed: run.seed,
        retracted: first.id,
        closure_ids: Enum.map(closure, & &1.id),
        ok: closure != []
      }
    else
      %{k: 2, seed: nil, retracted: nil, closure_ids: [], ok: false}
    end
  end

  defp summary_by_k(runs) do
    runs
    |> Enum.group_by(& &1.k)
    |> Map.new(fn {k, rows} ->
      {k,
       %{
         icc: Metrics.summary(Enum.map(rows, &(&1.icc * 1.0))),
         coverage: Metrics.summary(Enum.map(rows, &(&1.coverage * 1.0))),
         diversity: Metrics.summary(Enum.map(rows, & &1.diversity)),
         collapse_rate: Metrics.summary(Enum.map(rows, & &1.collapse_rate))
       }}
    end)
  end

  defp monotonic_trend(summary, ks) do
    values = Enum.map(ks, &(get_in(summary, [&1, :icc, :mean]) || 0.0))

    cond do
      values == Enum.sort(values) -> :nondecreasing
      values == Enum.sort(values, :desc) -> :nonincreasing
      true -> :mixed
    end
  end

  defp persist(result, adapter_name) do
    File.mkdir_p!("runs")

    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace("Z", "")

    path = "runs/#{timestamp}-doseresponse-#{adapter_name}.json"

    serializable =
      result
      |> Map.update!(:runs, fn runs -> Enum.map(runs, &Map.drop(&1, [:reference, :agents])) end)
      |> GroundTruth.to_plain()

    File.write!(path, Jason.encode!(serializable, pretty: true))
    path
  end

  defp print_result(result) do
    Mix.shell().info("Tracefield DoseResponse")
    Mix.shell().info("runs:")
    Mix.shell().info("k seed icc coverage diversity collapse_rate")

    Enum.each(result.runs, fn row ->
      Mix.shell().info(
        "#{row.k} #{row.seed} #{row.icc} #{row.coverage} #{fmt(row.diversity)} #{fmt(row.collapse_rate)}"
      )
    end)

    Mix.shell().info("")
    Mix.shell().info("aggregate mean±sd:")
    Mix.shell().info("k icc coverage diversity collapse_rate")

    result.summary
    |> Enum.sort_by(fn {k, _row} -> k end)
    |> Enum.each(fn {k, row} ->
      Mix.shell().info(
        "#{k} #{mean_sd(row.icc)} #{mean_sd(row.coverage)} #{mean_sd(row.diversity)} #{mean_sd(row.collapse_rate)}"
      )
    end)

    Mix.shell().info("")
    Mix.shell().info("trend: ICC vs k is #{result.trend}")

    Mix.shell().info(
      "retract smoke: retract #{result.retract_smoke.retracted} closure=#{inspect(result.retract_smoke.closure_ids)} ok=#{result.retract_smoke.ok}"
    )

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
