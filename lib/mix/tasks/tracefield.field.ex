defmodule Mix.Tasks.Tracefield.Field do
  @moduledoc "Run a live Tracefield Field demo."
  use Mix.Task

  alias Tracefield.Field
  alias Tracefield.Meta
  alias Tracefield.Reference

  @shortdoc "Run the live field demo"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["--demo"] -> run_demo()
      _other -> Mix.raise("pass --demo")
    end
  end

  defp run_demo do
    base = Path.join(System.tmp_dir!(), "tracefield-field-#{System.unique_integer([:positive])}")
    a_store = Path.join(base, "A.jsonl")
    b_store = Path.join(base, "B.jsonl")
    meta_store = Path.join(base, "META.jsonl")

    {:ok, field} =
      Field.start_link(
        clusters: [
          %{name: "A", persist_path: a_store},
          %{name: "B", persist_path: b_store}
        ],
        meta: meta_store,
        links: :auto
      )

    refs = Field.refs(field)
    links = Field.links(field)
    a = Map.fetch!(refs, "A")
    b = Map.fetch!(refs, "B")
    meta = Map.fetch!(refs, "META")

    Mix.shell().info("tracefield.field demo")
    Mix.shell().info("1. Field started: A=#{inspect(a)} B=#{inspect(b)} META=#{inspect(meta)}")

    [a1] =
      Reference.absorb(
        a,
        [
          %{
            type: :observation,
            text: "solar insulation rebate evidence supports low-risk green loan",
            meta: %{label: "a1"}
          }
        ],
        "ENERGY"
      )

    [meta_copy] = Meta.publish(meta, "A", a, ids: [a1.id])
    Mix.shell().info("2. A absorbed a1=#{a1.id}; published to META copy=#{meta_copy.id}")

    [found | _rest] =
      Meta.discover(meta, "green loan insulation rebate evidence", exclude_cluster: "B")

    [b_copy] = Meta.pull(b, meta, [found.entry.id])

    Mix.shell().info(
      "3. B discovered source=#{found.source_cluster}/#{found.source_id}; pulled copy=#{b_copy.id}"
    )

    [b1] =
      Reference.absorb(
        b,
        [
          %{
            type: :decision,
            text: "approve the green loan pilot because imported evidence grounds the risk",
            citations: [b_copy.id],
            meta: %{label: "b1"}
          }
        ],
        "FINANCE"
      )

    Mix.shell().info("4. B absorbed decision b1=#{b1.id} citing copy=#{b_copy.id}")

    Reference.retract(a, a1.id)

    await_history(Map.fetch!(links, {"A", "META"}), fn history ->
      Enum.any?(history, &(&1.source_id == a1.id))
    end)

    await_history(Map.fetch!(links, {"META", "B"}), fn history ->
      Enum.any?(history, &(&1.source_id == meta_copy.id and &1.copy_id == b_copy.id))
    end)

    Mix.shell().info("5. A retracted a1; links automatically propagated A -> META -> B")
    Mix.shell().info("6. Final B store")
    print_store_state(Reference.all(b))
    Mix.shell().info("source_chain: #{format_source_chain(Reference.get(b, b_copy.id).meta)}")
  end

  defp await_history(link, predicate, attempts \\ 50)

  defp await_history(_link, _predicate, 0), do: Mix.raise("timed out waiting for link history")

  defp await_history(link, predicate, attempts) do
    history = Tracefield.Bridge.Link.history(link)

    if predicate.(history) do
      history
    else
      Process.sleep(20)
      await_history(link, predicate, attempts - 1)
    end
  end

  defp print_store_state(entries) do
    Enum.each(entries, fn entry ->
      Mix.shell().info(
        "#{entry.id} status=#{entry.status} author=#{entry.author} cites=#{format_list(entry.citations)} text=#{entry.text}"
      )
    end)
  end

  defp format_source_chain(meta) do
    chain = Map.get(meta, :source_chain, [])

    final = %{
      source_cluster: Map.get(meta, :source_cluster),
      source_id: Map.get(meta, :source_id)
    }

    (chain ++ [final])
    |> Enum.map_join(" -> ", fn hop -> "#{hop.source_cluster}/#{hop.source_id}" end)
  end

  defp format_list([]), do: "-"
  defp format_list(values), do: Enum.map_join(values, ",", &to_string/1)
end
