defmodule Tracefield.Transfer do
  @moduledoc """
  Move an agent between Tracefield cluster directories.
  """

  alias Tracefield.{Memory, Reference}

  @policies [:distill, :fresh, :full]

  def move(from_dir, to_dir, agent_id, opts \\ []) do
    from_dir = Path.expand(from_dir)
    to_dir = Path.expand(to_dir)
    agent_id = to_string(agent_id)
    policy = normalize_policy(Keyword.get(opts, :policy, :distill))
    limit = Keyword.get(opts, :limit, 5) |> max(0)

    with {:ok, from_agents} <- load_agents(from_dir),
         {:ok, to_agents} <- load_agents(to_dir),
         {:ok, agent} <- fetch_agent(from_agents, agent_id),
         :ok <- ensure_absent(to_agents, agent_id) do
      do_move(from_dir, to_dir, agent_id, policy, limit, from_agents, to_agents, agent)
    end
  end

  defp do_move(from_dir, to_dir, agent_id, policy, limit, from_agents, to_agents, agent) do
    from_name = Path.basename(from_dir)
    to_name = Path.basename(to_dir)
    from_store_path = Path.join(from_dir, "store.jsonl")
    to_store_path = Path.join(to_dir, "store.jsonl")
    memory_path = Memory.memory_path(Path.join(from_dir, "memory"), agent_id)
    to_memory_path = Memory.memory_path(Path.join(to_dir, "memory"), agent_id)

    store_entries =
      if File.exists?(from_store_path), do: store_entries(from_store_path), else: nil

    {memory_entries, stale_excluded} =
      memory_path |> Memory.read_file() |> Memory.filter_stale(store_entries)

    {agent, summary_entry, files} =
      apply_policy(
        policy,
        agent,
        memory_entries,
        from_name,
        to_name,
        to_dir,
        to_store_path,
        limit
      )

    files = files ++ copy_procedure(agent, from_dir, to_dir)
    files = files ++ write_memory(policy, memory_entries, to_memory_path)

    write_agents!(from_dir, reject_agent(from_agents, agent_id))
    write_agents!(to_dir, to_agents ++ [agent])
    remove_source_memory(memory_path)

    files =
      files ++
        [
          rel(from_dir, Path.join(from_dir, "agents.json")),
          rel(to_dir, Path.join(to_dir, "agents.json"))
        ] ++
        departure_record(from_store_path, agent_id, to_name, policy) ++
        arrival_record(policy, to_store_path, agent_id, from_name)

    %{
      policy: policy,
      summary_entry: summary_entry,
      stale_excluded: stale_excluded,
      files: Enum.uniq(files)
    }
  end

  defp apply_policy(:distill, agent, memory_entries, from_name, _to_name, to_dir, to_store, limit) do
    summary = experience_summary(agent_id(agent), from_name, Enum.take(memory_entries, -limit))

    [entry] =
      absorb_store(
        to_store,
        [
          %{
            type: :observation,
            text: summary,
            meta: %{transfer_from: from_name, agent: agent_id(agent)}
          }
        ],
        "TRANSFER/#{agent_id(agent)}"
      )

    private_file = "#{agent_id(agent)}-experience.md"
    private_path = Path.join([to_dir, "private", private_file])
    write_file!(private_path, summary <> "\n")
    agent = Map.put(agent, "private_doc", private_file)
    {agent, entry, [rel(to_dir, private_path), rel(to_dir, to_store)]}
  end

  defp apply_policy(
         :fresh,
         agent,
         _memory_entries,
         _from_name,
         _to_name,
         to_dir,
         _to_store,
         _limit
       ) do
    private_file = "#{agent_id(agent)}-fresh.md"
    private_path = Path.join([to_dir, "private", private_file])
    write_file!(private_path, fresh_private_doc())
    {Map.put(agent, "private_doc", private_file), nil, [rel(to_dir, private_path)]}
  end

  defp apply_policy(
         :full,
         agent,
         _memory_entries,
         _from_name,
         _to_name,
         to_dir,
         _to_store,
         _limit
       ) do
    IO.puts("機密注意: :full policy は私的メモリを転籍先へそのままコピーします。")
    private_file = "#{agent_id(agent)}-fresh.md"
    private_path = Path.join([to_dir, "private", private_file])
    write_file!(private_path, fresh_private_doc())
    {Map.put(agent, "private_doc", private_file), nil, [rel(to_dir, private_path)]}
  end

  defp write_memory(:distill, _entries, to_memory_path) do
    write_file!(to_memory_path, "")
    [rel(Path.dirname(Path.dirname(to_memory_path)), to_memory_path)]
  end

  defp write_memory(:fresh, _entries, to_memory_path) do
    write_file!(to_memory_path, "")
    [rel(Path.dirname(Path.dirname(to_memory_path)), to_memory_path)]
  end

  defp write_memory(:full, entries, to_memory_path) do
    content = Enum.map_join(entries, "", fn entry -> entry.raw <> "\n" end)
    write_file!(to_memory_path, content)
    [rel(Path.dirname(Path.dirname(to_memory_path)), to_memory_path)]
  end

  defp copy_procedure(agent, from_dir, to_dir) do
    case Map.get(agent, "procedure") do
      nil ->
        []

      procedure ->
        from_path = Path.join(from_dir, procedure)
        to_path = Path.join(to_dir, procedure)

        if File.exists?(from_path) do
          File.mkdir_p!(Path.dirname(to_path))
          File.cp!(from_path, to_path)
          [rel(to_dir, to_path)]
        else
          []
        end
    end
  end

  defp departure_record(from_store_path, agent_id, to_name, policy) do
    if File.exists?(from_store_path) do
      absorb_store(
        from_store_path,
        [%{type: :observation, text: "AGENT #{agent_id} が #{to_name} へ転籍（#{policy}）"}],
        "TRANSFER"
      )

      [Path.basename(from_store_path)]
    else
      []
    end
  end

  defp arrival_record(:distill, _to_store_path, _agent_id, _from_name), do: []

  defp arrival_record(policy, to_store_path, agent_id, from_name) do
    absorb_store(
      to_store_path,
      [
        %{
          type: :observation,
          text: "AGENT #{agent_id} が #{from_name} から転入（#{policy}）",
          meta: %{transfer_from: from_name, agent: agent_id}
        }
      ],
      "TRANSFER"
    )

    [Path.basename(to_store_path)]
  end

  defp experience_summary(agent_id, from_name, entries) do
    bullets =
      entries
      |> Enum.map_join("\n", fn entry -> "- #{truncate(entry.text, 120)}" end)
      |> case do
        "" -> "- （有効な私的メモリなし）"
        text -> text
      end

    "経験サマリ（#{agent_id}, #{from_name} より転籍）:\n#{bullets}"
  end

  defp fresh_private_doc do
    "新任。私的知見はこれから蓄積。\n"
  end

  defp store_entries(path) do
    {:ok, ref} = Reference.start_link(persist_path: path)
    entries = Reference.all(ref)
    GenServer.stop(ref)
    entries
  end

  defp absorb_store(path, entries, author) do
    {:ok, ref} = Reference.start_link(persist_path: path)
    stored = Reference.absorb(ref, entries, author)
    GenServer.stop(ref)
    stored
  end

  defp load_agents(dir) do
    path = Path.join(dir, "agents.json")

    case File.read(path) do
      {:ok, content} ->
        {:ok, Jason.decode!(content)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_agent(agents, agent_id) do
    case Enum.find(agents, &(agent_id(&1) == agent_id)) do
      nil -> {:error, :missing_agent}
      agent -> {:ok, agent}
    end
  end

  defp ensure_absent(agents, agent_id) do
    if Enum.any?(agents, &(agent_id(&1) == agent_id)) do
      {:error, :already_exists}
    else
      :ok
    end
  end

  defp reject_agent(agents, agent_id), do: Enum.reject(agents, &(agent_id(&1) == agent_id))

  defp write_agents!(dir, agents) do
    write_file!(Path.join(dir, "agents.json"), Jason.encode!(agents, pretty: true) <> "\n")
  end

  defp write_file!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp remove_source_memory(path) do
    if File.exists?(path), do: File.rm!(path)
  end

  defp normalize_policy(policy) when policy in @policies, do: policy

  defp normalize_policy(policy) when is_binary(policy) do
    policy
    |> String.trim()
    |> String.to_existing_atom()
    |> normalize_policy()
  rescue
    ArgumentError -> raise ArgumentError, "unknown transfer policy #{inspect(policy)}"
  end

  defp normalize_policy(policy),
    do: raise(ArgumentError, "unknown transfer policy #{inspect(policy)}")

  defp agent_id(agent), do: Map.get(agent, "id", Map.get(agent, :id)) |> to_string()

  defp truncate(text, limit) do
    text = to_string(text)
    if String.length(text) > limit, do: String.slice(text, 0, limit), else: text
  end

  defp rel(root, path), do: Path.relative_to(path, root)
end
