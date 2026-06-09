defmodule Mix.Tasks.Tracefield.Phase1 do
  @moduledoc "Run Phase 1 counterfactual characterization."
  use Mix.Task

  alias Tracefield.{GroundTruth, Scenario}

  @shortdoc "Run Tracefield Phase 1"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          adapter: :string,
          n: :integer,
          temperature: :float,
          model: :string,
          seed_base: :integer,
          n_agents: :integer,
          rounds: :integer
        ],
        aliases: [a: :adapter, n: :n, t: :temperature, m: :model]
      )

    adapter = adapter_module(Keyword.get(opts, :adapter, "mock"))
    adapter_name = Keyword.get(opts, :adapter, "mock")
    n = Keyword.get(opts, :n, 8)
    temperature = Keyword.get(opts, :temperature, 0.2)
    seed_base = Keyword.get(opts, :seed_base, 1_000)

    model =
      Keyword.get(
        opts,
        :model,
        if(adapter == Tracefield.LLM.Mock, do: "mock", else: "gemma4:12b")
      )

    scenario = Scenario.load!("scenarios/enterprise-assistant")

    case GroundTruth.run(scenario,
           adapter: adapter,
           n: n,
           temperature: temperature,
           model: model,
           seed_base: seed_base,
           n_agents: Keyword.get(opts, :n_agents, 4),
           rounds: Keyword.get(opts, :rounds, 3),
           persist_runs: true
         ) do
      {:ok, result} ->
        path = persist_summary(result, adapter_name)
        print_result(result, path)

      {:error, reason} ->
        Mix.raise("tracefield.phase1 failed: #{inspect(reason)}")
    end
  end

  defp adapter_module("mock"), do: Tracefield.LLM.Mock
  defp adapter_module("ollama"), do: Tracefield.LLM.Ollama
  defp adapter_module(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp persist_summary(result, adapter_name) do
    File.mkdir_p!("runs")

    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace("Z", "")

    path = "runs/#{timestamp}-phase1-#{adapter_name}.json"
    File.write!(path, Jason.encode!(GroundTruth.to_plain(result), pretty: true))
    path
  end

  defp print_result(result, path) do
    Mix.shell().info("Tracefield Phase 1 - #{result.adapter}")
    Mix.shell().info("model: #{result.model}")
    Mix.shell().info("n per state: #{result.n}")
    Mix.shell().info("temperature: #{fmt(result.temperature)}")
    Mix.shell().info("seed_base: #{result.seed_base}")
    Mix.shell().info("within: #{summary(result.within_summary)}")
    Mix.shell().info("between: #{summary(result.between_summary)}")
    Mix.shell().info("AUC: #{fmt(result.auc)}")
    Mix.shell().info("Cliff's delta: #{fmt(result.cliffs_delta)}")
    Mix.shell().info("ground truth size: #{MapSet.size(result.ground_truth_set)}")
    Mix.shell().info("ground truth set: #{inspect(MapSet.to_list(result.ground_truth_set))}")

    Mix.shell().info(
      "system claimed affected size: #{MapSet.size(result.system_claimed_affected)}"
    )

    Mix.shell().info("proxy recall: #{fmt(result.proxy.recall)}")
    Mix.shell().info("proxy precision: #{fmt(result.proxy.precision)}")
    Mix.shell().info("proxy f1: #{fmt(result.proxy.f1)}")
    Mix.shell().info("saved: #{path}")
  end

  defp summary(summary) do
    "n=#{summary.n}, mean=#{fmt(summary.mean)}, sd=#{fmt(summary.sd)}, median=#{fmt(summary.median)}"
  end

  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)
end
