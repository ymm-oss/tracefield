defmodule Tracefield.WorkspaceTest do
  use ExUnit.Case

  alias Tracefield.Workspace
  alias Tracefield.Workspace.OrganMock

  test "load! raises when workspace.json is missing" do
    dir = tmp_dir()

    assert_raise Mix.Error, ~r/workspace\.json/, fn ->
      Workspace.load!(dir)
    end
  end

  test "load! raises when path is not a git repository" do
    issue_dir = tmp_dir()
    repo_dir = Path.join(issue_dir, "repo")
    File.mkdir_p!(repo_dir)

    write_workspace!(issue_dir, %{"path" => "repo"})

    assert_raise Mix.Error, ~r/git リポジトリ/, fn ->
      Workspace.load!(issue_dir)
    end
  end

  test "load! defaults git flow to current mode when git section is omitted" do
    issue_dir = tmp_dir()
    repo = init_git_repo_in!(issue_dir, "repo")

    write_workspace!(issue_dir, %{"path" => "repo"})

    ws = Workspace.load!(issue_dir)

    assert ws.path == repo
    assert ws.git_mode == :current
    assert ws.git_branch_template == "tracefield/{slug}"
    assert ws.git_base == "main"
    assert ws.git_worktree_root == Path.join(issue_dir, "repo-worktrees")
  end

  test "load! expands git config and rejects invalid mode" do
    issue_dir = tmp_dir()
    repo = init_git_repo_in!(issue_dir, "repo")
    root = Path.join(issue_dir, "trees")

    write_workspace!(issue_dir, %{
      "path" => "repo",
      "git" => %{
        "mode" => "worktree",
        "branch_template" => "tf/{slug}",
        "base" => "trunk",
        "worktree_root" => root
      }
    })

    ws = Workspace.load!(issue_dir)

    assert ws.path == repo
    assert ws.git_mode == :worktree
    assert ws.git_branch_template == "tf/{slug}"
    assert ws.git_base == "trunk"
    assert ws.git_worktree_root == root

    write_workspace!(issue_dir, %{"path" => "repo", "git" => %{"mode" => "sideways"}})

    assert_raise Mix.Error, ~r/invalid git mode/, fn ->
      Workspace.load!(issue_dir)
    end
  end

  test "OrganMock appends mock implementation and design decision lines" do
    repo = init_git_repo!()

    prompt = """
    TRACEFIELD_IMPLEMENT
    承認済み設計判断:
    e5: 設計判断(ARCH): モジュール X を変更する
    e7: 設計判断(ARCH): データ Y を追加する
    """

    assert {:ok, summary} = OrganMock.run(repo, prompt)
    assert summary =~ "IMPLEMENTED.md"

    content = File.read!(Path.join(repo, "IMPLEMENTED.md"))
    assert content =~ "mock実装"
    assert content =~ "e5: 設計判断(ARCH): モジュール X を変更する"
    assert content =~ "e7: 設計判断(ARCH): データ Y を追加する"
  end

  test "capture_diff! returns files, stat, diff, and sha" do
    repo = init_git_repo!()
    File.write!(Path.join(repo, "new.txt"), "hello\n")

    ws = %Workspace{
      path: repo,
      test_cmd: "true",
      organ_cmd: "true",
      organ_args: [],
      organ_author: "ORGAN"
    }

    diff = Workspace.capture_diff!(ws)

    assert "new.txt" in diff.files
    assert diff.stat =~ "file changed"
    assert diff.diff =~ "hello"
    assert String.length(diff.sha) == 12
    assert Regex.match?(~r/^[0-9a-f]{12}$/, diff.sha)
  end

  test "run_tests! reports exit code and output tail" do
    repo = init_git_repo!()

    ws_ok = %Workspace{
      path: repo,
      test_cmd: "true",
      organ_cmd: "true",
      organ_args: [],
      organ_author: "ORGAN"
    }

    assert %{exit: 0} = Workspace.run_tests!(ws_ok)

    ws_fail = %Workspace{
      path: repo,
      test_cmd: "false",
      organ_cmd: "true",
      organ_args: [],
      organ_author: "ORGAN"
    }

    assert %{exit: 1} = Workspace.run_tests!(ws_fail)
  end

  test "apply! creates a commit and advances HEAD" do
    repo = init_git_repo!()
    {before_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: repo)
    File.write!(Path.join(repo, "applied.txt"), "applied\n")

    ws = %Workspace{
      path: repo,
      test_cmd: "true",
      organ_cmd: "true",
      organ_args: [],
      organ_author: "ORGAN"
    }

    assert {:ok, short_sha} = Workspace.apply!(ws, "tracefield test commit")
    {after_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: repo)

    assert String.trim(before_sha) != String.trim(after_sha)
    assert String.starts_with?(String.trim(after_sha), short_sha)
    assert File.exists?(Path.join(repo, "applied.txt"))
  end

  test "apply! appends default Co-Authored-By trailer from organ_author" do
    repo = init_git_repo!()
    File.write!(Path.join(repo, "applied.txt"), "applied\n")

    ws = %Workspace{
      path: repo,
      test_cmd: "true",
      organ_cmd: "true",
      organ_args: [],
      organ_author: "ORGAN/codex"
    }

    assert {:ok, _short_sha} = Workspace.apply!(ws, "tracefield implement: issue-1 [e37]")

    {body, 0} = System.cmd("git", ["log", "-1", "--format=%B"], cd: repo)

    assert body =~ "Co-Authored-By: ORGAN/codex via tracefield <noreply@tracefield.local>"
  end

  test "apply! appends Co-Authored-By trailer from workspace.json footer override" do
    issue_dir = tmp_dir()
    repo = init_git_repo_in!(issue_dir, "repo")
    File.write!(Path.join(repo, "applied.txt"), "applied\n")

    write_workspace!(issue_dir, %{
      "path" => "repo",
      "organ" => %{
        "author" => "ORGAN",
        "footer" => "Custom Organ <custom@example.com>"
      }
    })

    ws = Workspace.load!(issue_dir)

    assert {:ok, _short_sha} =
             Workspace.apply!(ws, "tracefield implement: issue-2 [e42]")

    {body, 0} = System.cmd("git", ["log", "-1", "--format=%B"], cd: repo)

    assert body =~ "Co-Authored-By: Custom Organ <custom@example.com>"
    refute body =~ "via tracefield <noreply@tracefield.local>"
  end

  test "apply! preserves the first line of the commit message" do
    repo = init_git_repo!()
    File.write!(Path.join(repo, "applied.txt"), "applied\n")

    ws = %Workspace{
      path: repo,
      test_cmd: "true",
      organ_cmd: "true",
      organ_args: [],
      organ_author: "ORGAN"
    }

    subject = "tracefield implement: issue-3 [e99]"

    assert {:ok, _short_sha} = Workspace.apply!(ws, subject)

    {body, 0} = System.cmd("git", ["log", "-1", "--format=%B"], cd: repo)
    [first_line | _] = String.split(body, "\n", trim: false)

    assert first_line == subject
  end

  test "apply! returns empty when nothing is staged" do
    repo = init_git_repo!()

    ws = %Workspace{
      path: repo,
      test_cmd: "true",
      organ_cmd: "true",
      organ_args: [],
      organ_author: "ORGAN"
    }

    assert {:error, :empty} = Workspace.apply!(ws, "nothing to commit")
  end

  test "clean? is true for clean repo and false when dirty" do
    repo = init_git_repo!()

    ws = %Workspace{
      path: repo,
      test_cmd: "true",
      organ_cmd: "true",
      organ_args: [],
      organ_author: "ORGAN"
    }

    assert Workspace.clean?(ws)

    File.write!(Path.join(repo, "dirty.txt"), "x\n")
    refute Workspace.clean?(ws)
  end

  test "ensure_flow! current mode is a no-op" do
    repo = init_git_repo!()
    branch_before = current_branch(repo)
    head_before = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()

    ws = flow_workspace(repo, :current)

    assert Workspace.ensure_flow!(ws, "issue-42").path == repo
    assert current_branch(repo) == branch_before
    assert git!(repo, ["rev-parse", "HEAD"]) |> String.trim() == head_before
  end

  test "ensure_flow! main mode checks out base branch" do
    repo = init_git_repo!()
    git!(repo, ["branch", "-M", "main"])
    git!(repo, ["checkout", "-b", "topic"])

    ws = flow_workspace(repo, :main)

    Workspace.ensure_flow!(ws, "issue-42")

    assert current_branch(repo) == "main"
  end

  test "ensure_flow! branch mode creates and reuses issue branch and blocks dirty checkout" do
    repo = init_git_repo!()
    git!(repo, ["branch", "-M", "main"])

    ws = flow_workspace(repo, :branch)

    assert Workspace.ensure_flow!(ws, "issue-42").path == repo
    assert current_branch(repo) == "tracefield/issue-42"

    head = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()
    assert Workspace.ensure_flow!(ws, "issue-42").path == repo
    assert current_branch(repo) == "tracefield/issue-42"
    assert git!(repo, ["rev-parse", "HEAD"]) |> String.trim() == head

    git!(repo, ["checkout", "main"])
    File.write!(Path.join(repo, "dirty.txt"), "dirty\n")

    assert_raise Mix.Error, ~r/clean/, fn ->
      Workspace.ensure_flow!(ws, "issue-42")
    end
  end

  test "ensure_flow! worktree mode creates a branch worktree and resolves it idempotently" do
    parent = tmp_dir()
    repo = init_git_repo_in!(parent, "repo")
    git!(repo, ["branch", "-M", "main"])
    root = Path.join(parent, "worktrees")

    ws = %{flow_workspace(repo, :worktree) | git_worktree_root: root}

    resolved = Workspace.ensure_flow!(ws, "issue-42")

    assert resolved.path == Path.join(root, "issue-42")
    assert File.exists?(Path.join(resolved.path, ".git"))
    assert current_branch(resolved.path) == "tracefield/issue-42"
    assert current_branch(repo) == "main"
    assert Workspace.clean?(%Workspace{path: repo})

    again = Workspace.ensure_flow!(ws, "issue-42")

    assert again.path == resolved.path
    assert current_branch(repo) == "main"
    assert Workspace.clean?(%Workspace{path: repo})
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tracefield-ws-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp init_git_repo! do
    init_git_repo_in!(tmp_dir())
  end

  defp init_git_repo_in!(parent_dir, name \\ nil) do
    dir = if name, do: Path.join(parent_dir, name), else: parent_dir
    File.mkdir_p!(dir)
    git!(dir, ["init"])
    File.write!(Path.join(dir, "README.md"), "initial\n")
    git!(dir, ["add", "README.md"])

    git!(dir, [
      "-c",
      "user.email=t@tracefield",
      "-c",
      "user.name=tracefield",
      "commit",
      "-m",
      "init"
    ])

    dir
  end

  defp git!(path, args) do
    {output, 0} = System.cmd("git", args, cd: path, stderr_to_stdout: true)
    output
  end

  defp current_branch(path) do
    git!(path, ["branch", "--show-current"]) |> String.trim()
  end

  defp flow_workspace(repo, mode) do
    %Workspace{
      path: repo,
      test_cmd: "true",
      organ_cmd: "true",
      organ_args: [],
      organ_author: "ORGAN",
      git_mode: mode,
      git_branch_template: "tracefield/{slug}",
      git_base: "main",
      git_worktree_root: Path.join(Path.dirname(repo), "#{Path.basename(repo)}-worktrees")
    }
  end

  defp write_workspace!(issue_dir, config) do
    File.write!(Path.join(issue_dir, "workspace.json"), Jason.encode!(config))
  end
end
