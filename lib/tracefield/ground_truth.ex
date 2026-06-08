defmodule Tracefield.GroundTruth do
  @moduledoc """
  Counterfactual A/B x N runner and ground-truth set builder.
  """

  alias Tracefield.{Explore, Metrics, Normalize}

  def run(%Tracefield.Scenario{} = scenario, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Mock)
    n = Keyword.get(opts, :n, 8)
    temperature = Keyword.get(opts, :temperature, 0.2)
    seed_base = Keyword.get(opts, :seed_base, 1_000)
    model = Keyword.get(opts, :model, default_model(adapter))
    threshold = Keyword.get(opts, :threshold, 0.5)
    persist_runs = Keyword.get(opts, :persist_runs, true)

    with {:ok, runs_a} <-
           run_state(scenario, :a, n, adapter, model, temperature, seed_base, persist_runs),
         {:ok, runs_b} <-
           run_state(scenario, :b, n, adapter, model, temperature, seed_base, persist_runs) do
      runs_a = Enum.map(runs_a, &attach_claims(&1, adapter))
      runs_b = Enum.map(runs_b, &attach_claims(&1, adapter))

      within = within_distances(runs_a) ++ within_distances(runs_b)
      between = between_distances(runs_a, runs_b)
      ground_truth_set = ground_truth_set(runs_a, runs_b, threshold)
      system_set = system_claimed_union(runs_a ++ runs_b)
      proxy = Metrics.prf(ground_truth_set, system_set)

      {:ok,
       %{
         condition: :c4,
         adapter: inspect(adapter),
         model: model,
         temperature: temperature,
         seed_base: seed_base,
         n: n,
         generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
         runs_a: runs_a,
         runs_b: runs_b,
         within: within,
         between: between,
         within_summary: Metrics.summary(within),
         between_summary: Metrics.summary(between),
         auc: Metrics.auc(within, between),
         cliffs_delta: Metrics.cliffs_delta(within, between),
         ground_truth_set: ground_truth_set,
         system_claimed_affected: system_set,
         proxy: proxy
       }}
    end
  end

  def to_plain(term) when is_struct(term, MapSet), do: MapSet.to_list(term)

  def to_plain(%Normalize.Claim{} = claim) do
    %{id: claim.id, text: claim.text, kind: claim.kind, raw_index: claim.raw_index}
  end

  def to_plain(%{} = map) do
    Map.new(map, fn {key, value} -> {key, to_plain(value)} end)
  end

  def to_plain(list) when is_list(list), do: Enum.map(list, &to_plain/1)
  def to_plain(atom) when is_atom(atom), do: Atom.to_string(atom)
  def to_plain(other), do: other

  defp run_state(scenario, state, n, adapter, model, temperature, seed_base, persist_runs) do
    Enum.reduce_while(0..(n - 1), {:ok, []}, fn index, {:ok, acc} ->
      seed = seed_base + index

      case Explore.run(scenario,
             state: state,
             adapter: adapter,
             model: model,
             temperature: temperature,
             seed: seed
           ) do
        {:ok, run} ->
          if persist_runs, do: persist_run(run, index)
          {:cont, {:ok, acc ++ [run]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp attach_claims(run, adapter) do
    claims =
      Normalize.extract_claims(run.raw_output,
        adapter: adapter,
        model: run.model,
        seed: run.seed,
        temperature: run.temperature
      )

    Map.put(run, :claims, claims)
  end

  defp within_distances(runs) do
    for {left, i} <- Enum.with_index(runs),
        {right, j} <- Enum.with_index(runs),
        i < j do
      Normalize.diff(left.claims, right.claims)
    end
  end

  defp between_distances(runs_a, runs_b) do
    for left <- runs_a, right <- runs_b do
      Normalize.diff(left.claims, right.claims)
    end
  end

  defp ground_truth_set(runs_a, runs_b, threshold) do
    all_ids =
      Enum.concat(runs_a, runs_b)
      |> Enum.flat_map(&MapSet.to_list(Normalize.cluster_ids(&1.claims)))
      |> MapSet.new()

    all_ids
    |> Enum.filter(fn id ->
      frequency(runs_a, id) - frequency(runs_b, id) >= threshold
    end)
    |> MapSet.new()
  end

  defp frequency([], _id), do: 0.0

  defp frequency(runs, id) do
    count =
      Enum.count(runs, fn run ->
        run.claims
        |> Normalize.cluster_ids()
        |> MapSet.member?(id)
      end)

    count / length(runs)
  end

  defp system_claimed_union(runs) do
    Enum.reduce(runs, MapSet.new(), fn run, acc ->
      MapSet.union(acc, run.system_claimed_affected)
    end)
  end

  defp persist_run(run, index) do
    File.mkdir_p!("runs")

    filename =
      "runs/#{System.system_time(:millisecond)}-#{run.state}-#{index + 1}-seed-#{run.seed}.json"

    File.write!(filename, Jason.encode!(to_plain(run), pretty: true))
  end

  defp default_model(Tracefield.LLM.Mock), do: "mock"
  defp default_model(_adapter), do: "gemma4:12b"
end
