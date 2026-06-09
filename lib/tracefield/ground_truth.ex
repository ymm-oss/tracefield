defmodule Tracefield.GroundTruth do
  @moduledoc """
  Counterfactual A/B x N runner and ground-truth set builder.
  """

  alias Tracefield.{Explore, Metrics, Normalize, Provenance, Stance}

  def run(%Tracefield.Scenario{} = scenario, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Mock)
    n = Keyword.get(opts, :n, 8)
    temperature = Keyword.get(opts, :temperature, 0.2)
    seed_base = Keyword.get(opts, :seed_base, 1_000)
    model = Keyword.get(opts, :model, default_model(adapter))
    persist_runs = Keyword.get(opts, :persist_runs, true)
    n_agents = Keyword.get(opts, :n_agents, 4)
    rounds = Keyword.get(opts, :rounds, 3)
    condition = normalize_condition(Keyword.get(opts, :condition, :c4))
    contaminant = normalize_contaminant(Keyword.get(opts, :contaminant, "a"))
    decoys = Keyword.get(opts, :decoys, [])

    with condition when is_atom(condition) <- condition,
         contaminant when is_binary(contaminant) <- contaminant,
         {:ok, _pair} <- Tracefield.Scenario.contaminant_pair(scenario, contaminant),
         {:ok, runs_a} <-
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
             rounds,
             condition,
             contaminant,
             decoys
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
             rounds,
             condition,
             contaminant,
             decoys
           ) do
      runs_a = attach_run_keys(runs_a, "a")
      runs_b = attach_run_keys(runs_b, "b")

      measure(runs_a, runs_b, scenario,
        adapter: adapter,
        model: model,
        temperature: temperature,
        seed_base: seed_base,
        n: n,
        condition: condition,
        contaminant: contaminant,
        decoys: decoys
      )
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def measure(runs_a, runs_b, %Tracefield.Scenario{} = scenario, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Mock)
    model = Keyword.get(opts, :model, default_model(adapter))
    temperature = Keyword.get(opts, :temperature, 0.2)
    seed_base = Keyword.get(opts, :seed_base, 1_000)
    n = Keyword.get(opts, :n, max(length(runs_a), length(runs_b)))
    condition = normalize_condition(Keyword.get(opts, :condition, :c4))
    contaminant = normalize_contaminant(Keyword.get(opts, :contaminant, "a"))
    decoys = Keyword.get(opts, :decoys, [])

    with condition when is_atom(condition) <- condition,
         contaminant when is_binary(contaminant) <- contaminant,
         {:ok, selected} <- Tracefield.Scenario.contaminant_pair(scenario, contaminant) do
      runs_a = runs_a |> Enum.map(&normalize_run/1) |> ensure_run_keys("a")
      runs_b = runs_b |> Enum.map(&normalize_run/1) |> ensure_run_keys("b")

      runs =
        (runs_a ++ runs_b)
        |> Enum.map(
          &attach_claims_and_reconstruction(&1, scenario, selected.contaminant.body, adapter)
        )

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

      stance_table =
        stance_table(runs_a, runs_b,
          adapter: adapter,
          model: model,
          seed: seed_base + 30_000,
          temperature: temperature
        )

      affected_set = affected_set(stance_table)
      system_set = system_claimed_union(runs_a ++ runs_b)
      proxy = Metrics.prf(affected_set, system_set)
      provenance = Provenance.build(runs_a ++ runs_b, injection_ids: [selected.contaminant.id])

      c4_affected_points =
        reconstruct_points(
          runs_a ++ runs_b,
          scenario,
          adapter: adapter,
          model: model,
          temperature: temperature,
          seed: seed_base + 40_000,
          contaminant_body: selected.contaminant.body
        )

      provenance_comparison =
        Provenance.compare(provenance.c5_affected_points, c4_affected_points)

      {:ok,
       %{
         condition: condition,
         adapter: inspect(adapter),
         model: model,
         temperature: temperature,
         seed_base: seed_base,
         n: n,
         contaminant: contaminant,
         decoys: Enum.map(decoys, & &1.id),
         generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
         scenario: scenario_to_plain(scenario, selected, decoys),
         runs_a: runs_a,
         runs_b: runs_b,
         cluster_assignments: cluster_assignments,
         stance_table: stance_table,
         within: within,
         between: between,
         within_summary: Metrics.summary(within),
         between_summary: Metrics.summary(between),
         auc: Metrics.auc(within, between),
         cliffs_delta: Metrics.cliffs_delta(within, between),
         affected_set: affected_set,
         ground_truth_set: affected_set,
         system_claimed_affected: system_set,
         proxy: proxy,
         c5_affected_points: provenance_comparison.c5_affected_points,
         c4_affected_points: provenance_comparison.c4_affected_points,
         c5_minus_c4: provenance_comparison.c5_minus_c4,
         c5_quarantine: provenance.c5_quarantine
       }}
    else
      {:error, reason} -> {:error, reason}
      {:unknown_contaminant, contaminant} -> {:error, {:unknown_contaminant, contaminant}}
    end
  end

  def reconstruct(run, claims, llm_opts \\ []) do
    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_RECONSTRUCT_AFFECTED. Return only a JSON array of claim numbers that depend on the contaminant note."
      },
      %{
        role: "user",
        content:
          "TASK:\n#{Keyword.get(llm_opts, :task, "")}\n\nCONTAMINANT NOTE:\n#{Keyword.get(llm_opts, :contaminant_body, "")}\n\nTRANSCRIPT:\n#{format_transcript(run.transcript)}\n\nFINAL OUTPUT:\n#{run.raw_output}\n\nCLAIMS:\n#{format_numbered_claims(claims)}"
      }
    ]

    case Tracefield.LLM.complete(messages, Keyword.drop(llm_opts, [:task, :contaminant_body])) do
      {:ok, content} -> parse_reconstructed_ids(content, claims)
      {:error, _reason} -> MapSet.new()
    end
  end

  def reconstruct_points(runs, %Tracefield.Scenario{} = scenario, llm_opts \\ []) do
    points = Provenance.points(runs)

    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_RECONSTRUCT_AFFECTED_POINTS. Return only a JSON array of point numbers that depend on the contaminant note."
      },
      %{
        role: "user",
        content:
          "TASK:\n#{scenario.task}\n\nCONTAMINANT NOTE:\n#{Keyword.get(llm_opts, :contaminant_body, scenario.contaminant.body)}\n\nTRANSCRIPTS:\n#{format_runs(runs)}\n\nPOINTS:\n#{format_numbered_points(points)}"
      }
    ]

    case Tracefield.LLM.complete(messages, Keyword.drop(llm_opts, [:task, :contaminant_body])) do
      {:ok, content} -> parse_reconstructed_point_ids(content, points)
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
         rounds,
         condition,
         contaminant,
         decoys
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
             rounds: rounds,
             condition: condition,
             contaminant: contaminant,
             decoys: decoys
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

  defp attach_claims_and_reconstruction(run, scenario, contaminant_body, adapter) do
    llm_opts = run_llm_opts(run, adapter)

    claims =
      case Map.get(run, :claims) do
        nil ->
          Normalize.extract_claims(
            run.raw_output,
            Keyword.put(llm_opts, :seed, run.seed + 10_001)
          )

        claims ->
          Enum.map(claims, &normalize_claim/1)
      end

    reconstructed_affected =
      reconstruct(
        run,
        claims,
        llm_opts
        |> Keyword.put(:seed, run.seed + 10_002)
        |> Keyword.put(:task, scenario.task)
        |> Keyword.put(:contaminant_body, contaminant_body)
      )

    run
    |> Map.put(:claims, claims)
    |> Map.put(:reconstructed_affected, reconstructed_affected)
  end

  defp run_llm_opts(run, adapter) do
    [
      adapter: adapter,
      model: Map.get(run, :model, "mock"),
      seed: Map.get(run, :seed, 0),
      temperature: Map.get(run, :temperature, 0.2)
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

  defp system_claimed_union(runs) do
    Enum.reduce(runs, MapSet.new(), fn run, acc ->
      MapSet.union(acc, run.reconstructed_affected_clusters)
    end)
  end

  defp stance_table(runs_a, runs_b, llm_opts) do
    all_ids =
      Enum.concat(runs_a, runs_b)
      |> Enum.flat_map(&MapSet.to_list(&1.clusters))
      |> Enum.uniq()
      |> Enum.sort()

    all_ids
    |> Enum.with_index()
    |> Map.new(fn {topic, index} ->
      a_texts = claim_texts_for_topic(runs_a, topic)
      b_texts = claim_texts_for_topic(runs_b, topic)
      a_present = a_texts != []
      b_present = b_texts != []

      assessment =
        if a_present and b_present do
          Stance.assess(
            topic,
            a_texts,
            b_texts,
            Keyword.put(llm_opts, :seed, llm_opts[:seed] + index)
          )
        else
          %{differs: false, g1: "", g2: ""}
        end

      {topic,
       %{
         topic: topic,
         a_present: a_present,
         b_present: b_present,
         support: length(a_texts) + length(b_texts),
         presence_changed: a_present != b_present,
         differs: assessment.differs,
         g1: assessment.g1,
         g2: assessment.g2
       }}
    end)
  end

  # A topic is affected if its stance flips, or if it appears on only one side
  # AND is backed by enough claims to be a real recurring topic (min_support).
  # Single-claim clustering leftovers (support 1) are treated as noise, not effects.
  defp affected_set(stance_table, min_support \\ 2) do
    stance_table
    |> Enum.filter(fn {_topic, row} ->
      row.differs or (row.presence_changed and row.support >= min_support)
    end)
    |> Enum.map(fn {topic, _row} -> topic end)
    |> MapSet.new()
  end

  defp claim_texts_for_topic(runs, topic) do
    runs
    |> Enum.flat_map(fn run ->
      Enum.flat_map(run.claims, fn claim ->
        if Map.get(run.cluster_assignments, claim.id) == topic do
          [claim.text]
        else
          []
        end
      end)
    end)
    |> Enum.uniq()
  end

  defp normalize_run(%{} = run) do
    %{
      condition: value(run, :condition),
      state: parse_state(value(run, :state)),
      seed: parse_integer(value(run, :seed), 0),
      model: value(run, :model, "mock"),
      temperature: parse_float(value(run, :temperature), 0.2),
      timestamp: value(run, :timestamp),
      raw_output: value(run, :raw_output, ""),
      transcript: normalize_transcript(value(run, :transcript, [])),
      run_key: value(run, :run_key),
      claims: normalize_claims_if_present(value(run, :claims))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp ensure_run_keys(runs, state) do
    runs
    |> Enum.with_index(1)
    |> Enum.map(fn {run, index} ->
      case Map.get(run, :run_key) do
        key when is_binary(key) and key != "" -> run
        _ -> Map.put(run, :run_key, "#{state}#{index}")
      end
    end)
  end

  defp normalize_claims_if_present(nil), do: nil

  defp normalize_claims_if_present(claims) when is_list(claims),
    do: Enum.map(claims, &normalize_claim/1)

  defp normalize_claim(%Normalize.Claim{} = claim), do: claim

  defp normalize_claim(%{} = claim) do
    %Normalize.Claim{
      id: value(claim, :id, ""),
      text: value(claim, :text, ""),
      kind: parse_kind(value(claim, :kind, "concern")),
      raw_index: parse_integer(value(claim, :raw_index), 0)
    }
  end

  defp normalize_transcript(transcript) when is_list(transcript) do
    Enum.map(transcript, fn
      %{} = turn ->
        Map.new(turn, fn {key, value} ->
          {normalize_known_key(key), value}
        end)

      other ->
        other
    end)
  end

  defp normalize_transcript(_transcript), do: []

  defp normalize_known_key(key) when is_atom(key), do: key

  defp normalize_known_key(key) when is_binary(key) do
    case key do
      "role" -> :role
      "actor" -> :actor
      "round" -> :round
      "turn_id" -> :turn_id
      "injection_id" -> :injection_id
      "content" -> :content
      "raw_content" -> :raw_content
      "points" -> :points
      "point_id" -> :point_id
      "text" -> :text
      "depends_on_turns" -> :depends_on_turns
      "uses_injection" -> :uses_injection
      _ -> key
    end
  end

  defp parse_kind(kind) when is_atom(kind), do: kind

  defp parse_kind(kind) when is_binary(kind) do
    String.to_existing_atom(kind)
  rescue
    ArgumentError -> :concern
  end

  defp parse_kind(_kind), do: :concern

  defp parse_state(state) when state in [:a, :b], do: state
  defp parse_state("a"), do: :a
  defp parse_state("b"), do: :b
  defp parse_state(state), do: state

  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp parse_integer(_value, default), do: default

  defp parse_float(value, _default) when is_float(value), do: value
  defp parse_float(value, _default) when is_integer(value), do: value * 1.0

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp parse_float(_value, default), do: default

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp normalize_condition(condition) when condition in [:c4, "c4"], do: :c4
  defp normalize_condition(condition) when condition in [:c1, "c1"], do: :c1
  defp normalize_condition(condition), do: {:error, {:unknown_condition, condition}}

  defp normalize_contaminant(contaminant) when contaminant in [:a, :b, :c] do
    contaminant |> Atom.to_string() |> normalize_contaminant()
  end

  defp normalize_contaminant(contaminant) when is_binary(contaminant) do
    contaminant = contaminant |> String.trim() |> String.downcase()

    if contaminant in ["a", "b", "c"] do
      contaminant
    else
      {:error, {:unknown_contaminant, contaminant}}
    end
  end

  defp normalize_contaminant(contaminant), do: {:error, {:unknown_contaminant, contaminant}}

  defp scenario_to_plain(scenario, selected, decoys) do
    %{
      dir: scenario.dir,
      task: scenario.task,
      contaminant_body: selected.contaminant.body,
      correction_body: selected.correction.body,
      decoys: Enum.map(decoys, & &1.id)
    }
  end

  defp claim_ref(run_key, claim_id), do: "#{run_key}|#{claim_id}"

  defp format_numbered_claims(claims) do
    claims
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {claim, index} ->
      "#{index}. [#{claim.id}] #{claim.kind}: #{String.replace(claim.text, "\n", " ")}"
    end)
  end

  defp format_numbered_points(points) do
    points
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {point, index} ->
      "#{index}. [#{point.id}] #{String.replace(point.text, "\n", " ")}"
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

  defp parse_reconstructed_point_ids(content, points) do
    index_to_id =
      points
      |> Enum.with_index(1)
      |> Map.new(fn {point, index} -> {index, point.id} end)

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
      turn_id = Map.get(turn, :turn_id, Map.get(turn, "turn_id", "?"))
      "[TURN #{turn_id} #{actor}]\n#{content}"
    end)
  end

  defp format_runs(runs) do
    Enum.map_join(runs, "\n\n", fn run ->
      "RUN #{Map.get(run, :run_key, Map.get(run, "run_key", "run"))}\n#{format_transcript(Map.get(run, :transcript, Map.get(run, "transcript", [])))}"
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
