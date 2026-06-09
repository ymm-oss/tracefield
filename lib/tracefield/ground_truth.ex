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
    n_agents = Keyword.get(opts, :n_agents, 4)
    rounds = Keyword.get(opts, :rounds, 3)

    with {:ok, runs_a} <-
           run_state(
             scenario,
             :a,
             n,
             adapter,
             model,
             temperature,
             seed_base,
             persist_runs,
             n_agents,
             rounds
           ),
         {:ok, runs_b} <-
           run_state(
             scenario,
             :b,
             n,
             adapter,
             model,
             temperature,
             seed_base,
             persist_runs,
             n_agents,
             rounds
           ) do
      runs_a = attach_run_keys(runs_a, "a")
      runs_b = attach_run_keys(runs_b, "b")

      runs =
        (runs_a ++ runs_b)
        |> Enum.map(&attach_claims_and_reconstruction(&1, scenario, adapter))

      cluster_assignments =
        cluster_assignments(runs,
          adapter: adapter,
          model: model,
          seed: seed_base + 20_000,
          temperature: temperature
        )

      runs = Enum.map(runs, &attach_clusters(&1, cluster_assignments))
      {runs_a, runs_b} = Enum.split(runs, length(runs_a))

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
         cluster_assignments: cluster_assignments,
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

  def reconstruct(run, claims, llm_opts \\ []) do
    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_RECONSTRUCT_AFFECTED. Return only a JSON array of claim numbers that depend on contaminant A."
      },
      %{
        role: "user",
        content:
          "TASK:\n#{Keyword.get(llm_opts, :task, "")}\n\nCONTAMINANT A:\n#{Keyword.get(llm_opts, :contaminant_body, "")}\n\nTRANSCRIPT:\n#{format_transcript(run.transcript)}\n\nFINAL OUTPUT:\n#{run.raw_output}\n\nCLAIMS:\n#{format_numbered_claims(claims)}"
      }
    ]

    case Tracefield.LLM.complete(messages, Keyword.drop(llm_opts, [:task, :contaminant_body])) do
      {:ok, content} -> parse_reconstructed_ids(content, claims)
      {:error, _reason} -> MapSet.new()
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

  defp run_state(
         scenario,
         state,
         n,
         adapter,
         model,
         temperature,
         seed_base,
         persist_runs,
         n_agents,
         rounds
       ) do
    Enum.reduce_while(0..(n - 1), {:ok, []}, fn index, {:ok, acc} ->
      seed = seed_base + index

      case Explore.run(scenario,
             state: state,
             adapter: adapter,
             model: model,
             temperature: temperature,
             seed: seed,
             n_agents: n_agents,
             rounds: rounds
           ) do
        {:ok, run} ->
          if persist_runs, do: persist_run(run, index)
          {:cont, {:ok, acc ++ [run]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp attach_run_keys(runs, state) do
    runs
    |> Enum.with_index(1)
    |> Enum.map(fn {run, index} -> Map.put(run, :run_key, "#{state}#{index}") end)
  end

  defp attach_claims_and_reconstruction(run, scenario, adapter) do
    llm_opts = run_llm_opts(run, adapter)

    claims =
      Normalize.extract_claims(
        run.raw_output,
        Keyword.put(llm_opts, :seed, run.seed + 10_001)
      )

    reconstructed_affected =
      reconstruct(
        run,
        claims,
        llm_opts
        |> Keyword.put(:seed, run.seed + 10_002)
        |> Keyword.put(:task, scenario.task)
        |> Keyword.put(:contaminant_body, scenario.contaminant.body)
      )

    run
    |> Map.put(:claims, claims)
    |> Map.put(:reconstructed_affected, reconstructed_affected)
  end

  defp run_llm_opts(run, adapter) do
    [
      adapter: adapter,
      model: run.model,
      seed: run.seed,
      temperature: run.temperature
    ]
  end

  defp cluster_assignments(runs, llm_opts) do
    runs
    |> Enum.flat_map(fn run ->
      Enum.map(run.claims, fn claim ->
        %{ref: claim_ref(run.run_key, claim.id), text: claim.text}
      end)
    end)
    |> Normalize.cluster(llm_opts)
  end

  defp attach_clusters(run, assignments) do
    cluster_assignments =
      Map.new(run.claims, fn claim ->
        ref = claim_ref(run.run_key, claim.id)
        {claim.id, Map.fetch!(assignments, ref)}
      end)

    clusters = MapSet.new(Map.values(cluster_assignments))

    reconstructed_affected_clusters =
      run.reconstructed_affected
      |> Enum.map(&Map.get(cluster_assignments, &1))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    run
    |> Map.put(:cluster_assignments, cluster_assignments)
    |> Map.put(:clusters, clusters)
    |> Map.put(:reconstructed_affected_clusters, reconstructed_affected_clusters)
  end

  defp within_distances(runs) do
    for {left, i} <- Enum.with_index(runs),
        {right, j} <- Enum.with_index(runs),
        i < j do
      Normalize.diff(left.clusters, right.clusters)
    end
  end

  defp between_distances(runs_a, runs_b) do
    for left <- runs_a, right <- runs_b do
      Normalize.diff(left.clusters, right.clusters)
    end
  end

  defp ground_truth_set(runs_a, runs_b, threshold) do
    all_ids =
      Enum.concat(runs_a, runs_b)
      |> Enum.flat_map(&MapSet.to_list(&1.clusters))
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
        MapSet.member?(run.clusters, id)
      end)

    count / length(runs)
  end

  defp system_claimed_union(runs) do
    Enum.reduce(runs, MapSet.new(), fn run, acc ->
      MapSet.union(acc, run.reconstructed_affected_clusters)
    end)
  end

  defp claim_ref(run_key, claim_id), do: "#{run_key}|#{claim_id}"

  defp format_numbered_claims(claims) do
    claims
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {claim, index} ->
      "#{index}. [#{claim.id}] #{claim.kind}: #{String.replace(claim.text, "\n", " ")}"
    end)
  end

  defp parse_reconstructed_ids(content, claims) do
    index_to_id =
      claims
      |> Enum.with_index(1)
      |> Map.new(fn {claim, index} -> {index, claim.id} end)

    case decode_json_array(content) do
      {:ok, indexes} when is_list(indexes) ->
        indexes
        |> Enum.map(&parse_claim_index/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&Map.get(index_to_id, &1))
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end

  defp parse_claim_index(index) when is_integer(index), do: index

  defp parse_claim_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_claim_index(_index), do: nil

  defp decode_json_array(content) do
    with {:error, _reason} <- Jason.decode(content),
         {:ok, array_text} <- extract_array_text(content) do
      Jason.decode(array_text)
    end
  end

  defp extract_array_text(content) do
    start = :binary.match(content, "[")

    finish =
      content
      |> String.reverse()
      |> :binary.match("]")

    case {start, finish} do
      {{start_index, 1}, {reverse_index, 1}} ->
        end_index = byte_size(content) - reverse_index - 1

        if end_index >= start_index do
          {:ok, binary_part(content, start_index, end_index - start_index + 1)}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp format_transcript([]), do: "(empty)"

  defp format_transcript(transcript) do
    Enum.map_join(transcript, "\n\n", fn turn ->
      actor = Map.get(turn, :actor, Map.get(turn, "actor", "unknown"))
      content = Map.get(turn, :content, Map.get(turn, "content", ""))
      "[#{actor}]\n#{content}"
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
