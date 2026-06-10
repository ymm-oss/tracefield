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

  @types [:belief, :hypothesis, :observation, :stance, :decision, :question, :chunk]
  @statuses [:active, :retracted, :superseded]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def absorb(ref, entries, author) when is_list(entries) do
    GenServer.call(ref, {:absorb, entries, author})
  end

  def absorb(ref, entry, author), do: absorb(ref, [entry], author)

  def serve(ref, query_text, opts \\ []) do
    GenServer.call(ref, {:serve, query_text, opts})
  end

  def retract(ref, id) do
    GenServer.call(ref, {:retract, id})
  end

  def get(ref, id) do
    GenServer.call(ref, {:get, id})
  end

  def all(ref) do
    GenServer.call(ref, :all)
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
    state = %{
      entries: [],
      next_id: 1,
      embed_adapter: Keyword.get(opts, :embed_adapter, Tracefield.Embed.Mock),
      embed_model: Keyword.get(opts, :embed_model, "nomic-embed-text")
    }

    entries = Keyword.get(opts, :entries, [])

    {:ok, absorb_initial(state, entries)}
  end

  @impl true
  def handle_call({:absorb, entries, author}, _from, state) do
    {stored, state} = build_entries(entries, author, state)
    {:reply, stored, %{state | entries: state.entries ++ stored}}
  end

  def handle_call({:serve, query_text, opts}, _from, state) do
    k = opts |> Keyword.get(:k, 5) |> max(0)
    exclude_author = Keyword.get(opts, :exclude_author)
    only_author = Keyword.get(opts, :only_author)
    query_embedding = embed_one(query_text, state)

    entries =
      state.entries
      |> Enum.filter(&(&1.status == :active))
      |> filter_author(:exclude_author, exclude_author)
      |> filter_author(:only_author, only_author)
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} ->
        {entry, Tracefield.Embed.cosine(query_embedding, entry.embedding), index}
      end)
      |> Enum.sort_by(fn {_entry, score, index} -> {-score, index} end)
      |> Enum.take(k)
      |> Enum.map(fn {entry, _score, _index} -> entry end)

    {:reply, entries, state}
  end

  def handle_call({:retract, id}, _from, state) do
    closure = closure(state.entries, id)

    entries =
      Enum.map(state.entries, fn
        %Entry{id: ^id} = entry -> %{entry | status: :retracted}
        entry -> entry
      end)

    {:reply, closure, %{state | entries: entries}}
  end

  def handle_call({:get, id}, _from, state) do
    {:reply, Enum.find(state.entries, &(&1.id == id)), state}
  end

  def handle_call(:all, _from, state) do
    {:reply, state.entries, state}
  end

  defp absorb_initial(state, entries) do
    Enum.reduce(List.wrap(entries), state, fn entry, acc ->
      author = entry_author(entry) || "seed"
      {stored, acc} = build_entries([entry], author, acc)
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

  defp normalize_meta(meta) when is_map(meta), do: meta
  defp normalize_meta(_meta), do: %{}

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
  defp entry_status(entry), do: entry_value(entry, :status, nil)
  defp entry_citations(entry), do: entry_value(entry, :citations, [])
end
