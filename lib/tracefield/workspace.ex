defmodule Tracefield.Workspace do
  @moduledoc "Workspace configuration and organ execution for the implement stage."

  alias Tracefield.Workspace.OrganMock

  defstruct [:path, :test_cmd, :organ_cmd, :organ_args, :organ_author]

  @default_test_cmd "mise exec -- mix test"
  @default_organ_cmd "claude"
  @default_organ_args ["-p"]
  @default_organ_author "ORGAN"
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

    %__MODULE__{
      path: repo_path,
      test_cmd: Map.get(config, "test_cmd", @default_test_cmd),
      organ_cmd: Map.get(organ, "cmd", @default_organ_cmd),
      organ_args: normalize_args(Map.get(organ, "args", @default_organ_args)),
      organ_author: Map.get(organ, "author", @default_organ_author)
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
      git!(ws.path, @git_identity ++ ["commit", "-m", message])
      {short_sha, 0} = git!(ws.path, ["rev-parse", "--short", "HEAD"])
      {:ok, String.trim(short_sha)}
    end
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

  defp git!(path, args) do
    case System.cmd("git", args, cd: path, stderr_to_stdout: true) do
      {output, 0} -> {output, 0}
      {output, code} -> Mix.raise("git #{Enum.join(args, " ")} failed (exit #{code}): #{output}")
    end
  end
end
