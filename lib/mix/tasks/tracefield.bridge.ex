defmodule Mix.Tasks.Tracefield.Bridge do
  @moduledoc "Bridge Tracefield Reference stores across clusters."
  use Mix.Task

  alias Tracefield.Reference

  @shortdoc "Export/import entries and propagate cross-cluster retractions"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    args
    |> parse_args()
    |> run_bridge()
  end

  defp parse_args(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          from_store: :string,
          to_store: :string,
          source_name: :string,
          export: :string,
          sync: :boolean,
          demo: :boolean
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    opts
  end

  defp run_bridge(opts) do
    if Keyword.get(opts, :demo) do
      run_demo()
    else
      run_store_bridge(opts)
    end
  end

  defp run_store_bridge(opts) do
    from_store = required!(opts, :from_store)
    to_store = required!(opts, :to_store)
    source_name = required!(opts, :source_name)

    {:ok, from} = Reference.start_link(persist_path: from_store)
    {:ok, to} = Reference.start_link(persist_path: to_store)

    cond do
      Keyword.get(opts, :sync, false) ->
        ids = export_ids(opts, from)
        source_entries = Reference.export(from, ids)
        results = Reference.propagate_retractions(to, source_name, source_entries)
        print_sync_results(results)

      Keyword.has_key?(opts, :export) ->
        exported = Reference.export(from, export_ids(opts, from))
        copies = Reference.import(to, exported, source_name)
        print_import_results(copies)

      true ->
        Mix.raise("pass --export ids or --sync")
    end
  end

  defp run_demo do
    base = Path.join(System.tmp_dir!(), "tracefield-bridge-#{System.unique_integer([:positive])}")
    a_store = Path.join(base, "A.jsonl")
    b_store = Path.join(base, "B.jsonl")

    {:ok, a} = Reference.start_link(persist_path: a_store)
    {:ok, b} = Reference.start_link(persist_path: b_store)

    Mix.shell().info("tracefield.bridge demo")
    Mix.shell().info("stores: A=#{a_store} B=#{b_store}")
    Mix.shell().info("")

    Mix.shell().info("1. クラスタA: 知見 a1 を absorb")

    [a1] =
      Reference.absorb(
        a,
        [
          %{
            type: :observation,
            text: "省エネ優遇は実測データで担保できる(evidence)",
            meta: %{label: "a1"}
          }
        ],
        "ENERGY"
      )

    Mix.shell().info("   a1=#{a1.id} #{a1.text}")

    Mix.shell().info("2. bridge: a1 を B へ輸出入")
    [copy] = Reference.import(b, Reference.export(a, [a1.id]), "A")
    Mix.shell().info("   b-copy=#{copy.id} source=A/#{a1.id} author=#{copy.author}")

    Mix.shell().info("3. クラスタB: 判断 b1 を b-copy citation で absorb")

    [b1] =
      Reference.absorb(
        b,
        [
          %{
            type: :decision,
            text: "優遇ローン商品を設計する",
            citations: [copy.id],
            meta: %{label: "b1"}
          }
        ],
        "FINANCE"
      )

    Mix.shell().info("   b1=#{b1.id} cites=#{Enum.join(b1.citations, ",")}")

    Mix.shell().info("4. クラスタA: a1 を retract")
    Reference.retract(a, a1.id)
    Mix.shell().info("   理由: 実測データに誤りが判明")

    Mix.shell().info("5. --sync 相当: B で写しを撤回し、依存判断を閉包隔離")
    results = Reference.propagate_retractions(b, "A", Reference.export(a, [a1.id]))
    print_sync_results(results)

    Mix.shell().info("")
    Mix.shell().info("final B store state")
    print_store_state(Reference.all(b))
  end

  defp required!(opts, key) do
    Keyword.get(opts, key) ||
      Mix.raise("missing required --#{String.replace(to_string(key), "_", "-")}")
  end

  defp export_ids(opts, from) do
    case Keyword.get(opts, :export) do
      nil ->
        from
        |> Reference.all()
        |> Enum.map(& &1.id)

      ids ->
        ids
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  defp print_import_results(copies) do
    Mix.shell().info("copies: #{length(copies)}")

    Enum.each(copies, fn copy ->
      source_id = meta_value(copy.meta, :source_id)
      unresolved = Map.get(copy.meta, :unresolved_citations, [])
      Mix.shell().info("copy: #{source_id} -> #{copy.id}")
      Mix.shell().info("  citations: #{format_list(copy.citations)}")
      Mix.shell().info("  unresolved: #{format_list(unresolved)}")
    end)
  end

  defp print_sync_results([]), do: Mix.shell().info("越境撤回: なし")

  defp print_sync_results(results) do
    Enum.each(results, fn result ->
      Mix.shell().info(
        "越境撤回: #{result.source_id} → 写し #{result.copy.id} を撤回、依存 #{length(result.closure)} 件隔離"
      )
    end)
  end

  defp print_store_state(entries) do
    Enum.each(entries, fn entry ->
      Mix.shell().info(
        "#{entry.id} status=#{entry.status} author=#{entry.author} cites=#{format_list(entry.citations)} text=#{entry.text}"
      )
    end)
  end

  defp format_list([]), do: "-"
  defp format_list(values), do: Enum.map_join(values, ",", &to_string/1)

  defp meta_value(meta, key) when is_map(meta) do
    value = Map.get(meta, key, Map.get(meta, to_string(key)))
    if is_nil(value), do: nil, else: to_string(value)
  end
end
