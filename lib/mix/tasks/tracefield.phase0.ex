defmodule Mix.Tasks.Tracefield.Phase0 do
  @moduledoc "Run Phase 0 mock wiring checks."
  use Mix.Task

  alias Tracefield.{GroundTruth, Metrics, Normalize, Scenario}

  @shortdoc "Run Tracefield Phase 0"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    scenario = Scenario.load!("scenarios/enterprise-assistant")
    toy_same = claims(["a", "b"])
    toy_half_left = claims(["a", "b", "c"])
    toy_half_right = claims(["a", "b", "d"])
    toy_disjoint = claims(["x", "y"])

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

    proxy = Metrics.prf(result.ground_truth_set, result.system_claimed_affected)

    Mix.shell().info("within mean: #{fmt(result.within_summary.mean)}")
    Mix.shell().info("between mean: #{fmt(result.between_summary.mean)}")
    Mix.shell().info("AUC: #{fmt(result.auc)}")
    Mix.shell().info("Cliff's delta: #{fmt(result.cliffs_delta)}")
    Mix.shell().info("ground truth set: #{inspect(MapSet.to_list(result.ground_truth_set))}")
    Mix.shell().info("proxy recall: #{fmt(proxy.recall)}")
    Mix.shell().info("proxy precision: #{fmt(proxy.precision)}")
  end

  defp claims(ids) do
    ids
    |> Enum.with_index(1)
    |> Enum.map(fn {id, index} ->
      %Normalize.Claim{id: id, text: "claim #{id}", kind: :concern, raw_index: index}
    end)
  end

  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)
end
