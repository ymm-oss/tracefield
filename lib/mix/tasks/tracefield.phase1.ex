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
          rounds: :integer,
          condition: :string,
          contaminant: :string,
          with_decoys: :boolean
        ],
        aliases: [a: :adapter, n: :n, t: :temperature, m: :model]
      )

    adapter = adapter_module(Keyword.get(opts, :adapter, "mock"))
    adapter_name = Keyword.get(opts, :adapter, "mock")
    n = Keyword.get(opts, :n, 8)
    temperature = Keyword.get(opts, :temperature, 0.2)
    seed_base = Keyword.get(opts, :seed_base, 1_000)
    condition = condition_value(Keyword.get(opts, :condition, "c4"))
    contaminant = contaminant_value(Keyword.get(opts, :contaminant, "a"))

    model =
      Keyword.get(
        opts,
        :model,
        if(adapter == Tracefield.LLM.Mock, do: "mock", else: "gemma4:12b")
      )

    scenario = Scenario.load!("scenarios/enterprise-assistant")
    decoys = if Keyword.get(opts, :with_decoys, false), do: scenario.decoys, else: []

    case GroundTruth.run(scenario,
           adapter: adapter,
           n: n,
           temperature: temperature,
           model: model,
           seed_base: seed_base,
           n_agents: Keyword.get(opts, :n_agents, 4),
           rounds: Keyword.get(opts, :rounds, 3),
           condition: condition,
           contaminant: contaminant,
           decoys: decoys,
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

  defp condition_value("c4"), do: :c4
  defp condition_value("c1"), do: :c1
  defp condition_value(other), do: Mix.raise("unknown condition #{inspect(other)}")

  defp contaminant_value(value) when value in ["a", "b", "c"], do: value

  defp contaminant_value(value) when is_binary(value) do
    value
    |> String.downcase()
    |> contaminant_value()
  end

  defp contaminant_value(other), do: Mix.raise("unknown contaminant #{inspect(other)}")

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
    Mix.shell().info("condition: #{result.condition}")
    Mix.shell().info("model: #{result.model}")
    Mix.shell().info("n per state: #{result.n}")
    Mix.shell().info("temperature: #{fmt(result.temperature)}")
    Mix.shell().info("seed_base: #{result.seed_base}")
    Mix.shell().info("contaminant: #{result.contaminant}")
    Mix.shell().info("decoys: #{inspect(result.decoys)}")
    Mix.shell().info("within: #{summary(result.within_summary)}")
    Mix.shell().info("between: #{summary(result.between_summary)}")
    Mix.shell().info("AUC: #{fmt(result.auc)}")
    Mix.shell().info("Cliff's delta: #{fmt(result.cliffs_delta)}")
    Mix.shell().info("affected size: #{MapSet.size(result.affected_set)}")
    Mix.shell().info("affected set: #{inspect(MapSet.to_list(result.affected_set))}")

    Mix.shell().info(
      "system claimed affected size: #{MapSet.size(result.system_claimed_affected)}"
    )

    Mix.shell().info("proxy recall: #{fmt(result.proxy.recall)}")
    Mix.shell().info("proxy precision: #{fmt(result.proxy.precision)}")
    Mix.shell().info("proxy f1: #{fmt(result.proxy.f1)}")
    Mix.shell().info("c5 affected points: #{inspect(sorted(result.c5_affected_points))}")
    Mix.shell().info("c4 affected points: #{inspect(sorted(result.c4_affected_points))}")
    Mix.shell().info("c5 minus c4: #{inspect(sorted(result.c5_minus_c4))}")
    print_stance_table(result.stance_table)
    Mix.shell().info("saved: #{path}")
  end

  defp print_stance_table(stance_table) do
    Mix.shell().info("stance table:")

    stance_table
    |> Enum.sort_by(fn {topic, _row} -> topic end)
    |> Enum.each(fn {topic, row} ->
      Mix.shell().info(
        "  #{topic}: a_present=#{row.a_present} b_present=#{row.b_present} differs=#{row.differs} g1=#{inspect(row.g1)} g2=#{inspect(row.g2)}"
      )
    end)
  end

  defp summary(summary) do
    "n=#{summary.n}, mean=#{fmt(summary.mean)}, sd=#{fmt(summary.sd)}, median=#{fmt(summary.median)}"
  end

  defp sorted(set), do: set |> MapSet.to_list() |> Enum.sort()

  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)
end
