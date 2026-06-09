defmodule Tracefield.Scenario do
  @moduledoc """
  Loader for the enterprise-assistant MVP scenario.
  """

  defstruct [:dir, :task, :contaminant, :correction, contaminants: %{}, decoys: []]

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
      contaminants = load_contaminants(dir)

      {:ok,
       %__MODULE__{
         dir: dir,
         task: strip_agent_meta(task),
         contaminant: contaminant,
         correction: correction,
         contaminants: contaminants,
         decoys: load_decoys(dir)
       }}
    end
  end

  def contaminant_pair(%__MODULE__{contaminants: contaminants}, contaminant) do
    key = normalize_contaminant_key(contaminant)

    case Map.fetch(contaminants, key) do
      {:ok, pair} -> {:ok, pair}
      :error -> {:error, {:unknown_contaminant, contaminant}}
    end
  end

  def contaminant_pair!(%__MODULE__{} = scenario, contaminant) do
    case contaminant_pair(scenario, contaminant) do
      {:ok, pair} -> pair
      {:error, reason} -> raise "failed to select contaminant: #{inspect(reason)}"
    end
  end

  defp load_contaminants(dir) do
    ["a", "b", "c"]
    |> Enum.flat_map(fn key ->
      with {:ok, contaminant_path} <- injection_path(dir, "contaminant", key),
           {:ok, correction_path} <- injection_path(dir, "correction", key),
           {:ok, contaminant} <- load_injection(contaminant_path),
           {:ok, correction} <- load_injection(correction_path) do
        [{key, %{contaminant: contaminant, correction: correction}}]
      else
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp load_decoys(dir) do
    dir
    |> Path.join("decoy-*.md")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      case load_injection(path) do
        {:ok, injection} -> [injection]
        {:error, _reason} -> []
      end
    end)
  end

  defp injection_path(dir, kind, key) do
    [String.upcase(key), String.downcase(key)]
    |> Enum.map(&Path.join(dir, "#{kind}-#{&1}.md"))
    |> Enum.find(&File.exists?/1)
    |> case do
      nil -> {:error, :missing_injection}
      path -> {:ok, path}
    end
  end

  defp normalize_contaminant_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalize_contaminant_key()

  defp normalize_contaminant_key(key) when is_binary(key),
    do: key |> String.trim() |> String.downcase()

  defp normalize_contaminant_key(key), do: key

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
