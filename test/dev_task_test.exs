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
