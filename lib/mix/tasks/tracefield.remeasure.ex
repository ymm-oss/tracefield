defmodule Mix.Tasks.Tracefield.Remeasure do
  @moduledoc "Remeasure a saved Tracefield Phase 1 summary without rerunning exploration."
  use Mix.Task

  alias Tracefield.{GroundTruth, Scenario}

  @shortdoc "Remeasure a saved Tracefield summary"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          from: :string,
          adapter: :string,
          model: :string,
          temperature: :float,
          seed_base: :integer
        ]
      )

    from = Keyword.get(opts, :from) || Mix.raise("missing required --from")
    summary = read_summary!(from)
    adapter = adapter_module(Keyword.get(opts, :adapter) || adapter_name(summary))
    scenario = Scenario.load!(scenario_dir(summary))
    contaminant = contaminant_name(summary)
    decoys = decoys_from_summary(summary, scenario)

    {:ok, result} =
      GroundTruth.measure(summary["runs_a"] || [], summary["runs_b"] || [], scenario,
        adapter: adapter,
        model: Keyword.get(opts, :model, summary["model"] || default_model(adapter)),
        temperature: Keyword.get(opts, :temperature, summary["temperature"] || 0.2),
        seed_base: Keyword.get(opts, :seed_base, summary["seed_base"] || 1_000),
        n: summary["n"] || max(length(summary["runs_a"] || []), length(summary["runs_b"] || [])),
        contaminant: contaminant,
        decoys: decoys
      )

    path = persist_summary(result, from)
    print_result(result, from, path)
  end

  defp read_summary!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp scenario_dir(%{"scenario" => %{"dir" => dir}}) when is_binary(dir) and dir != "", do: dir
  defp scenario_dir(_summary), do: "scenarios/enterprise-assistant"

  defp adapter_name(%{"adapter" => adapter}) when is_binary(adapter) do
    cond do
      String.contains?(adapter, "Ollama") -> "ollama"
      true -> "mock"
    end
  end

  defp adapter_name(_summary), do: "mock"

  defp adapter_module("mock"), do: Tracefield.LLM.Mock
  defp adapter_module("ollama"), do: Tracefield.LLM.Ollama
  defp adapter_module(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp contaminant_name(%{"contaminant" => contaminant}) when contaminant in ["a", "b", "c"],
    do: contaminant

  defp contaminant_name(_summary), do: "a"

  defp decoys_from_summary(%{"decoys" => decoy_ids}, scenario) when is_list(decoy_ids) do
    decoys_by_id = Map.new(scenario.decoys, &{&1.id, &1})

    decoy_ids
    |> Enum.map(&Map.get(decoys_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp decoys_from_summary(_summary, _scenario), do: []

  defp default_model(Tracefield.LLM.Mock), do: "mock"
  defp default_model(_adapter), do: "gemma4:12b"

  defp persist_summary(result, from) do
    File.mkdir_p!("runs")

    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace("Z", "")

    stem = from |> Path.basename(".json") |> String.replace(~r/[^A-Za-z0-9_.-]+/, "-")
    path = "runs/#{timestamp}-remeasure-#{stem}.json"
    File.write!(path, Jason.encode!(GroundTruth.to_plain(result), pretty: true))
    path
  end

  defp print_result(result, from, path) do
    Mix.shell().info("Tracefield Remeasure - #{result.adapter}")
    Mix.shell().info("from: #{from}")
    Mix.shell().info("model: #{result.model}")
    Mix.shell().info("n per state: #{result.n}")
    Mix.shell().info("contaminant: #{result.contaminant}")
    Mix.shell().info("decoys: #{inspect(result.decoys)}")
    Mix.shell().info("affected set: #{inspect(MapSet.to_list(result.affected_set))}")
    Mix.shell().info("proxy recall: #{fmt(result.proxy.recall)}")
    Mix.shell().info("proxy precision: #{fmt(result.proxy.precision)}")
    Mix.shell().info("proxy f1: #{fmt(result.proxy.f1)}")
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

  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)
end
