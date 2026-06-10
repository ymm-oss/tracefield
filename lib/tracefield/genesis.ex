defmodule Tracefield.Genesis do
  @moduledoc """
  Deterministic genesis attractor detection, proposal, and scaffold generation.
  """

  alias Tracefield.Embed
  alias Tracefield.Meta
  alias Tracefield.Reference

  @default_tau_genesis 0.7
  @default_tau_claim 0.75
  @default_min_size 4

  def detect(meta_ref, charters, opts \\ []) do
    tau_genesis = Keyword.get(opts, :tau_genesis, @default_tau_genesis)
    tau_claim = Keyword.get(opts, :tau_claim, @default_tau_claim)
    min_size = Keyword.get(opts, :min_size, @default_min_size)
    charter_embeddings = embed_charters(charters, opts)

    meta_ref
    |> Reference.all()
    |> Enum.filter(&detect_candidate?/1)
    |> greedy_groups(tau_genesis)
    |> Enum.flat_map(fn group ->
      source_clusters = source_clusters(group)
      centroid = centroid(Enum.map(group, & &1.embedding))
      {max_charter_sim, charter_best} = best_charter(centroid, charter_embeddings)

      if length(group) >= min_size and length(source_clusters) >= 2 and
           max_charter_sim < tau_claim do
        [
          %{
            members: group,
            source_clusters: source_clusters,
            max_charter_sim: max_charter_sim,
            charter_best: charter_best
          }
        ]
      else
        []
      end
    end)
  end

  def propose(meta_ref, %{members: members, source_clusters: source_clusters}) do
    citations = Enum.map(members, & &1.id)
    first_text = members |> List.first() |> then(&if(&1, do: &1.text, else: ""))

    text =
      "析出提案: #{Enum.join(source_clusters, ",")}由来の#{length(members)}件 — #{String.slice(first_text, 0, 60)}…"

    [entry] =
      Reference.absorb(
        meta_ref,
        [%{type: :genesis, text: text, citations: citations}],
        "GENESIS"
      )

    entry
  end

  def scaffold(meta_ref, genesis_id, dir, opts \\ []) do
    genesis =
      Reference.get(meta_ref, genesis_id) ||
        raise ArgumentError, "unknown genesis id #{genesis_id}"

    member_ids = genesis.citations

    members =
      member_ids
      |> Enum.map(&Reference.get(meta_ref, &1))
      |> Enum.reject(&is_nil/1)

    source_clusters = source_clusters(members)
    dir = Path.expand(dir)
    private_dir = Path.join(dir, "private")
    File.mkdir_p!(private_dir)

    files = [
      write_file(dir, "task.md", task_markdown(genesis, members)),
      write_file(dir, "agents.json", agents_json(source_clusters)),
      write_file(dir, "procedure.md", procedure_markdown())
    ]

    private_files =
      source_clusters
      |> Enum.map(fn cluster ->
        write_file(private_dir, "#{cluster}.md", private_markdown(cluster, members))
      end)

    general_file = write_file(private_dir, "general.md", general_markdown(members))
    store_path = Path.join(dir, "store.jsonl")
    {:ok, target_ref} = Reference.start_link(persist_path: store_path)
    seeded = Meta.pull(target_ref, meta_ref, member_ids)

    files = files ++ private_files ++ [general_file, store_path]
    relative_files = Enum.map(files, &Path.relative_to(&1, dir))

    if Keyword.get(opts, :stop_store, true), do: GenServer.stop(target_ref)

    %{dir: dir, files: relative_files, seeded: length(seeded)}
  end

  defp detect_candidate?(entry) do
    entry.status == :active and entry.type not in [:chunk, :procedure]
  end

  defp greedy_groups(entries, tau) do
    entries
    |> Enum.reduce([], fn entry, groups ->
      index =
        Enum.find_index(groups, fn [representative | _rest] ->
          Embed.cosine(entry.embedding, representative.embedding) >= tau
        end)

      case index do
        nil -> groups ++ [[entry]]
        index -> List.update_at(groups, index, &(&1 ++ [entry]))
      end
    end)
  end

  defp embed_charters(charters, opts) do
    normalized =
      Enum.map(List.wrap(charters), fn charter ->
        %{
          name: charter_value(charter, :name, ""),
          text: charter_value(charter, :text, "")
        }
      end)

    texts = Enum.map(normalized, & &1.text)

    embeddings =
      case Embed.embed(texts, embed_opts(opts)) do
        {:ok, embeddings} -> embeddings
        {:error, _reason} -> Enum.map(texts, fn _text -> [] end)
      end

    Enum.zip_with(normalized, embeddings, fn charter, embedding ->
      %{name: to_string(charter.name), embedding: embedding}
    end)
  end

  defp best_charter(_centroid, []), do: {0.0, nil}

  defp best_charter(centroid, charters) do
    charters
    |> Enum.map(fn charter -> {Embed.cosine(centroid, charter.embedding), charter.name} end)
    |> Enum.max_by(fn {sim, _name} -> sim end, fn -> {0.0, nil} end)
  end

  defp centroid([]), do: []

  defp centroid(vectors) do
    dims = vectors |> hd() |> length()

    vectors
    |> Enum.reduce(List.duplicate(0.0, dims), fn vector, acc ->
      Enum.zip_with(acc, vector, &(&1 + &2))
    end)
    |> Enum.map(&(&1 / length(vectors)))
    |> normalize_vector()
  end

  defp normalize_vector(vector) do
    norm =
      vector
      |> Enum.map(&(&1 * &1))
      |> Enum.sum()
      |> :math.sqrt()

    if norm == 0.0, do: vector, else: Enum.map(vector, &(&1 / norm))
  end

  defp source_clusters(entries) do
    entries
    |> Enum.map(&meta_value(&1.meta, :source_cluster))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp task_markdown(genesis, members) do
    """
    # Genesis Cluster

    ## Mission

    #{genesis.text}

    ## Background Findings

    #{bullet_texts(members)}
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  defp agents_json(source_clusters) do
    agents =
      Enum.map(source_clusters, fn cluster ->
        %{
          id: "#{cluster}_LENS",
          domain: "#{cluster}-perspective",
          desc: "#{cluster}由来の知見を優先して検討する",
          private_doc: "#{cluster}.md"
        }
      end) ++
        [
          %{
            id: "GENERAL",
            domain: "general-perspective",
            desc: "全体の整合と未接続の論点を検討する",
            private_doc: "general.md"
          }
        ]

    Jason.encode!(agents, pretty: true) <> "\n"
  end

  defp private_markdown(cluster, members) do
    cluster_members =
      Enum.filter(members, fn member -> meta_value(member.meta, :source_cluster) == cluster end)

    """
    # #{cluster} Lens

    #{bullet_texts(cluster_members)}
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  defp general_markdown(members) do
    """
    # General Lens

    #{bullet_texts(members)}
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  defp procedure_markdown do
    """
    # Procedure

    1. Read task.md and your private lens note.
    2. Preserve cited provenance when making claims.
    3. Publish concise belief or decision entries with citations.
    """
  end

  defp bullet_texts([]), do: "- (none)"
  defp bullet_texts(entries), do: Enum.map_join(entries, "\n", fn entry -> "- #{entry.text}" end)

  defp write_file(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  defp embed_opts(opts) do
    [
      adapter: Keyword.get(opts, :embed_adapter, Tracefield.Embed.Mock),
      model: Keyword.get(opts, :embed_model, "nomic-embed-text")
    ]
  end

  defp charter_value(%{} = charter, key, default),
    do: Map.get(charter, key, Map.get(charter, to_string(key), default))

  defp charter_value(_charter, _key, default), do: default

  defp meta_value(meta, key) when is_map(meta) do
    value = Map.get(meta, key, Map.get(meta, to_string(key)))
    if is_nil(value), do: nil, else: to_string(value)
  end

  defp meta_value(_meta, _key), do: nil
end
