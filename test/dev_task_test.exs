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

  test "implement stage runs after design with workspace, gates on human approval, and commits workspace changes" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    repo = init_workspace_repo!(dir)

    drive_to_design_done!(dir)

    implement1 = Dev.run_dev(issue: dir, adapter: "mock")

    assert implement1.state["stage"] == "implement"
    assert implement1.state["status"] == "awaiting_human"

    implement_pending = Path.join([dir, "pending", "HUMAN-implement.md"])
    assert File.exists?(implement_pending)
    assert File.exists?(dir |> Path.join("pending") |> Path.join("implement-r5.patch"))

    approved_decision_ids =
      implement1.entries
      |> Enum.filter(fn entry ->
        entry.type == :decision and entry.author == "ARCH" and entry.status == :active and
          Enum.any?(implement1.entries, fn human ->
            human.type == :decision and human.author == "HUMAN" and entry.id in human.citations
          end)
      end)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    change =
      Enum.find(implement1.entries, fn entry ->
        entry.type == :change and entry.author == "ORGAN" and entry.status == :active
      end)

    assert change
    assert Enum.all?(change.citations, &MapSet.member?(approved_decision_ids, &1))
    assert change.text =~ "テスト: green"
    assert File.exists?(Path.join(repo, "IMPLEMENTED.md"))

    append_response!(implement_pending, "- テストの追加も検討してください\n")
    implement2 = Dev.run_dev(issue: dir, adapter: "mock")

    assert implement2.state["status"] == "awaiting_human"
    assert implement2.state["iteration"] == 1
    assert Enum.count(implement2.entries, &(&1.type == :change and &1.author == "ORGAN")) == 2
    assert File.exists?(dir |> Path.join("pending") |> Path.join("implement-r6.patch"))

    {commits_before, 0} = System.cmd("git", ["rev-list", "--count", "HEAD"], cd: repo)

    append_response!(implement_pending, "APPROVE\n")
    implement3 = Dev.run_dev(issue: dir, adapter: "mock")

    assert implement3.state["stage"] == "implement"
    assert implement3.state["status"] == "done"

    change_ids =
      implement3.entries
      |> Enum.filter(&(&1.type == :change and &1.author == "ORGAN"))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    assert Enum.any?(implement3.entries, fn entry ->
             entry.type == :decision and entry.author == "HUMAN" and
               Enum.any?(entry.citations, &MapSet.member?(change_ids, &1))
           end)

    {commits_after, 0} = System.cmd("git", ["rev-list", "--count", "HEAD"], cd: repo)
    assert String.to_integer(String.trim(commits_before)) + 1 == String.to_integer(String.trim(commits_after))

    by_id = Map.new(implement3.entries, &{&1.id, &1})

    human_decision =
      Enum.find(implement3.entries, fn entry ->
        entry.type == :decision and entry.author == "HUMAN" and
          Enum.any?(entry.citations, &MapSet.member?(change_ids, &1))
      end)

    cited_change = Map.fetch!(by_id, hd(human_decision.citations))

    cited_decision =
      cited_change.citations
      |> Enum.map(&Map.get(by_id, &1))
      |> Enum.find(&(&1 && &1.type == :decision))

    requirement =
      cited_decision.citations
      |> Enum.map(&Map.get(by_id, &1))
      |> Enum.find(&(&1 && &1.type == :requirement))

    issue_chunk =
      requirement.citations
      |> Enum.map(&Map.get(by_id, &1))
      |> Enum.find(&(&1 && &1.type == :chunk and &1.author == "ISSUE"))

    assert cited_change.type == :change
    assert cited_decision
    assert requirement
    assert issue_chunk

    again = Dev.run_dev(issue: dir, adapter: "mock")
    assert again.state["stage"] == "qa"
    assert again.state["status"] == "done"

    assert Enum.any?(again.entries, &(&1.type == :verdict and &1.author == "QA"))

    latest_change =
      again.entries
      |> Enum.filter(&(&1.type == :change and &1.author == "ORGAN" and &1.status == :active))
      |> Enum.max_by(&String.to_integer(String.trim_leading(&1.id, "e")))

    requirement = Enum.find(again.entries, &(&1.type == :requirement and &1.status == :active))

    verdict =
      Enum.find(again.entries, fn entry ->
        entry.type == :verdict and requirement.id in entry.citations and latest_change.id in entry.citations
      end)

    assert verdict
    assert verdict.meta[:pass] == true
  end

  test "qa stage passes after implement done with verdict provenance chain" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    init_workspace_repo!(dir)
    drive_to_implement_done!(dir)

    result = Dev.run_dev(issue: dir, adapter: "mock")

    assert result.state["stage"] == "qa"
    assert result.state["status"] == "done"

    requirements = Enum.filter(result.entries, &(&1.type == :requirement and &1.status == :active))

    latest_change =
      result.entries
      |> Enum.filter(&(&1.type == :change and &1.author == "ORGAN" and &1.status == :active))
      |> Enum.max_by(&String.to_integer(String.trim_leading(&1.id, "e")))

    Enum.each(requirements, fn requirement ->
      verdict =
        Enum.find(result.entries, fn entry ->
          entry.type == :verdict and entry.author == "QA" and
            requirement.id in entry.citations and latest_change.id in entry.citations
        end)

      assert verdict
      assert verdict.meta[:pass] == true
    end)

    by_id = Map.new(result.entries, &{&1.id, &1})

    verdict = Enum.find(result.entries, &(&1.type == :verdict and &1.author == "QA"))
    change = Map.fetch!(by_id, Enum.find(verdict.citations, &(Map.get(by_id, &1).type == :change)))

    decision =
      change.citations
      |> Enum.map(&Map.get(by_id, &1))
      |> Enum.find(&(&1 && &1.type == :decision))

    requirement =
      verdict.citations
      |> Enum.map(&Map.get(by_id, &1))
      |> Enum.find(&(&1 && &1.type == :requirement))

    issue_chunk =
      requirement.citations
      |> Enum.map(&Map.get(by_id, &1))
      |> Enum.find(&(&1 && &1.type == :chunk and &1.author == "ISSUE"))

    assert change
    assert decision
    assert requirement
    assert issue_chunk

    again = Dev.run_dev(issue: dir, adapter: "mock")
    assert again.state["stage"] == "qa"
    assert again.state["status"] == "done"
  end

  test "qa fail rolls back to implement and requires re-approval of latest change" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    repo = init_workspace_repo!(dir, test_cmd: "false")
    drive_to_implement_done!(dir)

    fail_qa = Dev.run_dev(issue: dir, adapter: "mock")

    assert fail_qa.state["stage"] == "implement"
    assert fail_qa.state["status"] == "awaiting_human"

    fail_verdict = Enum.find(fail_qa.entries, &(&1.type == :verdict and &1.author == "QA"))
    assert fail_verdict
    assert fail_verdict.meta[:pass] == false

    changes =
      fail_qa.entries
      |> Enum.filter(&(&1.type == :change and &1.author == "ORGAN" and &1.status == :active))

    assert length(changes) == 2

    patches =
      dir
      |> Path.join("pending")
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, "implement-r"))

    assert length(patches) == 2

    resume = Dev.run_dev(issue: dir, adapter: "mock")
    assert resume.state["stage"] == "implement"
    assert resume.state["status"] == "awaiting_human"

    workspace_path = Path.join(dir, "workspace.json")

    workspace_config =
      workspace_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("test_cmd", "true")

    File.write!(workspace_path, Jason.encode!(workspace_config, pretty: true))

    implement_pending = Path.join([dir, "pending", "HUMAN-implement.md"])
    append_response!(implement_pending, "APPROVE\n")
    implement_done = Dev.run_dev(issue: dir, adapter: "mock")

    assert implement_done.state["stage"] == "implement"
    assert implement_done.state["status"] == "done"

    {commits_after_fix, 0} = System.cmd("git", ["rev-list", "--count", "HEAD"], cd: repo)
    assert String.to_integer(String.trim(commits_after_fix)) == 3

    pass_qa = Dev.run_dev(issue: dir, adapter: "mock")
    assert pass_qa.state["stage"] == "qa"
    assert pass_qa.state["status"] == "done"

    pass_verdicts = Enum.filter(pass_qa.entries, &(&1.type == :verdict and &1.author == "QA"))
    assert Enum.any?(pass_verdicts, &(&1.meta[:pass] == true))
  end

  test "implement raises when workspace is dirty" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    repo = init_workspace_repo!(dir)
    drive_to_design_done!(dir)

    File.write!(Path.join(repo, "dirty.txt"), "uncommitted\n")

    assert_raise Mix.Error, ~r/clean/, fn ->
      Dev.run_dev(issue: dir, adapter: "mock")
    end
  end

  test "implement change text reports red when test_cmd fails" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    _repo = init_workspace_repo!(dir, test_cmd: "false")
    drive_to_design_done!(dir)

    result = Dev.run_dev(issue: dir, adapter: "mock")

    change = Enum.find(result.entries, &(&1.type == :change and &1.author == "ORGAN"))
    assert change.text =~ "テスト: red"
    assert change.text =~ "exit 1"
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

  defp drive_to_implement_done!(dir) do
    drive_to_design_done!(dir)
    Dev.run_dev(issue: dir, adapter: "mock")
    append_response!(Path.join([dir, "pending", "HUMAN-implement.md"]), "APPROVE\n")
    Dev.run_dev(issue: dir, adapter: "mock")
  end

  defp drive_to_design_done!(dir) do
    Dev.run_dev(issue: dir, adapter: "mock")
    append_response!(Path.join([dir, "pending", "HUMAN-refine.md"]), "APPROVE\n")
    Dev.run_dev(issue: dir, adapter: "mock")
    Dev.run_dev(issue: dir, adapter: "mock")
    append_response!(Path.join([dir, "pending", "HUMAN-design.md"]), "APPROVE\n")
    Dev.run_dev(issue: dir, adapter: "mock")
  end

  defp init_workspace_repo!(issue_dir, opts \\ []) do
    test_cmd = Keyword.get(opts, :test_cmd, "true")
    repo = Path.join(issue_dir, "workspace-repo")
    File.mkdir_p!(repo)
    git!(repo, ["init"])
    File.write!(Path.join(repo, "README.md"), "initial\n")
    git!(repo, ["add", "README.md"])
    git!(repo, ["-c", "user.email=t@tracefield", "-c", "user.name=tracefield", "commit", "-m", "init"])

    File.write!(
      Path.join(issue_dir, "workspace.json"),
      Jason.encode!(%{
        "path" => "workspace-repo",
        "test_cmd" => test_cmd,
        "organ" => %{"cmd" => "true", "args" => [], "author" => "ORGAN"}
      })
    )

    repo
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

  defp git!(path, args) do
    {output, 0} = System.cmd("git", args, cd: path, stderr_to_stdout: true)
    output
  end
end
