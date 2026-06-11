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

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tracefield-ws-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp init_git_repo! do
    dir = tmp_dir()
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

  defp write_workspace!(issue_dir, config) do
    File.write!(Path.join(issue_dir, "workspace.json"), Jason.encode!(config))
  end
end
