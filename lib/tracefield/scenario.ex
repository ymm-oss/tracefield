defmodule Tracefield.Scenario do
  @moduledoc """
  Loader for the enterprise-assistant MVP scenario.
  """

  defstruct [:dir, :task, :contaminant, :correction]

  defmodule Injection do
    @moduledoc false
    defstruct [
      :id,
      :scenario,
      :type,
      :condition_state,
      :tracks,
      :inject_after,
      :source_actor,
      :status_at_injection,
      :revealed_later,
      :counterpart,
      :replaces,
      :body,
      :raw_body,
      metadata: %{}
    ]
  end

  @spec load(Path.t()) :: %__MODULE__{}
  def load(dir) do
    load!(dir)
  end

  def load!(dir) do
    case load_result(dir) do
      {:ok, scenario} -> scenario
      {:error, reason} -> raise "failed to load scenario #{dir}: #{inspect(reason)}"
    end
  end

  defp load_result(dir) do
    with {:ok, task} <- File.read(Path.join(dir, "task.md")),
         {:ok, contaminant} <- load_injection(Path.join(dir, "contaminant-A.md")),
         {:ok, correction} <- load_injection(Path.join(dir, "correction-A.md")) do
      {:ok,
       %__MODULE__{
         dir: dir,
         task: strip_agent_meta(task),
         contaminant: contaminant,
         correction: correction
       }}
    end
  end

  defp load_injection(path) do
    with {:ok, text} <- File.read(path),
         {:ok, frontmatter, body} <- split_frontmatter(text) do
      metadata = parse_frontmatter(frontmatter)
      agent_body = agent_injection_body(body)

      {:ok,
       %Injection{
         id: metadata["id"],
         scenario: metadata["scenario"],
         type: metadata["type"],
         condition_state: metadata["condition_state"],
         tracks: metadata["tracks"],
         inject_after: metadata["inject_after"],
         source_actor: metadata["source_actor"],
         status_at_injection: metadata["status_at_injection"],
         revealed_later: metadata["revealed_later"],
         counterpart: metadata["counterpart"],
         replaces: metadata["replaces"],
         body: agent_body,
         raw_body: body,
         metadata: metadata
       }}
    end
  end

  defp split_frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---\n", parts: 2) do
      [frontmatter, body] -> {:ok, frontmatter, body}
      _ -> {:error, :invalid_frontmatter}
    end
  end

  defp split_frontmatter(_text), do: {:error, :missing_frontmatter}

  defp parse_frontmatter(frontmatter) do
    frontmatter
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp strip_agent_meta(text) do
    text
    |> String.split("## この入力の性質", parts: 2)
    |> hd()
    |> String.trim()
  end

  defp agent_injection_body(text) do
    clean = strip_agent_meta(text)

    case Regex.run(~r/(\*\*事業責任者より[\s\S]*?)(?:\n---|\z)/u, clean) do
      [_, block] -> String.trim(block)
      _ -> clean
    end
  end
end
