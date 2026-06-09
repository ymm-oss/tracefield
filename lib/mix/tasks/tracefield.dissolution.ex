defmodule Mix.Tasks.Tracefield.Dissolution do
  @moduledoc "Run the dissolution-depth experiment."
  use Mix.Task

  alias Tracefield.{Dissolution, GroundTruth, Metrics, Scenario}

  @shortdoc "Run Tracefield dissolution experiment"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          adapter: :string,
          seeds: :integer,
          rounds: :integer,
          regimes: :string,
          model: :string,
          temperature: :float
        ],
        aliases: [a: :adapter, m: :model, t: :temperature]
      )

    adapter_name = Keyword.get(opts, :adapter, "mock")
    adapter = adapter_module(adapter_name)
    seeds = Keyword.get(opts, :seeds, 3)
    rounds = Keyword.get(opts, :rounds, 2)
    regimes = regimes(Keyword.get(opts, :regimes, "closed,semi,merged"))
    temperature = Keyword.get(opts, :temperature, 0.4)

    model =
      Keyword.get(
        opts,
        :model,
        if(adapter == Tracefield.LLM.Mock, do: "mock", else: "gemma4:12b")
      )

    scenario = Scenario.load!("scenarios/enterprise-assistant")

    measurements =
      for regime <- regimes, index <- 0..(seeds - 1) do
        seed = 1_000 + index

        run =
          Dissolution.run(scenario, regime,
            adapter: adapter,
            model: model,
            temperature: temperature,
            seed: seed,
            rounds: rounds
          )

        measure =
          Dissolution.measure(run,
            adapter: adapter,
            model: model,
            temperature: temperature
          )

        Map.put(measure, :run, run)
      end

    path = persist(measurements, adapter_name)
    print_result(measurements, path)
  end

  defp adapter_module("mock"), do: Tracefield.LLM.Mock
  defp adapter_module("ollama"), do: Tracefield.LLM.Ollama
  defp adapter_module(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp regimes(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn
      "closed" -> :closed
      "semi" -> :semi
      "merged" -> :merged
      other -> Mix.raise("unknown regime #{inspect(other)}")
    end)
  end

  defp persist(measurements, adapter_name) do
    File.mkdir_p!("runs")

    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace("Z", "")

    path = "runs/#{timestamp}-dissolution-#{adapter_name}.json"
    File.write!(path, Jason.encode!(GroundTruth.to_plain(measurements), pretty: true))
    path
  end

  defp print_result(measurements, path) do
    Mix.shell().info("Tracefield Dissolution")
    Mix.shell().info("runs:")
    Mix.shell().info("regime seed icc coverage diversity bias_retention")

    Enum.each(measurements, fn row ->
      Mix.shell().info(
        "#{row.regime} #{row.seed} #{row.icc} #{row.coverage} #{fmt(row.diversity)} #{fmt(row.bias_retention)}"
      )
    end)

    summary = summary_by_regime(measurements)

    Mix.shell().info("")
    Mix.shell().info("aggregate mean±sd:")
    Mix.shell().info("regime icc coverage diversity bias_retention")

    Enum.each([:closed, :semi, :merged], fn regime ->
      if row = summary[regime] do
        Mix.shell().info(
          "#{regime} #{mean_sd(row.icc)} #{mean_sd(row.coverage)} #{mean_sd(row.diversity)} #{mean_sd(row.bias_retention)}"
        )
      end
    end)

    Mix.shell().info("")
    Mix.shell().info("verdicts:")

    Mix.shell().info(
      "H1 semi ICC > closed ICC: #{verdict(mean(summary, :semi, :icc) > mean(summary, :closed, :icc))}"
    )

    Mix.shell().info(
      "H2 semi diversity > merged diversity: #{verdict(mean(summary, :semi, :diversity) > mean(summary, :merged, :diversity))}"
    )

    h3 =
      abs(mean(summary, :merged, :diversity)) <= 0.0001 and
        mean(summary, :merged, :coverage) < mean(summary, :closed, :coverage)

    Mix.shell().info(
      "H3 merged diversity≈0 and merged coverage < closed coverage: #{verdict(h3)}"
    )

    Mix.shell().info("saved: #{path}")
  end

  defp summary_by_regime(measurements) do
    measurements
    |> Enum.group_by(& &1.regime)
    |> Map.new(fn {regime, rows} ->
      {regime,
       %{
         icc: Metrics.summary(Enum.map(rows, &(&1.icc * 1.0))),
         coverage: Metrics.summary(Enum.map(rows, &(&1.coverage * 1.0))),
         diversity: Metrics.summary(Enum.map(rows, & &1.diversity)),
         bias_retention: Metrics.summary(Enum.map(rows, & &1.bias_retention))
       }}
    end)
  end

  defp mean(summary, regime, metric), do: get_in(summary, [regime, metric, :mean]) || 0.0

  defp mean_sd(summary), do: "#{fmt(summary.mean)}±#{fmt(summary.sd)}"
  defp verdict(true), do: "PASS"
  defp verdict(false), do: "FAIL"
  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)
end
