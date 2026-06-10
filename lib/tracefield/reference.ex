defmodule Tracefield.Reference do
  @moduledoc """
  Shared, citable state store for Tracefield entries.
  """

  use GenServer

  defmodule Entry do
    @moduledoc "Reference entry with provenance and retrieval metadata."

    @enforce_keys [:id, :type, :author, :version, :status, :text, :citations, :embedding, :meta]
    defstruct [:id, :type, :author, :version, :status, :text, :citations, :embedding, :meta]
  end

  @types [:belief, :hypothesis, :observation, :stance, :decision, :question, :chunk, :procedure]
  @statuses [:active, :retracted, :superseded]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def absorb(ref, entries, author) when is_list(entries) do
    GenServer.call(ref, {:absorb, entries, author})
  end

  def absorb(ref, entry, author), do: absorb(ref, [entry], author)

  def absorb_idempotent(ref, entries, author) when is_list(entries) do
    GenServer.call(ref, {:absorb_idempotent, entries, author})
  end

  def absorb_idempotent(ref, entry, author), do: absorb_idempotent(ref, [entry], author)

  def serve(ref, query_text, opts \\ []) do
    GenServer.call(ref, {:serve, query_text, opts})
  end

  def retract(ref, id) do
    GenServer.call(ref, {:retract, id})
  end

  def quarantine(ref, ids) do
    GenServer.call(ref, {:quarantine, List.wrap(ids)})
  end

  def most_cited(ref, opts \\ []) do
    GenServer.call(ref, {:most_cited, opts})
  end

  def verify(ref, entries, opts \\ []) do
    all_entries = all(ref)
    by_id = Map.new(all_entries, &{entry_id(&1), &1})

    pairs =
      entries
      |> List.wrap()
      |> Enum.flat_map(fn entry ->
        entry_citations(entry)
        |> Enum.map(fn cited_id ->
          %{
            key: {entry_id(entry), cited_id},
            citing: entry,
            cited: Map.get(by_id, cited_id)
          }
        end)
      end)

    {decided, judge_pairs} =
      Enum.reduce(pairs, {%{}, []}, fn pair, {decided, judge_pairs} ->
        cond do
          is_nil(pair.cited) ->
            {Map.put(decided, pair.key, false), judge_pairs}

          entry_type(pair.cited) == :procedure ->
            {Map.put(decided, pair.key, true), judge_pairs}

          entry_status(pair.cited) != :active ->
            {Map.put(decided, pair.key, false), judge_pairs}

          true ->
            {decided, judge_pairs ++ [pair]}
        end
      end)

    Map.merge(decided, judge_verify(judge_pairs, opts))
  end

  def get(ref, id) do
    GenServer.call(ref, {:get, id})
  end

  def all(ref) do
    GenServer.call(ref, :all)
  end

  def stats(ref) do
    GenServer.call(ref, :stats)
  end

  def closure(entries, id) do
    by_id = Map.new(entries, &{entry_id(&1), &1})

    active_ids =
      MapSet.new(for entry <- entries, entry_status(entry) == :active, do: entry_id(entry))

    reverse = reverse_citation_index(entries)

    id
    |> downstream_ids(reverse, active_ids)
    |> Enum.map(&Map.fetch!(by_id, &1))
  end

  @impl true
  def init(opts) do
    persist_path = Keyword.get(opts, :persist_path)

    state = %{
      entries: [],
      next_id: 1,
      embed_adapter: Keyword.get(opts, :embed_adapter, Tracefield.Embed.Mock),
      embed_model: Keyword.get(opts, :embed_model, "nomic-embed-text"),
      persist_path: persist_path,
      restored: 0,
      skipped_lines: 0
    }

    state = restore_persisted(state, persist_path)
    entries = Keyword.get(opts, :entries, [])

    {:ok, absorb_initial(state, entries)}
  end

  @impl true
  def handle_call({:absorb, entries, author}, _from, state) do
    {stored, state} = build_entries(entries, author, state)
    persist_absorbs!(state, stored)
    {:reply, stored, %{state | entries: state.entries ++ stored}}
  end

  def handle_call({:absorb_idempotent, entries, author}, _from, state) do
    {stored, state} =
      Enum.map_reduce(entries, state, fn entry, state ->
        normalized = normalize_entry(entry, author)

        case find_existing_seed(state.entries, normalized) do
          nil ->
            {[stored], state} = build_entries([entry], author, state)
            persist_absorbs!(state, [stored])
            {stored, %{state | entries: state.entries ++ [stored]}}

          existing ->
            {existing, state}
        end
      end)

    {:reply, stored, state}
  end

  def handle_call({:serve, query_text, opts}, _from, state) do
    k = opts |> Keyword.get(:k, 5) |> max(0)
    exclude_author = Keyword.get(opts, :exclude_author)
    only_author = Keyword.get(opts, :only_author)
    exclude_types = Keyword.get(opts, :exclude_types, [])
    policy = Keyword.get(opts, :policy, :similar)

    entries =
      state.entries
      |> Enum.filter(&(&1.status == :active))
      |> filter_author(:exclude_author, exclude_author)
      |> filter_author(:only_author, only_author)
      |> serve_entries(query_text, k, exclude_types, policy, state)

    {:reply, entries, state}
  end

  def handle_call({:retract, id}, _from, state) do
    closure = closure(state.entries, id)

    entries =
      Enum.map(state.entries, fn
        %Entry{id: ^id} = entry -> %{entry | status: :retracted}
        entry -> entry
      end)

    if Enum.any?(state.entries, &(&1.id == id)) do
      persist_status!(state, id, :retracted)
    end

    {:reply, closure, %{state | entries: entries}}
  end

  def handle_call({:quarantine, ids}, _from, state) do
    ids = MapSet.new(Enum.map(ids, &to_string/1))

    entries =
      Enum.map(state.entries, fn
        %Entry{id: id, status: :active} = entry ->
          if MapSet.member?(ids, id), do: %{entry | status: :superseded}, else: entry

        entry ->
          entry
      end)

    entries
    |> Enum.filter(&(&1.status == :superseded and MapSet.member?(ids, &1.id)))
    |> Enum.each(&persist_status!(state, &1.id, :superseded))

    quarantined = Enum.filter(entries, &MapSet.member?(ids, &1.id))
    {:reply, quarantined, %{state | entries: entries}}
  end

  def handle_call({:most_cited, opts}, _from, state) do
    min_count = Keyword.get(opts, :min_count, 1)

    counts =
      state.entries
      |> Enum.filter(&(&1.status == :active))
      |> Enum.flat_map(& &1.citations)
      |> Enum.frequencies()

    entry =
      state.entries
      |> Enum.filter(&(&1.status == :active))
      |> Enum.reject(&(&1.type in [:chunk, :procedure]))
      |> Enum.map(&{&1, Map.get(counts, &1.id, 0)})
      |> Enum.filter(fn {_entry, count} -> count >= min_count end)
      |> Enum.sort_by(fn {entry, count} -> {-count, entry_number(entry.id)} end)
      |> case do
        [{entry, _count} | _rest] -> entry
        [] -> nil
      end

    {:reply, entry, state}
  end

  def handle_call({:get, id}, _from, state) do
    {:reply, Enum.find(state.entries, &(&1.id == id)), state}
  end

  def handle_call(:all, _from, state) do
    {:reply, state.entries, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       entries: length(state.entries),
       restored: state.restored,
       skipped_lines: state.skipped_lines
     }, state}
  end

  defp absorb_initial(state, entries) do
    Enum.reduce(List.wrap(entries), state, fn entry, acc ->
      author = entry_author(entry) || "seed"
      {stored, acc} = build_entries([entry], author, acc)
      persist_absorbs!(acc, stored)
      %{acc | entries: acc.entries ++ stored}
    end)
  end

  defp build_entries(entries, author, state) do
    normalized = Enum.map(entries, &normalize_entry(&1, author))
    embeddings = embed_all(Enum.map(normalized, & &1.text), state)

    {stored, next_id} =
      normalized
      |> Enum.zip(embeddings)
      |> Enum.map_reduce(state.next_id, fn {entry, embedding}, next_id ->
        stored = %Entry{
          id: "e#{next_id}",
          type: entry.type,
          author: entry.author,
          version: 1,
          status: entry.status,
          text: entry.text,
          citations: entry.citations,
          embedding: embedding,
          meta: entry.meta
        }

        {stored, next_id + 1}
      end)

    {stored, %{state | next_id: next_id}}
  end

  defp normalize_entry(entry, author) do
    %{
      type: normalize_type(entry_value(entry, :type, :belief)),
      author: to_string(entry_author(entry) || author),
      status: normalize_status(entry_value(entry, :status, :active)),
      text: entry_value(entry, :text, "") |> to_string(),
      citations: normalize_citations(entry_value(entry, :citations, [])),
      meta: normalize_meta(entry_value(entry, :meta, %{}))
    }
  end

  defp find_existing_seed(entries, normalized) do
    Enum.find(entries, fn entry ->
      entry.type == normalized.type and entry.author == normalized.author and
        entry.text == normalized.text
    end)
  end

  defp normalize_type(type) when type in @types, do: type

  defp normalize_type(type) when is_binary(type) do
    type
    |> String.trim()
    |> String.to_existing_atom()
    |> normalize_type()
  rescue
    ArgumentError -> :belief
  end

  defp normalize_type(_type), do: :belief

  defp normalize_status(status) when status in @statuses, do: status

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.trim()
    |> String.to_existing_atom()
    |> normalize_status()
  rescue
    ArgumentError -> :active
  end

  defp normalize_status(_status), do: :active

  defp normalize_citations(citations) do
    citations
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) or is_atom(&1) or is_integer(&1)))
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_meta(meta) when is_map(meta) do
    Map.new(meta, fn {key, value} -> {normalize_meta_key(key), value} end)
  end

  defp normalize_meta(_meta), do: %{}

  defp normalize_meta_key(key) when is_atom(key), do: key

  defp normalize_meta_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp normalize_meta_key(key), do: key

  defp restore_persisted(state, nil), do: state

  defp restore_persisted(state, path) do
    if File.exists?(path) do
      path
      |> File.stream!(:line, [])
      |> Enum.reduce(state, &replay_line/2)
      |> then(fn state ->
        %{state | next_id: next_restored_id(state.entries)}
      end)
    else
      state
    end
  end

  defp replay_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"op" => "absorb", "entry" => entry}} when is_map(entry) ->
        case restore_entry(entry) do
          %Entry{} = restored ->
            %{state | entries: state.entries ++ [restored], restored: state.restored + 1}

          nil ->
            %{state | skipped_lines: state.skipped_lines + 1}
        end

      {:ok, %{"op" => "status", "id" => id, "status" => status}} ->
        %{
          state
          | entries: put_entry_status(state.entries, to_string(id), normalize_status(status))
        }

      {:ok, _other} ->
        state

      {:error, _reason} ->
        %{state | skipped_lines: state.skipped_lines + 1}
    end
  end

  defp restore_entry(entry) do
    id = entry_value(entry, :id, nil)

    if is_binary(id) do
      %Entry{
        id: id,
        type: normalize_type(entry_value(entry, :type, :belief)),
        author: entry_value(entry, :author, "seed") |> to_string(),
        version: normalize_version(entry_value(entry, :version, 1)),
        status: normalize_status(entry_value(entry, :status, :active)),
        text: entry_value(entry, :text, "") |> to_string(),
        citations: normalize_citations(entry_value(entry, :citations, [])),
        embedding: normalize_embedding(entry_value(entry, :embedding, [])),
        meta: normalize_meta(entry_value(entry, :meta, %{}))
      }
    end
  end

  defp normalize_version(version) when is_integer(version) and version > 0, do: version
  defp normalize_version(_version), do: 1

  defp normalize_embedding(embedding) when is_list(embedding) do
    Enum.map(embedding, fn
      value when is_number(value) -> value * 1.0
      _value -> 0.0
    end)
  end

  defp normalize_embedding(_embedding), do: []

  defp put_entry_status(entries, id, status) do
    Enum.map(entries, fn
      %Entry{id: ^id} = entry -> %{entry | status: status}
      entry -> entry
    end)
  end

  defp next_restored_id(entries) do
    entries
    |> Enum.map(&entry_number(&1.id))
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp persist_absorbs!(_state, []), do: :ok

  defp persist_absorbs!(state, entries) do
    Enum.each(entries, fn entry ->
      append_persist!(state.persist_path, %{op: "absorb", entry: plain_entry(entry)})
    end)
  end

  defp persist_status!(state, id, status) do
    append_persist!(state.persist_path, %{op: "status", id: id, status: Atom.to_string(status)})
  end

  defp append_persist!(nil, _event), do: :ok

  defp append_persist!(path, event) do
    ensure_persist_file!(path)
    File.write!(path, Jason.encode!(event) <> "\n", [:append])
  end

  defp ensure_persist_file!(path) do
    unless File.exists?(path) do
      dir = Path.dirname(path)
      if dir not in [".", ""], do: File.mkdir_p!(dir)
      File.touch!(path)
      File.chmod!(path, 0o600)
    end
  end

  defp plain_entry(%Entry{} = entry) do
    %{
      id: entry.id,
      type: Atom.to_string(entry.type),
      author: entry.author,
      version: entry.version,
      status: Atom.to_string(entry.status),
      text: entry.text,
      citations: entry.citations,
      embedding: entry.embedding,
      meta: entry.meta
    }
  end

  defp embed_all([], _state), do: []

  defp embed_all(texts, state) do
    case Tracefield.Embed.embed(texts, adapter: state.embed_adapter, model: state.embed_model) do
      {:ok, embeddings} -> embeddings
      {:error, _reason} -> Enum.map(texts, fn _text -> List.duplicate(0.0, 32) end)
    end
  end

  defp embed_one(text, state), do: hd(embed_all([to_string(text)], state))

  defp filter_author(entries, _mode, nil), do: entries

  defp filter_author(entries, :exclude_author, author) do
    author = to_string(author)
    Enum.reject(entries, &(&1.author == author))
  end

  defp filter_author(entries, :only_author, author) do
    author = to_string(author)
    Enum.filter(entries, &(&1.author == author))
  end

  defp filter_types(entries, _mode, []), do: entries
  defp filter_types(entries, _mode, nil), do: entries

  defp filter_types(entries, :exclude_types, types) do
    types = MapSet.new(Enum.map(List.wrap(types), &normalize_type/1))
    Enum.reject(entries, &MapSet.member?(types, &1.type))
  end

  defp serve_entries(entries, query_text, k, exclude_types, :similar, state) do
    query_embedding = embed_one(query_text, state)

    entries
    |> filter_types(:exclude_types, exclude_types)
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      {entry, Tracefield.Embed.cosine(query_embedding, entry.embedding), index}
    end)
    |> Enum.sort_by(fn {_entry, score, index} -> {-score, index} end)
    |> Enum.take(k)
    |> Enum.map(fn {entry, _score, _index} -> entry end)
  end

  defp serve_entries(entries, _query_text, k, exclude_types, :diverse, _state) do
    entries
    |> filter_types(:exclude_types, [:procedure | List.wrap(exclude_types)])
    |> Enum.group_by(& &1.author)
    |> Map.values()
    |> Enum.map(&Enum.sort_by(&1, fn entry -> -entry_number(entry.id) end))
    |> Enum.sort_by(fn [entry | _rest] -> -entry_number(entry.id) end)
    |> round_robin()
    |> Enum.take(k)
  end

  defp serve_entries(_entries, _query_text, _k, _exclude_types, other, _state) do
    raise ArgumentError, "unknown serve policy #{inspect(other)}"
  end

  defp round_robin(groups), do: do_round_robin(groups, [])

  defp do_round_robin([], acc), do: acc

  defp do_round_robin(groups, acc) do
    {heads, tails} =
      Enum.reduce(groups, {[], []}, fn
        [head | tail], {heads, tails} ->
          {[head | heads], if(tail == [], do: tails, else: [tail | tails])}

        [], {heads, tails} ->
          {heads, tails}
      end)

    do_round_robin(Enum.reverse(tails), acc ++ Enum.reverse(heads))
  end

  defp entry_number("e" <> number) do
    case Integer.parse(number) do
      {value, ""} -> value
      _ -> 0
    end
  end

  defp entry_number(_id), do: 0

  defp reverse_citation_index(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      Enum.reduce(entry_citations(entry), acc, fn citation, acc ->
        Map.update(acc, citation, [entry_id(entry)], &[entry_id(entry) | &1])
      end)
    end)
  end

  defp downstream_ids(id, reverse, active_ids) do
    do_downstream_ids([id], reverse, active_ids, MapSet.new())
  end

  defp do_downstream_ids([], _reverse, _active_ids, seen), do: MapSet.to_list(seen)

  defp do_downstream_ids([id | rest], reverse, active_ids, seen) do
    next =
      reverse
      |> Map.get(id, [])
      |> Enum.filter(&MapSet.member?(active_ids, &1))
      |> Enum.reject(&MapSet.member?(seen, &1))

    do_downstream_ids(
      rest ++ next,
      reverse,
      active_ids,
      Enum.reduce(next, seen, &MapSet.put(&2, &1))
    )
  end

  defp entry_value(%{} = entry, key, default) do
    Map.get(entry, key, Map.get(entry, to_string(key), default))
  end

  defp entry_value(_entry, _key, default), do: default

  defp entry_id(entry), do: entry_value(entry, :id, nil)
  defp entry_author(entry), do: entry_value(entry, :author, nil)
  defp entry_type(entry), do: entry_value(entry, :type, nil)
  defp entry_status(entry), do: entry_value(entry, :status, nil)
  defp entry_citations(entry), do: entry_value(entry, :citations, [])

  defp entry_text(entry), do: entry_value(entry, :text, "")

  defp judge_verify([], _opts), do: %{}

  defp judge_verify(pairs, opts) do
    numbered =
      pairs
      |> Enum.with_index(1)
      |> Enum.map(fn {pair, index} ->
        %{
          "n" => index,
          "citing_id" => elem(pair.key, 0),
          "cited_id" => elem(pair.key, 1),
          "citing" => entry_text(pair.citing),
          "cited" => entry_text(pair.cited)
        }
      end)

    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_VERIFY\nReturn only JSON like {\"1\":{\"verified\":true}}. Judge whether each cited text grounds the citing claim."
      },
      %{
        role: "user",
        content: "PAIRS_JSON:\n#{Jason.encode!(numbered)}"
      }
    ]

    llm_opts =
      [
        adapter:
          Keyword.get(opts, :judge_adapter, Keyword.get(opts, :adapter, Tracefield.LLM.Mock)),
        model: Keyword.get(opts, :judge_model, Keyword.get(opts, :model, "mock")),
        temperature: Keyword.get(opts, :temperature, 0.0),
        seed: Keyword.get(opts, :seed, 0),
        cli: Keyword.get(opts, :cli)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    judgments =
      case Tracefield.LLM.complete(messages, llm_opts) do
        {:ok, content} -> parse_verify_response(content)
        {:error, _reason} -> %{}
      end

    pairs
    |> Enum.with_index(1)
    |> Map.new(fn {pair, index} ->
      value = Map.get(judgments, Integer.to_string(index), Map.get(judgments, index))
      {pair.key, verified?(value)}
    end)
  end

  defp parse_verify_response(content) when is_binary(content) do
    with {:ok, decoded} <- decode_json_object(content),
         true <- is_map(decoded) do
      decoded
    else
      _ -> %{}
    end
  end

  defp parse_verify_response(_content), do: %{}

  defp decode_json_object(content) do
    with {:error, _reason} <- Jason.decode(content),
         {:ok, object_text} <- extract_object_text(content) do
      Jason.decode(object_text)
    end
  end

  defp extract_object_text(content) do
    start = :binary.match(content, "{")
    finish = content |> String.reverse() |> :binary.match("}")

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

  defp verified?(%{"verified" => value}), do: verified?(value)
  defp verified?(%{verified: value}), do: verified?(value)
  defp verified?(true), do: true
  defp verified?("true"), do: true
  defp verified?(_value), do: false
end
