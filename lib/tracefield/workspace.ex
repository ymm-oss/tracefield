defmodule Tracefield.Workspace do
  @moduledoc "Workspace configuration and organ execution for the implement stage."

  alias Tracefield.Workspace.OrganMock

  defstruct [
    :path,
    :test_cmd,
    :organ_cmd,
    :organ_args,
    :organ_author,
    :organ_footer,
    :git_mode,
    :git_branch_template,
    :git_base,
    :git_worktree_root
  ]

  @default_test_cmd "mise exec -- mix test"
  @default_organ_cmd "claude"
  @default_organ_args ["-p"]
  @default_organ_author "ORGAN"
  @default_git_branch_template "tracefield/{slug}"
  @default_git_base "main"
  @git_modes [:current, :main, :branch, :worktree]
  @git_identity ["-c", "user.email=t@tracefield", "-c", "user.name=tracefield"]

  @spec configured?(String.t()) :: boolean()
  def configured?(issue_dir) do
    File.exists?(Path.join(issue_dir, "workspace.json"))
  end

  @spec load!(String.t()) :: %__MODULE__{}
  def load!(issue_dir) do
    path = Path.join(issue_dir, "workspace.json")

    unless File.exists?(path) do
      Mix.raise("workspace.json が見つかりません: #{issue_dir}")
    end

    config = Jason.decode!(File.read!(path))
    repo_path = resolve_path(issue_dir, Map.fetch!(config, "path"))
    validate_repo!(repo_path)

    organ = Map.get(config, "organ", %{})
    git = normalize_git_config!(config, repo_path)

    %__MODULE__{
      path: repo_path,
      test_cmd: Map.get(config, "test_cmd", @default_test_cmd),
      organ_cmd: Map.get(organ, "cmd", @default_organ_cmd),
      organ_args: normalize_args(Map.get(organ, "args", @default_organ_args)),
      organ_author: Map.get(organ, "author", @default_organ_author),
      organ_footer: Map.get(organ, "footer"),
      git_mode: git.mode,
      git_branch_template: git.branch_template,
      git_base: git.base,
      git_worktree_root: git.worktree_root
    }
  end

  @spec ensure_flow!(%__MODULE__{}, String.t()) :: %__MODULE__{}
  def ensure_flow!(%__MODULE__{git_mode: :current} = ws, _slug), do: ws

  def ensure_flow!(%__MODULE__{git_mode: :main} = ws, _slug) do
    if current_branch(ws.path) != ws.git_base do
      ensure_clean_for_checkout!(ws)
      git!(ws.path, ["checkout", ws.git_base])
    end

    Mix.shell().info("⚠ git flow: main — #{ws.git_base} へ直接コミットします")
    ws
  end

  def ensure_flow!(%__MODULE__{git_mode: :branch} = ws, slug) do
    branch = branch_name(ws, slug)

    if current_branch(ws.path) != branch do
      ensure_clean_for_checkout!(ws)

      if branch_exists?(ws.path, branch) do
        git!(ws.path, ["checkout", branch])
      else
        git!(ws.path, ["checkout", "-b", branch, ws.git_base])
      end
    end

    ws
  end

  def ensure_flow!(%__MODULE__{git_mode: :worktree} = ws, slug) do
    branch = branch_name(ws, slug)
    path = worktree_path(ws, slug)

    cond do
      File.exists?(path) ->
        validate_repo!(path)
        %{ws | path: path}

      true ->
        ensure_clean_for_checkout!(ws)
        File.mkdir_p!(Path.dirname(path))

        if branch_exists?(ws.path, branch) do
          git!(ws.path, ["worktree", "add", path, branch])
        else
          git!(ws.path, ["worktree", "add", "-b", branch, path, ws.git_base])
        end

        %{ws | path: path}
    end
  end

  @spec resolve_flow_path!(%__MODULE__{}, String.t()) :: %__MODULE__{}
  def resolve_flow_path!(%__MODULE__{git_mode: :worktree} = ws, slug) do
    path = worktree_path(ws, slug)

    if File.exists?(path) do
      validate_repo!(path)
      %{ws | path: path}
    else
      ws
    end
  end

  def resolve_flow_path!(ws, _slug), do: ws

  @spec git_policy(%__MODULE__{}, String.t()) :: %{
          text: String.t(),
          meta: map(),
          branch: String.t()
        }
  def git_policy(ws, slug) do
    branch =
      case ws.git_mode do
        mode when mode in [:branch, :worktree] -> branch_name(ws, slug)
        _mode -> "-"
      end

    mode = Atom.to_string(ws.git_mode)

    %{
      branch: branch,
      text: "git flow: mode=#{mode} branch=#{branch} base=#{ws.git_base}",
      meta: %{kind: "git_flow", mode: mode, branch: branch, base: ws.git_base}
    }
  end

  @spec clean?(%__MODULE__{}) :: boolean()
  def clean?(ws) do
    {output, 0} = git!(ws.path, ["status", "--porcelain"])
    String.trim(output) == ""
  end

  @spec implement!(%__MODULE__{}, String.t(), module()) :: {:ok, String.t()}
  def implement!(ws, prompt, adapter) do
    if adapter == Tracefield.LLM.Mock do
      OrganMock.run(ws.path, prompt)
    else
      {output, exit_code} =
        System.cmd(
          ws.organ_cmd,
          ws.organ_args ++ [prompt],
          cd: ws.path,
          stderr_to_stdout: true
        )

      if exit_code == 0 do
        {:ok, output}
      else
        Mix.raise("organ 実行失敗 (exit #{exit_code}): #{String.slice(output, 0, 500)}")
      end
    end
  end

  @spec capture_diff!(%__MODULE__{}) :: %{
          files: [String.t()],
          stat: String.t(),
          diff: String.t(),
          sha: String.t()
        }
  def capture_diff!(ws) do
    git!(ws.path, ["add", "-A"])

    {name_only, 0} = git!(ws.path, ["diff", "--cached", "--name-only"])

    files =
      name_only
      |> String.split("\n", trim: true)

    {stat_output, 0} = git!(ws.path, ["diff", "--cached", "--stat"])

    stat =
      stat_output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Kernel.||("")

    {diff, 0} = git!(ws.path, ["diff", "--cached"])

    sha =
      :crypto.hash(:sha256, diff)
      |> Base.encode16(case: :lower)
      |> String.slice(0, 12)

    %{files: files, stat: stat, diff: diff, sha: sha}
  end

  @spec run_tests!(%__MODULE__{}) :: %{exit: non_neg_integer(), tail: String.t()}
  def run_tests!(ws) do
    {output, exit_code} =
      System.cmd("sh", ["-c", ws.test_cmd], cd: ws.path, stderr_to_stdout: true)

    tail =
      if String.length(output) > 800 do
        String.slice(output, -800, 800)
      else
        output
      end

    %{exit: exit_code, tail: tail}
  end

  @spec apply!(%__MODULE__{}, String.t()) :: {:ok, String.t()} | {:error, :empty}
  def apply!(ws, message) do
    git!(ws.path, ["add", "-A"])

    {staged, 0} = git!(ws.path, ["diff", "--cached", "--name-only"])

    if String.trim(staged) == "" do
      {:error, :empty}
    else
      git!(ws.path, @git_identity ++ ["commit", "-m", commit_message_with_footer(ws, message)])
      {short_sha, 0} = git!(ws.path, ["rev-parse", "--short", "HEAD"])
      {:ok, String.trim(short_sha)}
    end
  end

  defp commit_message_with_footer(ws, message) do
    trailer = commit_footer(ws)
    message <> "\n\nCo-Authored-By: " <> trailer
  end

  defp commit_footer(%__MODULE__{organ_footer: footer}) when is_binary(footer), do: footer

  defp commit_footer(%__MODULE__{organ_author: author}) do
    "#{author} via tracefield <noreply@tracefield.local>"
  end

  defp resolve_path(issue_dir, path) do
    expanded =
      if Path.type(path) == :relative do
        Path.expand(path, issue_dir)
      else
        Path.expand(path)
      end

    expanded
  end

  defp validate_repo!(path) do
    cond do
      not File.exists?(path) ->
        Mix.raise("workspace path が存在しません: #{path}")

      not File.exists?(Path.join(path, ".git")) ->
        Mix.raise("workspace path は git リポジトリではありません: #{path}")

      true ->
        :ok
    end
  end

  defp normalize_args(args) when is_list(args), do: Enum.map(args, &to_string/1)
  defp normalize_args(_args), do: @default_organ_args

  defp normalize_git_config!(config, repo_path) do
    git = Map.get(config, "git", %{})
    mode = normalize_git_mode!(Map.get(git, "mode", "current"))
    branch_template = Map.get(git, "branch_template", @default_git_branch_template) |> to_string()
    base = Map.get(git, "base", @default_git_base) |> to_string()
    worktree_root = Map.get(git, "worktree_root") || default_worktree_root(repo_path)

    %{
      mode: mode,
      branch_template: branch_template,
      base: base,
      worktree_root: Path.expand(worktree_root)
    }
  end

  defp normalize_git_mode!(mode) when is_atom(mode) and mode in @git_modes, do: mode

  defp normalize_git_mode!(mode) when is_binary(mode) do
    mode
    |> String.trim()
    |> String.to_existing_atom()
    |> normalize_git_mode!()
  rescue
    ArgumentError -> Mix.raise("invalid git mode #{inspect(mode)}")
  end

  defp normalize_git_mode!(mode), do: Mix.raise("invalid git mode #{inspect(mode)}")

  defp default_worktree_root(repo_path) do
    Path.join(Path.dirname(repo_path), "#{Path.basename(repo_path)}-worktrees")
  end

  defp branch_name(ws, slug) do
    String.replace(ws.git_branch_template, "{slug}", slug)
  end

  defp worktree_path(ws, slug) do
    Path.join(ws.git_worktree_root, slug)
  end

  defp ensure_clean_for_checkout!(ws) do
    unless clean?(ws) do
      Mix.raise("workspace が clean ではありません")
    end
  end

  defp current_branch(path) do
    {output, 0} = git!(path, ["branch", "--show-current"])
    String.trim(output)
  end

  defp branch_exists?(path, branch) do
    case System.cmd("git", ["show-ref", "--verify", "--quiet", "refs/heads/#{branch}"], cd: path) do
      {_output, 0} -> true
      {_output, _code} -> false
    end
  end

  defp git!(path, args) do
    case System.cmd("git", args, cd: path, stderr_to_stdout: true) do
      {output, 0} -> {output, 0}
      {output, code} -> Mix.raise("git #{Enum.join(args, " ")} failed (exit #{code}): #{output}")
    end
  end
end
