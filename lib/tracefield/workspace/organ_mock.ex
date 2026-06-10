defmodule Tracefield.Workspace.OrganMock do
  @moduledoc "Deterministic organ adapter for workspace implement rounds in tests."

  @spec run(String.t(), String.t()) :: {:ok, String.t()}
  def run(path, prompt) do
    decision_lines =
      prompt
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(~r/^e\d+:/, &1))
      |> Enum.map_join("\n", & &1)

    content = "mock実装\n" <> decision_lines <> "\n"
    implemented = Path.join(path, "IMPLEMENTED.md")
    File.write!(implemented, content, [:append])

    {:ok, "mock実装: IMPLEMENTED.md を更新"}
  end
end
