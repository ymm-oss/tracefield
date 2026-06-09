defmodule Mix.Tasks.Tracefield.Provenance do
  @moduledoc "Run mock point-provenance comparison."
  use Mix.Task

  alias Tracefield.{GroundTruth, Scenario}

  @shortdoc "Run Tracefield mock provenance comparison"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          n: :integer,
          seed_base: :integer,
          n_agents: :integer,
          rounds: :integer
        ],
        aliases: [n: :n]
      )

    scenario = Scenario.load!("scenarios/enterprise-assistant")

    {:ok, result} =
      GroundTruth.run(scenario,
        adapter: Tracefield.LLM.Mock,
        n: Keyword.get(opts, :n, 1),
        temperature: 0.2,
        seed_base: Keyword.get(opts, :seed_base, 700),
        n_agents: Keyword.get(opts, :n_agents, 4),
        rounds: Keyword.get(opts, :rounds, 2),
        persist_runs: false
      )

    Mix.shell().info("Tracefield Provenance - mock")
    Mix.shell().info("c5_affected_points: #{inspect(sorted(result.c5_affected_points))}")
    Mix.shell().info("c4_affected_points: #{inspect(sorted(result.c4_affected_points))}")
    Mix.shell().info("c5_minus_c4: #{inspect(sorted(result.c5_minus_c4))}")
  end

  defp sorted(set), do: set |> MapSet.to_list() |> Enum.sort()
end
