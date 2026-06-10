defmodule Tracefield.GenesisTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Tracefield.Culture
  alias Tracefield.Genesis
  alias Tracefield.Meta
  alias Tracefield.Reference

  test "detect finds a cross-cluster unclaimed attractor" do
    {:ok, meta} = Reference.start_link()

    publish_entries(meta, "OPS", [
      "resilience mesh offline handoff clinic queue coherent protocol",
      "resilience mesh offline handoff clinic queue staff escalation",
      "resilience mesh offline handoff clinic queue state record"
    ])

    publish_entries(meta, "CARE", [
      "resilience mesh offline handoff clinic queue continuity",
      "resilience mesh offline handoff clinic queue triage"
    ])

    attractors = Genesis.detect(meta, [%{name: "FIN", text: "green loan insulation rebate"}])

    assert [%{} = attractor] = attractors
    assert length(attractor.members) == 5
    assert attractor.source_clusters == ["CARE", "OPS"]
    assert attractor.max_charter_sim < 0.75
    assert attractor.charter_best == "FIN"
  end

  test "detect excludes single-cluster, claimed, and undersized groups" do
    {:ok, single_cluster} = Reference.start_link()

    publish_entries(single_cluster, "OPS", [
      "resilience mesh offline handoff clinic queue one",
      "resilience mesh offline handoff clinic queue two",
      "resilience mesh offline handoff clinic queue three",
      "resilience mesh offline handoff clinic queue four"
    ])

    assert Genesis.detect(single_cluster, [%{name: "FIN", text: "green loan insulation rebate"}]) ==
             []

    {:ok, claimed} = Reference.start_link()

    publish_entries(claimed, "FIN", [
      "green loan insulation rebate risk finance one",
      "green loan insulation rebate risk finance two"
    ])

    publish_entries(claimed, "ENERGY", [
      "green loan insulation rebate risk finance three",
      "green loan insulation rebate risk finance four"
    ])

    assert Genesis.detect(claimed, [
             %{name: "FIN", text: "green loan insulation rebate risk finance"}
           ]) ==
             []

    {:ok, undersized} = Reference.start_link()

    publish_entries(undersized, "OPS", [
      "resilience mesh offline handoff clinic queue one",
      "resilience mesh offline handoff clinic queue two"
    ])

    publish_entries(undersized, "CARE", [
      "resilience mesh offline handoff clinic queue three"
    ])

    assert Genesis.detect(undersized, [%{name: "FIN", text: "green loan insulation rebate"}]) ==
             []
  end

  test "propose absorbs a genesis entry with all member citations" do
    {:ok, meta} = Reference.start_link()
    attractor = seed_attractor(meta)

    genesis = Genesis.propose(meta, attractor)

    assert genesis.type == :genesis
    assert genesis.author == "GENESIS"
    assert genesis.citations == Enum.map(attractor.members, & &1.id)
    assert genesis.text =~ "析出提案: CARE,OPS由来の5件"
    assert Reference.get(meta, genesis.id) == genesis
  end

  test "scaffold writes files, source-cluster lenses, private docs, and seeded provenance" do
    {:ok, meta} = Reference.start_link()
    attractor = seed_attractor(meta)
    genesis = Genesis.propose(meta, attractor)
    dir = tmp_dir()

    result = Genesis.scaffold(meta, genesis.id, dir)

    assert result.seeded == 5
    assert "task.md" in result.files
    assert "agents.json" in result.files
    assert "procedure.md" in result.files
    assert "private/CARE.md" in result.files
    assert "private/OPS.md" in result.files
    assert "private/general.md" in result.files
    assert "store.jsonl" in result.files

    agents = dir |> Path.join("agents.json") |> File.read!() |> Jason.decode!()
    assert Enum.map(agents, & &1["id"]) == ["CARE_LENS", "OPS_LENS", "GENERAL"]
    assert Enum.map(agents, & &1["private_doc"]) == ["CARE.md", "OPS.md", "general.md"]

    care_doc = File.read!(Path.join([dir, "private", "CARE.md"]))
    ops_doc = File.read!(Path.join([dir, "private", "OPS.md"]))
    assert care_doc =~ "continuity"
    refute care_doc =~ "state record"
    assert ops_doc =~ "state record"
    refute ops_doc =~ "continuity"

    {:ok, seeded} = Reference.start_link(persist_path: Path.join(dir, "store.jsonl"))
    entries = Reference.all(seeded)
    assert length(entries) == 5
    assert Enum.all?(entries, &(&1.meta.source_cluster == "META"))
    assert Enum.all?(entries, &(hd(&1.meta.source_chain).source_cluster in ["CARE", "OPS"]))
  end

  test "Culture.transmission reports alignment, per-author alignment, and member diversity" do
    {:ok, aligned_ref} = Reference.start_link()

    Reference.absorb(
      aligned_ref,
      [
        %{type: :belief, text: "resilience mesh offline handoff clinic queue protocol"},
        %{type: :decision, text: "resilience mesh offline handoff clinic queue decision"}
      ],
      "OPS_LENS"
    )

    Reference.absorb(
      aligned_ref,
      [%{type: :belief, text: "resilience mesh offline handoff clinic queue continuity"}],
      "CARE_LENS"
    )

    Reference.absorb(
      aligned_ref,
      [
        %{type: :chunk, text: "resilience mesh offline handoff clinic queue chunk"},
        %{type: :procedure, text: "resilience mesh offline handoff clinic queue procedure"},
        %{type: :genesis, text: "resilience mesh offline handoff clinic queue genesis"}
      ],
      "SYSTEM"
    )

    high = Culture.transmission(aligned_ref, "resilience mesh offline handoff clinic queue")

    {:ok, unrelated_ref} = Reference.start_link()

    Reference.absorb(
      unrelated_ref,
      [
        %{type: :belief, text: "orchid catalog shipping labels"},
        %{type: :decision, text: "museum ticket lighting schedule"}
      ],
      "NOISE"
    )

    low = Culture.transmission(unrelated_ref, "resilience mesh offline handoff clinic queue")

    assert high.n == 3
    assert high.alignment > low.alignment
    assert Map.keys(high.per_author) |> Enum.sort() == ["CARE_LENS", "OPS_LENS"]
    assert high.member_diversity > 0.0
  end

  test "genesis demo prints detection, exclusion reasons, birth certificate, scaffold, and transmission" do
    Mix.Task.reenable("tracefield.genesis")

    output =
      capture_io(fn ->
        Mix.Tasks.Tracefield.Genesis.run(["--demo"])
      end)

    assert output =~ "tracefield.genesis demo"
    assert output =~ "2. detect: 1 attractor"
    assert output =~ "excluded claimed group"
    assert output =~ "excluded noise group"
    assert output =~ "3. birth certificate"
    assert output =~ "citations="
    assert output =~ "4. scaffold"
    assert output =~ "task.md head"
    assert output =~ "agents.json"
    assert output =~ "5. Culture.transmission"
    assert output =~ "member_diversity="
  end

  defp seed_attractor(meta) do
    publish_entries(meta, "OPS", [
      "resilience mesh offline handoff clinic queue coherent protocol",
      "resilience mesh offline handoff clinic queue staff escalation",
      "resilience mesh offline handoff clinic queue state record"
    ])

    publish_entries(meta, "CARE", [
      "resilience mesh offline handoff clinic queue continuity",
      "resilience mesh offline handoff clinic queue triage"
    ])

    [attractor] = Genesis.detect(meta, [%{name: "FIN", text: "green loan insulation rebate"}])
    attractor
  end

  defp publish_entries(meta, cluster, texts) do
    {:ok, source} = Reference.start_link()

    entries = Enum.map(texts, &%{type: :belief, text: &1})
    stored = Reference.absorb(source, entries, cluster)

    Meta.publish(meta, cluster, source, ids: Enum.map(stored, & &1.id))
  end

  defp tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "tracefield-genesis-test-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
