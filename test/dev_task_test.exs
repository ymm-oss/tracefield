defmodule Mix.Tasks.Tracefield.DevTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Dev
  alias Tracefield.Reference

  test "load_actors! reads actors.json with kind/turn defaults and human without private_doc" do
    dir = tmp_issue_dir()

    File.write!(
      Path.join(dir, "actors.json"),
      Jason.encode!([
        %{id: "ARCH", domain: "architecture", desc: "architect", private_doc: "arch.md"},
        %{id: "CLI", domain: "implementation", desc: "cli", kind: "cli", turn: "async"},
        %{id: "HUMAN", domain: "review", desc: "reviewer", kind: "human"}
      ])
    )

    File.mkdir_p!(Path.join(dir, "private"))
    File.write!(Path.join([dir, "private", "arch.md"]), "private architecture note")

    assert [arch, cli, human] = Dev.load_actors!(dir)
    assert arch.kind == :llm
    assert arch.turn == :blocking
    assert arch.private_doc == "private architecture note"
    assert cli.kind == :cli
    assert cli.turn == :async
    assert human.kind == :human
    assert human.turn == :blocking
    assert human.private_doc == ""
  end

  test "load_actors! falls back to agents.json" do
    dir = tmp_issue_dir()
    File.write!(Path.join(dir, "agents.json"), Jason.encode!([human_actor()]))

    assert [%{id: "HUMAN", kind: :human}] = Dev.load_actors!(dir)
  end

  test "refine pipeline resumes through answer loop, approval, provenance, and persisted store" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    first = Dev.run_dev(issue: dir, adapter: "mock")

    assert first.state["status"] == "awaiting_human"
    assert File.exists?(Path.join(dir, "store.jsonl"))
    pending = Path.join([dir, "pending", "HUMAN-refine.md"])
    assert File.read!(pending) =~ "REFINE手続き"
    assert File.read!(pending) =~ "## RESPONSE（この下に回答を書いてください）"

    assert Enum.any?(first.entries, &(&1.type == :requirement))
    assert Enum.any?(first.entries, &(&1.type == :question))
    question = Enum.find(first.entries, &(&1.type == :question))

    append_response!(pending, "- 範囲はCLIタスクまでです [#{question.id}]\n")
    second = Dev.run_dev(issue: dir, adapter: "mock")

    assert second.state["status"] == "awaiting_human"

    assert Enum.any?(second.entries, fn entry ->
             entry.type == :answer and question.id in entry.citations
           end)

    assert File.exists?(pending)
    assert File.exists?(Path.join([dir, "pending", "done", "HUMAN-refine.md"]))

    assert Enum.count(second.entries, &(&1.type == :requirement)) >
             Enum.count(first.entries, &(&1.type == :requirement))

    append_response!(pending, "APPROVE\n")
    third = Dev.run_dev(issue: dir, adapter: "mock")

    assert third.state["status"] == "done"
    assert Enum.any?(third.entries, &(&1.type == :decision and &1.author == "HUMAN"))

    issue_ids =
      third.entries
      |> Enum.filter(&(&1.type == :chunk and &1.author == "ISSUE"))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    assert Enum.any?(third.entries, fn entry ->
             entry.type == :requirement and
               Enum.any?(entry.citations, &MapSet.member?(issue_ids, &1))
           end)

    {:ok, restored} = Reference.start_link(persist_path: Path.join(dir, "store.jsonl"))
    restored_entries = Reference.all(restored)
    assert length(restored_entries) == length(third.entries)
    assert Jason.decode!(File.read!(Path.join(dir, "state.json")))["status"] == "done"
  end

  test "design stage starts after refine, iterates on comments, completes with design.md and 2-hop provenance" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    Dev.run_dev(issue: dir, adapter: "mock")
    append_response!(Path.join([dir, "pending", "HUMAN-refine.md"]), "APPROVE\n")
    refined = Dev.run_dev(issue: dir, adapter: "mock")
    assert refined.state["stage"] == "refine"
    assert refined.state["status"] == "done"

    design1 = Dev.run_dev(issue: dir, adapter: "mock")

    assert design1.state["stage"] == "design"
    assert design1.state["status"] == "awaiting_human"
    design_pending = Path.join([dir, "pending", "HUMAN-design.md"])
    assert File.read!(design_pending) =~ "DESIGN手続き"

    requirement_ids =
      design1.entries
      |> Enum.filter(&(&1.type == :requirement))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    machine_decisions = Enum.filter(design1.entries, &(&1.type == :decision and &1.author == "ARCH"))
    assert machine_decisions != []

    assert Enum.all?(machine_decisions, fn decision ->
             Enum.any?(decision.citations, &MapSet.member?(requirement_ids, &1))
           end)

    append_response!(design_pending, "- 代替案の比較も判断に含めてください\n")
    design2 = Dev.run_dev(issue: dir, adapter: "mock")

    assert design2.state["status"] == "awaiting_human"
    assert design2.state["iteration"] == 1
    assert File.exists?(design_pending)
    assert File.exists?(Path.join([dir, "pending", "done", "HUMAN-design.md"]))

    assert Enum.count(design2.entries, &(&1.type == :decision and &1.author == "ARCH")) >
             length(machine_decisions)

    append_response!(design_pending, "APPROVE\n")
    design3 = Dev.run_dev(issue: dir, adapter: "mock")

    assert design3.state["stage"] == "design"
    assert design3.state["status"] == "done"

    machine_ids =
      design3.entries
      |> Enum.filter(&(&1.type == :decision and &1.author == "ARCH"))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    assert Enum.any?(design3.entries, fn entry ->
             entry.type == :decision and entry.author == "HUMAN" and
               Enum.any?(entry.citations, &MapSet.member?(machine_ids, &1))
           end)

    design_md = File.read!(Path.join(dir, "design.md"))
    assert design_md =~ "# 設計判断"
    assert design_md =~ "設計判断(ARCH)"
    assert design_md =~ "根拠:"

    by_id = Map.new(design3.entries, &{&1.id, &1})

    decision = Enum.find(design3.entries, &(&1.type == :decision and &1.author == "ARCH"))

    requirement =
      decision.citations
      |> Enum.map(&Map.get(by_id, &1))
      |> Enum.find(&(&1 && &1.type == :requirement))

    assert requirement

    issue_chunk =
      requirement.citations
      |> Enum.map(&Map.get(by_id, &1))
      |> Enum.find(&(&1 && &1.type == :chunk and &1.author == "ISSUE"))

    assert issue_chunk

    again = Dev.run_dev(issue: dir, adapter: "mock")
    assert again.state["stage"] == "design"
    assert again.state["status"] == "done"
    assert Jason.decode!(File.read!(Path.join(dir, "state.json")))["stage"] == "design"
  end

  defp tmp_issue_dir do
    dir = Path.join(System.tmp_dir!(), "tracefield-dev-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp write_issue_files!(dir) do
    File.mkdir_p!(Path.join(dir, "docs"))
    File.write!(Path.join(dir, "issue.md"), "CLI駆動の詳細化パイプラインを実装する")
    File.write!(Path.join([dir, "docs", "reference.md"]), "受入基準はテストがgreenであること")
    File.write!(Path.join(dir, "actors.json"), Jason.encode!([llm_actor(), human_actor()]))
  end

  defp llm_actor do
    %{id: "ARCH", domain: "architecture", desc: "architectural reviewer"}
  end

  defp human_actor do
    %{id: "HUMAN", domain: "review", desc: "human reviewer", kind: "human"}
  end

  defp append_response!(pending, response) do
    content = File.read!(pending)
    File.write!(pending, content <> "\n" <> response)
  end
end
