defmodule Mix.Tasks.Tracefield.Genesis do
  @moduledoc "Detect, propose, and scaffold Tracefield genesis clusters."
  use Mix.Task

  alias Tracefield.Culture
  alias Tracefield.Genesis
  alias Tracefield.Meta
  alias Tracefield.Reference

  @shortdoc "Run genesis attractor detection and scaffolding"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    args
    |> parse_args()
    |> run_genesis()
  end

  defp parse_args(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          meta: :string,
          charter: :string,
          detect: :boolean,
          propose: :integer,
          scaffold: :string,
          dir: :string,
          demo: :boolean,
          tau_genesis: :float,
          tau_claim: :float,
          min_size: :integer
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    opts
  end

  defp run_genesis(opts) do
    if Keyword.get(opts, :demo) do
      run_demo()
    else
      run_store_command(opts)
    end
  end

  defp run_store_command(opts) do
    meta_path = required!(opts, :meta)
    {:ok, meta_ref} = Reference.start_link(persist_path: meta_path)

    cond do
      Keyword.get(opts, :detect, false) ->
        detect_and_print(meta_ref, opts)

      Keyword.has_key?(opts, :propose) ->
        attractors = Genesis.detect(meta_ref, charters(opts), detect_opts(opts))
        index = Keyword.fetch!(opts, :propose)

        attractor =
          Enum.at(attractors, index - 1) || Mix.raise("unknown attractor index #{index}")

        genesis = Genesis.propose(meta_ref, attractor)
        Mix.shell().info("genesis: #{genesis.id}")
        Mix.shell().info("citations: #{format_list(genesis.citations)}")

      Keyword.has_key?(opts, :scaffold) ->
        dir = required!(opts, :dir)

        result =
          Genesis.scaffold(meta_ref, Keyword.fetch!(opts, :scaffold), dir, detect_opts(opts))

        print_scaffold(result)

      true ->
        Mix.raise("pass --detect, --propose INDEX, --scaffold ID --dir PATH, or --demo")
    end
  end

  defp detect_and_print(meta_ref, opts) do
    attractors = Genesis.detect(meta_ref, charters(opts), detect_opts(opts))
    Mix.shell().info("attractors: #{length(attractors)}")

    attractors
    |> Enum.with_index(1)
    |> Enum.each(fn {attractor, index} ->
      Mix.shell().info(
        "#{index}. members=#{length(attractor.members)} source_clusters=#{format_list(attractor.source_clusters)} max_charter_sim=#{format_float(attractor.max_charter_sim)} charter_best=#{attractor.charter_best || "-"}"
      )
    end)
  end

  defp run_demo do
    base =
      Path.join(System.tmp_dir!(), "tracefield-genesis-#{System.unique_integer([:positive])}")

    meta_store = Path.join(base, "META.jsonl")
    scaffold_dir = Path.join(base, "new-cluster")
    {:ok, meta} = Reference.start_link(persist_path: meta_store)

    charter_text = "green loan insulation rebate risk finance"
    charter = %{name: "FINANCE", text: charter_text}

    Mix.shell().info("tracefield.genesis demo")
    Mix.shell().info("META=#{meta_store}")
    seed_demo_meta(meta)

    Mix.shell().info("1. seeded META: attractor=5, claimed=4, noise=3")
    attractors = Genesis.detect(meta, [charter], tau_genesis: 0.7, tau_claim: 0.75, min_size: 4)
    Mix.shell().info("2. detect: #{length(attractors)} attractor(s)")
    Mix.shell().info("   excluded claimed group: charter similarity >= 0.75")
    Mix.shell().info("   excluded noise group: min_size/source_cluster conditions not met")
    print_demo_attractors(attractors)

    [attractor] = attractors
    genesis = Genesis.propose(meta, attractor)
    Mix.shell().info("3. birth certificate")
    Mix.shell().info("   genesis=#{genesis.id}")
    Mix.shell().info("   citations=#{format_list(genesis.citations)}")
    Mix.shell().info("   text=#{genesis.text}")

    result = Genesis.scaffold(meta, genesis.id, scaffold_dir)
    Mix.shell().info("4. scaffold")
    print_tree(result)
    print_file_head(Path.join(scaffold_dir, "task.md"), "task.md head", 8)
    Mix.shell().info("agents.json")
    Mix.shell().info(File.read!(Path.join(scaffold_dir, "agents.json")) |> String.trim_trailing())

    store_path = Path.join(scaffold_dir, "store.jsonl")
    {:ok, new_ref} = Reference.start_link(persist_path: store_path)

    lens_authors =
      result.dir
      |> Path.join("agents.json")
      |> File.read!()
      |> Jason.decode!()
      |> Enum.reject(&(&1["id"] == "GENERAL"))
      |> Enum.map(& &1["id"])

    Enum.each(lens_authors, fn author ->
      Reference.absorb(
        new_ref,
        [
          %{type: :belief, text: "resilience mesh offline handoff keeps clinic queue coherent"},
          %{type: :belief, text: "unrelated archive taxonomy for stationery invoices"}
        ],
        author
      )
    end)

    Mix.shell().info("5. Culture.transmission")

    transmission =
      Culture.transmission(new_ref, "resilience mesh offline handoff clinic queue")

    Mix.shell().info("   alignment=#{format_float(transmission.alignment)}")
    Mix.shell().info("   per_author=#{inspect_float_map(transmission.per_author)}")
    Mix.shell().info("   member_diversity=#{format_float(transmission.member_diversity)}")
    Mix.shell().info("   n=#{transmission.n}")
  end

  defp seed_demo_meta(meta) do
    publish_entries(meta, "OPS", [
      "resilience mesh offline handoff clinic queue coherent protocol",
      "resilience mesh offline handoff clinic queue staff escalation",
      "resilience mesh offline handoff clinic queue state record"
    ])

    publish_entries(meta, "CARE", [
      "resilience mesh offline handoff clinic queue continuity",
      "resilience mesh offline handoff clinic queue triage"
    ])

    publish_entries(meta, "FIN", [
      "green loan insulation rebate risk finance",
      "insulation rebate finance lowers green loan risk"
    ])

    publish_entries(meta, "ENERGY", [
      "green loan rebate insulation finance risk",
      "finance risk for green loan insulation rebate"
    ])

    publish_entries(meta, "NOISE", [
      "orchid catalog shipping labels",
      "museum ticket lighting schedule",
      "compiler cache window checksum"
    ])
  end

  defp publish_entries(meta, cluster, texts) do
    {:ok, source} = Reference.start_link()

    entries =
      Enum.map(texts, fn text ->
        %{type: :belief, text: text}
      end)

    stored = Reference.absorb(source, entries, cluster)
    Meta.publish(meta, cluster, source, ids: Enum.map(stored, & &1.id))
  end

  defp print_demo_attractors(attractors) do
    Enum.each(attractors, fn attractor ->
      Mix.shell().info(
        "   attractor members=#{length(attractor.members)} source_clusters=#{format_list(attractor.source_clusters)} max_charter_sim=#{format_float(attractor.max_charter_sim)}"
      )
    end)
  end

  defp print_scaffold(result) do
    Mix.shell().info("dir: #{result.dir}")
    Mix.shell().info("seeded: #{result.seeded}")
    Enum.each(result.files, &Mix.shell().info("file: #{&1}"))
  end

  defp print_tree(result) do
    Mix.shell().info("   dir=#{result.dir}")
    Mix.shell().info("   seeded=#{result.seeded}")
    Enum.each(result.files, &Mix.shell().info("   #{&1}"))
  end

  defp print_file_head(path, label, lines) do
    head =
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.take(lines)
      |> Enum.join("\n")

    Mix.shell().info(label)
    Mix.shell().info(head)
  end

  defp charters(opts) do
    opts
    |> Keyword.get_values(:charter)
    |> Enum.map(fn spec ->
      case String.split(spec, "=", parts: 2) do
        [name, path] -> %{name: name, text: File.read!(path)}
        _other -> Mix.raise("charter must be NAME=path")
      end
    end)
  end

  defp detect_opts(opts) do
    opts
    |> Keyword.take([:tau_genesis, :tau_claim, :min_size])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp required!(opts, key) do
    Keyword.get(opts, key) ||
      Mix.raise("missing required --#{String.replace(to_string(key), "_", "-")}")
  end

  defp format_list([]), do: "-"
  defp format_list(values), do: Enum.map_join(values, ",", &to_string/1)

  defp format_float(value), do: :erlang.float_to_binary(value * 1.0, decimals: 3)

  defp inspect_float_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{format_float(value)}" end)
    |> then(&"%{#{&1}}")
  end
end
