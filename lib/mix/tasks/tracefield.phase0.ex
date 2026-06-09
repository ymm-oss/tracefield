defmodule Mix.Tasks.Tracefield.Phase0 do
  @moduledoc "Run Phase 0 mock wiring checks."
  use Mix.Task

  alias Tracefield.{GroundTruth, Normalize, Scenario}

  @shortdoc "Run Tracefield Phase 0"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    scenario = Scenario.load!("scenarios/enterprise-assistant")
    toy_same = MapSet.new(["a", "b"])
    toy_half_left = MapSet.new(["a", "b", "c"])
    toy_half_right = MapSet.new(["a", "b", "d"])
    toy_disjoint = MapSet.new(["x", "y"])

    Mix.shell().info("Tracefield Phase 0 - mock wiring")
    Mix.shell().info("diff identical: #{fmt(Normalize.diff(toy_same, toy_same))}")
    Mix.shell().info("diff half-overlap: #{fmt(Normalize.diff(toy_half_left, toy_half_right))}")
    Mix.shell().info("diff disjoint: #{fmt(Normalize.diff(toy_same, toy_disjoint))}")

    {:ok, result} =
      GroundTruth.run(scenario,
        adapter: Tracefield.LLM.Mock,
        n: 4,
        temperature: 0.2,
        seed_base: 700,
        persist_runs: false
      )

    Mix.shell().info("within mean: #{fmt(result.within_summary.mean)}")
    Mix.shell().info("between mean: #{fmt(result.between_summary.mean)}")
    Mix.shell().info("AUC: #{fmt(result.auc)}")
    Mix.shell().info("Cliff's delta: #{fmt(result.cliffs_delta)}")
    Mix.shell().info("affected set: #{inspect(MapSet.to_list(result.affected_set))}")
    Mix.shell().info("proxy recall: #{fmt(result.proxy.recall)}")
    Mix.shell().info("proxy precision: #{fmt(result.proxy.precision)}")
    print_stance_table(result.stance_table)
  end

  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)

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
end
