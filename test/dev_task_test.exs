defmodule Mix.Tasks.Tracefield.DevTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Dev
  alias Tracefield.Reference

  test "refine build_agent opts include requirement and question expected types" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    {:ok, reference} = Reference.start_link()
    actor = Enum.find(Dev.load_actors!(dir), &(&1.id == "ARCH"))

    opts =
      Dev.agent_build_opts(
        actor,
        reference,
        dir,
        "e1",
        [adapter: "mock"],
        nil,
        ["requirement", "question"]
      )

    assert Keyword.get(opts, :expected_types) == ["requirement", "question"]
  end

  test "design build_agent opts include decision expected type" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    {:ok, reference} = Reference.start_link()
    actor = Enum.find(Dev.load_actors!(dir), &(&1.id == "ARCH"))

    opts =
      Dev.agent_build_opts(
        actor,
        reference,
        dir,
        "e1",
        [adapter: "mock"],
        [%{id: "e2", file: "requirement", text: "approved requirement"}],
        ["decision"]
      )

    assert Keyword.get(opts, :expected_types) == ["decision"]
  end

  test "load_actors! reads actors.json with explicit kind/turn and human without private_doc" do
    dir = tmp_issue_dir()

    File.write!(
      Path.join(dir, "actors.json"),
      Jason.encode!([
        %{
          id: "ARCH",
          domain: "architecture",
          desc: "architect",
          kind: "llm",
          private_doc: "arch.md"
        },
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

  test "load_actors! raises when actor kind is missing" do
    dir = tmp_issue_dir()

    File.write!(
      Path.join(dir, "actors.json"),
      Jason.encode!([%{id: "ARCH", domain: "architecture", desc: "architect"}])
    )

    assert_raise Mix.Error, ~r/missing actor kind for ARCH/, fn ->
      Dev.load_actors!(dir)
    end
  end

  test "load_actors! raises for unknown actor kind" do
    dir = tmp_issue_dir()

    File.write!(
      Path.join(dir, "actors.json"),
      Jason.encode!([
        %{id: "ARCH", domain: "architecture", desc: "architect", kind: "robot"}
      ])
    )

    assert_raise Mix.Error, ~r/invalid actor kind "robot" for ARCH/, fn ->
      Dev.load_actors!(dir)
    end
  end

  test "load_actors! falls back to agents.json" do
    dir = tmp_issue_dir()
    File.write!(Path.join(dir, "agents.json"), Jason.encode!([human_actor()]))

    assert [%{id: "HUMAN", kind: :human}] = Dev.load_actors!(dir)
  end

  test "combine sharing appends synthesis instruction to refine procedure and policy entry" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    File.write!(
      Path.join(dir, "policy.json"),
      Jason.encode!(%{"sharing" => %{"refine" => "combine"}})
    )

    result = Dev.run_dev(issue: dir, adapter: "mock")

    combine_text =
      "PRESENTED ENTRIES の中に自分の専門と接続する entry があれば、帰結を述べてその entry と根拠 DOC の両方を引用せよ"

    procedure =
      Enum.find(result.entries, fn entry ->
        entry.type == :procedure and Map.get(entry.meta, :stage) == "refine"
      end)

    assert procedure.text =~ combine_text

    [policy] = Enum.filter(result.entries, &(&1.type == :policy and &1.author == "POLICY"))
    assert policy.meta[:policy]["sharing"]["refine"] == "combine"
    assert policy.text =~ "sharing.refine=combine(issue)"
  end

  test "independent sharing passes machine author exclusion to agent opts" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    File.write!(
      Path.join(dir, "actors.json"),
      Jason.encode!([
        %{id: "ARCH", domain: "architecture", desc: "architect", kind: "llm"},
        %{id: "SEC", domain: "security", desc: "security", kind: "llm"},
        human_actor()
      ])
    )

    {:ok, reference} = Reference.start_link()
    actors = Dev.load_actors!(dir)
    arch = Enum.find(actors, &(&1.id == "ARCH"))

    opts = [
      adapter: "mock",
      policy: %{"sharing" => %{"refine" => "independent"}}
    ]

    agent_opts =
      Dev.agent_build_opts(
        arch,
        reference,
        dir,
        "e1",
        opts,
        nil,
        ["requirement", "question"],
        "refine",
        actors
      )

    excluded = Keyword.fetch!(agent_opts, :exclude_machine_authors)
    assert MapSet.equal?(excluded, MapSet.new(["ARCH", "SEC"]))
    assert Keyword.get(agent_opts, :sharing_stage) == "refine"
  end

  test "independent sharing seeds static machine actor ids on policy entry meta" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    File.write!(
      Path.join(dir, "policy.json"),
      Jason.encode!(%{"sharing" => %{"refine" => "independent"}})
    )

    File.write!(
      Path.join(dir, "actors.json"),
      Jason.encode!([
        %{id: "ARCH", domain: "architecture", desc: "architect", kind: "llm"},
        %{id: "SEC", domain: "security", desc: "security", kind: "llm"},
        human_actor()
      ])
    )

    result = Dev.run_dev(issue: dir, adapter: "mock", rounds: 1)

    [policy] = Enum.filter(result.entries, &(&1.type == :policy and &1.author == "POLICY"))
    assert policy.meta[:policy]["sharing"]["refine"] == "independent"
    assert policy.meta[:sharing]["refine"]["mode"] == "independent"
    assert policy.meta[:sharing]["refine"]["exclude_machine_authors"] == ["ARCH", "SEC"]
    assert policy.meta[:sharing]["design"]["mode"] == "shared"
    refute Map.has_key?(policy.meta[:sharing]["design"], "exclude_machine_authors")

    store = Path.join(dir, "store.jsonl")
    assert File.exists?(store)
    assert store |> File.read!() |> String.contains?("exclude_machine_authors")

    {:ok, restored} =
      Reference.start_link(
        persist_path: store,
        embed_adapter: Tracefield.Embed.Mock
      )

    [restored_policy] =
      Enum.filter(Reference.all(restored), &(&1.type == :policy and &1.author == "POLICY"))

    assert restored_policy.meta[:sharing]["refine"]["exclude_machine_authors"] == ["ARCH", "SEC"]
  end

  test "embed_module! maps mock and ollama adapters without fallback" do
    assert Dev.embed_module!("mock") == Tracefield.Embed.Mock
    assert Dev.embed_module!("ollama") == Tracefield.Embed.Ollama

    assert_raise Mix.Error, ~r/invalid embed "foo"/, fn ->
      Dev.embed_module!("foo")
    end
  end

  test "run_dev raises for invalid embed option" do
    assert_raise Mix.Error, ~r/invalid embed "foo"/, fn ->
      Dev.run_dev(issue: tmp_issue_dir(), embed: "foo")
    end
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
    assert Enum.all?(approved_decision_ids, &(&1 in change.citations))
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

    assert String.to_integer(String.trim(commits_before)) + 1 ==
             String.to_integer(String.trim(commits_after))

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
      |> Enum.find(&((&1 && &1.type == :chunk) and &1.author == "ISSUE"))

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
        entry.type == :verdict and requirement.id in entry.citations and
          latest_change.id in entry.citations
      end)

    assert verdict
    assert verdict.meta[:pass] == true
  end

  test "branch git flow commits implementation on issue branch without moving base" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    repo =
      init_workspace_repo!(dir,
        git: %{"mode" => "branch", "base" => "main", "branch_template" => "tracefield/{slug}"}
      )

    drive_to_design_done!(dir)

    base_before = git!(repo, ["rev-parse", "main"]) |> String.trim()

    implement1 = Dev.run_dev(issue: dir, adapter: "mock")
    branch = "tracefield/#{Path.basename(dir)}"

    assert implement1.state["stage"] == "implement"
    assert current_branch(repo) == branch
    assert git!(repo, ["rev-parse", "main"]) |> String.trim() == base_before

    append_response!(Path.join([dir, "pending", "HUMAN-implement.md"]), "APPROVE\n")
    implement2 = Dev.run_dev(issue: dir, adapter: "mock")

    assert implement2.state["status"] == "done"
    assert current_branch(repo) == branch
    assert git!(repo, ["rev-parse", "main"]) |> String.trim() == base_before
    assert git!(repo, ["rev-parse", branch]) |> String.trim() != base_before
  end

  test "worktree git flow commits implementation in worktree while original repo stays put" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    repo =
      init_workspace_repo!(dir,
        git: %{"mode" => "worktree", "base" => "main", "branch_template" => "tracefield/{slug}"}
      )

    drive_to_design_done!(dir)

    base_before = git!(repo, ["rev-parse", "main"]) |> String.trim()
    original_branch = current_branch(repo)

    implement1 = Dev.run_dev(issue: dir, adapter: "mock")
    branch = "tracefield/#{Path.basename(dir)}"
    worktree = Path.join([dir, "workspace-repo-worktrees", Path.basename(dir)])

    assert implement1.state["stage"] == "implement"
    assert current_branch(repo) == original_branch
    assert current_branch(worktree) == branch
    assert git!(repo, ["rev-parse", "HEAD"]) |> String.trim() == base_before
    refute File.exists?(Path.join(repo, "IMPLEMENTED.md"))
    assert File.exists?(Path.join(worktree, "IMPLEMENTED.md"))

    append_response!(Path.join([dir, "pending", "HUMAN-implement.md"]), "APPROVE\n")
    implement2 = Dev.run_dev(issue: dir, adapter: "mock")

    assert implement2.state["status"] == "done"
    assert current_branch(repo) == original_branch
    assert git!(repo, ["rev-parse", "HEAD"]) |> String.trim() == base_before
    assert git!(worktree, ["rev-parse", "HEAD"]) |> String.trim() != base_before
    assert git!(repo, ["status", "--porcelain"]) == ""
  end

  test "effective policy is seeded once and cited by implementation changes" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    init_workspace_repo!(dir,
      git: %{"mode" => "branch", "base" => "main", "branch_template" => "tracefield/{slug}"}
    )

    drive_to_design_done!(dir)

    implement1 = Dev.run_dev(issue: dir, adapter: "mock")

    [policy] = Enum.filter(implement1.entries, &(&1.type == :policy and &1.author == "POLICY"))

    assert policy.text =~ "policy: "
    assert policy.text =~ "coverage.mode=absolute(default)"
    assert policy.text =~ "git.mode=branch(issue)"
    assert policy.text =~ "git.base=main(issue)"
    assert policy.meta[:kind] == "effective_policy"
    assert policy.meta[:policy]["git"]["mode"] == "branch"
    assert policy.meta[:sources]["git.mode"] == "issue"

    change = Enum.find(implement1.entries, &(&1.type == :change and &1.author == "ORGAN"))
    assert List.last(change.citations) == policy.id

    implement2 = Dev.run_dev(issue: dir, adapter: "mock")

    assert Enum.count(implement2.entries, &(&1.type == :policy and &1.author == "POLICY")) == 1
  end

  test "repo policy drives relative coverage mode and CLI flag overrides it" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    repo = init_workspace_repo!(dir)
    File.mkdir_p!(Path.join([repo, ".tracefield"]))

    File.write!(
      Path.join([repo, ".tracefield", "policy.json"]),
      Jason.encode!(%{"coverage" => %{"mode" => "relative"}})
    )

    repo_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Dev.run_dev(issue: dir, adapter: "mock")
      end)

    assert repo_output =~
             "⚠ coverage-relative: insufficient samples (N=2), skipping relative detection"

    cli_dir = tmp_issue_dir()
    write_issue_files!(cli_dir)
    cli_repo = init_workspace_repo!(cli_dir)
    File.mkdir_p!(Path.join([cli_repo, ".tracefield"]))

    File.write!(
      Path.join([cli_repo, ".tracefield", "policy.json"]),
      Jason.encode!(%{"coverage" => %{"mode" => "relative"}})
    )

    cli_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Dev.run_dev(
          issue: cli_dir,
          adapter: "mock",
          coverage_mode: :absolute,
          coverage_threshold: 0.0
        )
      end)

    refute cli_output =~ "coverage-relative"
  end

  test "policy entry records value and source metadata" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    repo = init_workspace_repo!(dir)
    File.mkdir_p!(Path.join([repo, ".tracefield"]))

    File.write!(
      Path.join([repo, ".tracefield", "policy.json"]),
      Jason.encode!(%{"coverage" => %{"mode" => "relative"}, "embed" => "mock"})
    )

    result = Dev.run_dev(issue: dir, adapter: "mock", coverage_mode: :absolute)
    [policy] = Enum.filter(result.entries, &(&1.type == :policy and &1.author == "POLICY"))

    assert policy.text =~ "coverage.mode=absolute(cli)"
    assert policy.text =~ "embed=mock(repo)"
    assert policy.meta[:kind] == "effective_policy"
    assert policy.meta[:policy]["coverage"]["mode"] == "absolute"
    assert policy.meta[:sources]["coverage.mode"] in [:cli, "cli"]
    assert policy.meta[:sources]["embed"] in [:repo, "repo"]
  end

  test "status prints effective policy values and sources" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Dev.run_dev(issue: dir, adapter: "mock", status: true, rounds: 3)
      end)

    assert output =~ "effective policy:"
    assert output =~ "  rounds: 3 (cli)"
    assert output =~ "  coverage.mode: absolute (default)"
  end

  test "qa stage passes after implement done with verdict provenance chain" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    init_workspace_repo!(dir)
    drive_to_implement_done!(dir)

    result = Dev.run_dev(issue: dir, adapter: "mock")

    assert result.state["stage"] == "qa"
    assert result.state["status"] == "done"

    requirements =
      Enum.filter(result.entries, &(&1.type == :requirement and &1.status == :active))

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

    change =
      Map.fetch!(by_id, Enum.find(verdict.citations, &(Map.get(by_id, &1).type == :change)))

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
      |> Enum.find(&((&1 && &1.type == :chunk) and &1.author == "ISSUE"))

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

  test "pr git flow creates PR once, preserves URL through QA rollback, and pushes updates" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)
    gh = fake_gh!(dir)
    bare = init_bare_repo!(dir, "origin.git")

    repo =
      init_workspace_repo!(dir,
        test_cmd: "false",
        git: %{
          "mode" => "pr",
          "base" => "main",
          "branch_template" => "tracefield/{slug}",
          "remote" => "origin",
          "gh_cmd" => gh
        }
      )

    git!(repo, ["remote", "add", "origin", bare])
    drive_to_design_done!(dir)

    Dev.run_dev(issue: dir, adapter: "mock")
    append_response!(Path.join([dir, "pending", "HUMAN-implement.md"]), "APPROVE\n")

    {implement_done, implement_output} = run_dev_capture(dir)
    branch = "tracefield/#{Path.basename(dir)}"

    assert implement_done.state["stage"] == "implement"
    assert implement_done.state["status"] == "done"
    assert implement_done.state["pr_url"] == "https://example.com/pr/1"
    assert implement_output =~ "PR: https://example.com/pr/1"
    assert branch_ref?(bare, branch)
    assert gh_create_count(dir) == 1

    first_remote_sha = git!(bare, ["rev-parse", branch]) |> String.trim()

    qa_fail = Dev.run_dev(issue: dir, adapter: "mock")

    assert qa_fail.state["stage"] == "implement"
    assert qa_fail.state["status"] == "awaiting_human"
    assert qa_fail.state["pr_url"] == "https://example.com/pr/1"

    append_response!(Path.join([dir, "pending", "HUMAN-implement.md"]), "APPROVE\n")
    {reapprove_done, reapprove_output} = run_dev_capture(dir)

    assert reapprove_done.state["stage"] == "implement"
    assert reapprove_done.state["status"] == "done"
    assert reapprove_done.state["pr_url"] == "https://example.com/pr/1"
    assert reapprove_output =~ "PR 更新: push 済み（https://example.com/pr/1）"
    assert gh_create_count(dir) == 1

    second_remote_sha = git!(bare, ["rev-parse", branch]) |> String.trim()
    local_sha = git!(repo, ["rev-parse", branch]) |> String.trim()

    assert second_remote_sha == local_sha
    assert second_remote_sha != first_remote_sha

    workspace_path = Path.join(dir, "workspace.json")

    workspace_config =
      workspace_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("test_cmd", "true")

    File.write!(workspace_path, Jason.encode!(workspace_config, pretty: true))

    {qa_pass, qa_output} = run_dev_capture(dir)

    assert qa_pass.state["stage"] == "qa"
    assert qa_pass.state["status"] == "done"
    assert qa_pass.state["pr_url"] == "https://example.com/pr/1"
    assert qa_output =~ "PR: https://example.com/pr/1"
    assert gh_create_count(dir) == 1
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

  test "gate_d_decision_ids excludes machine decisions without active requirement citation" do
    {:ok, reference} = Reference.start_link()
    actors = sample_actors()

    [req] =
      Reference.absorb(reference, [%{type: :requirement, text: "approved requirement"}], "HUMAN")

    [chunk] = Reference.absorb(reference, [%{type: :chunk, text: "reference chunk"}], "DOCS")

    [cited] =
      Reference.absorb(
        reference,
        [%{type: :decision, text: "cited design", citations: [req.id, chunk.id]}],
        "ARCH"
      )

    [uncited] =
      Reference.absorb(
        reference,
        [%{type: :decision, text: "uncited design", citations: [chunk.id]}],
        "ARCH"
      )

    assert Dev.gate_d_decision_ids(reference, actors) == [cited.id]
    refute uncited.id in Dev.gate_d_decision_ids(reference, actors)
  end

  test "gate_d_decision_ids matches all machine decisions when each cites an active requirement" do
    {:ok, reference} = Reference.start_link()
    actors = sample_actors()

    [req] =
      Reference.absorb(reference, [%{type: :requirement, text: "approved requirement"}], "HUMAN")

    [chunk] = Reference.absorb(reference, [%{type: :chunk, text: "reference chunk"}], "DOCS")

    [d1] =
      Reference.absorb(
        reference,
        [%{type: :decision, text: "design 1", citations: [req.id]}],
        "ARCH"
      )

    [d2] =
      Reference.absorb(
        reference,
        [%{type: :decision, text: "design 2", citations: [req.id, chunk.id]}],
        "ARCH"
      )

    assert MapSet.new(Dev.gate_d_decision_ids(reference, actors)) ==
             MapSet.new([d1.id, d2.id])
  end

  test "warn_uncited_decisions prints warning for requirement-less machine decisions" do
    {:ok, reference} = Reference.start_link()
    actors = sample_actors()

    [req] =
      Reference.absorb(reference, [%{type: :requirement, text: "approved requirement"}], "HUMAN")

    [chunk] = Reference.absorb(reference, [%{type: :chunk, text: "reference chunk"}], "DOCS")

    Reference.absorb(
      reference,
      [%{type: :decision, text: "cited design", citations: [req.id]}],
      "ARCH"
    )

    [uncited] =
      Reference.absorb(
        reference,
        [%{type: :decision, text: "uncited design", citations: [chunk.id]}],
        "ARCH"
      )

    output = ExUnit.CaptureIO.capture_io(fn -> Dev.warn_uncited_decisions(reference, actors) end)

    assert output =~ "⚠ requirement未引用のdecision: #{uncited.id} (ARCH)"
  end

  test "design stage excludes uncited machine decisions from approve_targets and design.md" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    drive_to_design_awaiting!(dir)

    {:ok, reference} =
      Reference.start_link(
        persist_path: Path.join(dir, "store.jsonl"),
        embed_adapter: Tracefield.Embed.Mock
      )

    chunk = Enum.find(Reference.all(reference), &(&1.type == :chunk))

    [uncited] =
      Reference.absorb(
        reference,
        [%{type: :decision, text: "uncited design judgment", citations: [chunk.id]}],
        "ARCH"
      )

    design_pending = Path.join([dir, "pending", "HUMAN-design.md"])

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Dev.run_dev(issue: dir, adapter: "mock")
      end)

    assert output =~ "⚠ requirement未引用のdecision: #{uncited.id} (ARCH)"

    append_response!(design_pending, "APPROVE\n")
    design_done = Dev.run_dev(issue: dir, adapter: "mock")

    assert design_done.state["stage"] == "design"
    assert design_done.state["status"] == "done"

    {:ok, restored} =
      Reference.start_link(
        persist_path: Path.join(dir, "store.jsonl"),
        embed_adapter: Tracefield.Embed.Mock
      )

    gate_d_ids = Dev.gate_d_decision_ids(restored, sample_actors()) |> MapSet.new()

    human_decision =
      design_done.entries
      |> Enum.filter(&(&1.type == :decision and &1.author == "HUMAN"))
      |> Enum.find(fn entry ->
        Enum.any?(entry.citations, &MapSet.member?(gate_d_ids, &1))
      end)

    assert human_decision
    refute uncited.id in human_decision.citations
    assert MapSet.subset?(MapSet.new(human_decision.citations), gate_d_ids)

    design_md = File.read!(Path.join(dir, "design.md"))
    refute design_md =~ "uncited design judgment"
    assert design_md =~ "設計判断(ARCH)"
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

    machine_decisions =
      Enum.filter(design1.entries, &(&1.type == :decision and &1.author == "ARCH"))

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
      |> Enum.find(&((&1 && &1.type == :chunk) and &1.author == "ISSUE"))

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

  defp drive_to_design_awaiting!(dir) do
    Dev.run_dev(issue: dir, adapter: "mock")
    append_response!(Path.join([dir, "pending", "HUMAN-refine.md"]), "APPROVE\n")
    Dev.run_dev(issue: dir, adapter: "mock")
    Dev.run_dev(issue: dir, adapter: "mock")
  end

  defp drive_to_design_done!(dir) do
    drive_to_design_awaiting!(dir)
    append_response!(Path.join([dir, "pending", "HUMAN-design.md"]), "APPROVE\n")
    Dev.run_dev(issue: dir, adapter: "mock")
  end

  defp sample_actors do
    [
      %{
        id: "ARCH",
        domain: "architecture",
        desc: "architectural reviewer",
        kind: :llm,
        turn: :blocking,
        private_doc_file: nil,
        private_doc_path: nil,
        private_doc: "",
        model: nil,
        recruit_entry: nil
      },
      %{
        id: "HUMAN",
        domain: "review",
        desc: "human reviewer",
        kind: :human,
        turn: :blocking,
        private_doc_file: nil,
        private_doc_path: nil,
        private_doc: "",
        model: nil,
        recruit_entry: nil
      }
    ]
  end

  defp init_workspace_repo!(issue_dir, opts \\ []) do
    test_cmd = Keyword.get(opts, :test_cmd, "true")
    git_config = Keyword.get(opts, :git)
    repo = Path.join(issue_dir, "workspace-repo")
    File.mkdir_p!(repo)
    git!(repo, ["init"])
    File.write!(Path.join(repo, "README.md"), "initial\n")
    git!(repo, ["add", "README.md"])

    git!(repo, [
      "-c",
      "user.email=t@tracefield",
      "-c",
      "user.name=tracefield",
      "commit",
      "-m",
      "init"
    ])

    if git_config do
      git!(repo, ["branch", "-M", Map.get(git_config, "base", "main")])
    end

    workspace_config =
      %{
        "path" => "workspace-repo",
        "test_cmd" => test_cmd,
        "organ" => %{"cmd" => "true", "args" => [], "author" => "ORGAN"}
      }
      |> maybe_put_git_config(git_config)

    File.write!(Path.join(issue_dir, "workspace.json"), Jason.encode!(workspace_config))

    repo
  end

  defp init_bare_repo!(parent_dir, name) do
    dir = Path.join(parent_dir, name)
    {_output, 0} = System.cmd("git", ["init", "--bare", dir], stderr_to_stdout: true)
    dir
  end

  defp fake_gh!(dir) do
    path = Path.join(dir, "fake-gh")

    File.write!(
      path,
      """
      #!/bin/sh
      DIR=$(dirname "$0")
      printf '%s\\n' "$*" >> "$DIR/gh-args.log"
      printf '%s\\n' "https://example.com/pr/1"
      exit 0
      """
    )

    File.chmod!(path, 0o755)
    path
  end

  defp run_dev_capture(dir) do
    parent = self()

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        send(parent, {:dev_result, Dev.run_dev(issue: dir, adapter: "mock")})
      end)

    result =
      receive do
        {:dev_result, result} -> result
      after
        1_000 -> flunk("Dev.run_dev did not return")
      end

    {result, output}
  end

  defp gh_create_count(dir) do
    path = Path.join(dir, "gh-args.log")

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.count(&String.starts_with?(&1, "pr create "))
    else
      0
    end
  end

  defp branch_ref?(bare, branch) do
    case System.cmd("git", ["show-ref", "--verify", "--quiet", "refs/heads/#{branch}"], cd: bare) do
      {_output, 0} -> true
      _other -> false
    end
  end

  defp maybe_put_git_config(config, nil), do: config
  defp maybe_put_git_config(config, git_config), do: Map.put(config, "git", git_config)

  defp write_issue_files!(dir) do
    File.mkdir_p!(Path.join(dir, "docs"))
    File.write!(Path.join(dir, "issue.md"), "CLI駆動の詳細化パイプラインを実装する")
    File.write!(Path.join([dir, "docs", "reference.md"]), "受入基準はテストがgreenであること")
    File.write!(Path.join(dir, "actors.json"), Jason.encode!([llm_actor(), human_actor()]))
  end

  defp llm_actor do
    %{id: "ARCH", domain: "architecture", desc: "architectural reviewer", kind: "llm"}
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

  defp current_branch(path) do
    git!(path, ["branch", "--show-current"]) |> String.trim()
  end
end
