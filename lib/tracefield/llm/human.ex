defmodule Tracefield.LLM.Human do
  @moduledoc """
  File-backed human adapter for the Tracefield LLM behaviour.
  """

  @behaviour Tracefield.LLM

  @response_heading "## RESPONSE（この下に回答を書いてください）"
  @response_template """

  #{@response_heading}
  <!-- 箇条書き1行=1エントリ。引用は [e12] 形式。質問への回答は [質問のid] を引用。
       要件を承認する場合は単独行で APPROVE と書く -->
  """

  @impl true
  def complete(messages, opts) do
    human = Keyword.fetch!(opts, :human)
    pending_path = pending_path(human)

    cond do
      not File.exists?(pending_path) ->
        File.mkdir_p!(Path.dirname(pending_path))
        File.write!(pending_path, render_pending(messages))
        {:error, :awaiting_human}

      response_empty?(File.read!(pending_path)) ->
        {:error, :awaiting_human}

      true ->
        json = parse_response(File.read!(pending_path), human) |> Jason.encode!()
        move_to_done!(pending_path)
        {:ok, json}
    end
  end

  def pending_path(human) do
    pending_dir = Map.fetch!(human, :pending_dir)
    actor_id = Map.fetch!(human, :actor_id)
    stage = Map.fetch!(human, :stage)

    Path.join(pending_dir, "#{actor_id}-#{stage}.md")
  end

  defp render_pending(messages) do
    messages
    |> Enum.map_join("\n\n", fn message ->
      role = message_value(message, :role, "user") |> String.upcase()
      content = message_value(message, :content, "")
      "## #{role}\n\n#{String.trim(content)}"
    end)
    |> Kernel.<>(@response_template)
  end

  defp response_empty?(content) do
    content
    |> response_body()
    |> strip_html_comments()
    |> String.trim()
    |> Kernel.==("")
  end

  defp parse_response(content, human) do
    question_ids = human |> Map.get(:question_ids, []) |> MapSet.new()
    approve_targets = human |> Map.get(:approve_targets, []) |> Enum.map(&to_string/1)

    entries =
      content
      |> response_body()
      |> strip_html_comments()
      |> String.split("\n")
      |> Enum.flat_map(&parse_response_line(&1, question_ids, approve_targets))

    %{"entries" => entries}
  end

  defp parse_response_line(line, question_ids, approve_targets) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        []

      trimmed == "APPROVE" ->
        [
          %{
            "type" => "decision",
            "text" => "要件を承認する",
            "citations" => approve_targets
          }
        ]

      match = Regex.run(~r/^\s*[-*]\s+(?<text>.+?)\s*$/u, line, capture: :all_names) ->
        [raw_text] = match
        citations = citations(raw_text)

        [
          %{
            "type" =>
              if(Enum.any?(citations, &MapSet.member?(question_ids, &1)),
                do: "answer",
                else: "observation"
              ),
            "text" => clean_citations(raw_text),
            "citations" => citations
          }
        ]

      true ->
        []
    end
  end

  defp citations(text) do
    ~r/\[(e\d+)\]/u
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp clean_citations(text) do
    text
    |> String.replace(~r/\s*\[e\d+\]/u, "")
    |> String.trim()
  end

  defp response_body(content) do
    case String.split(content, @response_heading, parts: 2) do
      [_before, after_heading] -> after_heading
      [_all] -> ""
    end
  end

  defp strip_html_comments(text) do
    String.replace(text, ~r/<!--[\s\S]*?-->/u, "")
  end

  defp move_to_done!(pending_path) do
    done_dir = Path.join(Path.dirname(pending_path), "done")
    File.mkdir_p!(done_dir)
    File.rename!(pending_path, done_path(done_dir, Path.basename(pending_path)))
  end

  defp done_path(done_dir, basename) do
    path = Path.join(done_dir, basename)

    if File.exists?(path) do
      ext = Path.extname(basename)
      root = Path.rootname(basename)
      Path.join(done_dir, "#{root}-#{System.unique_integer([:positive])}#{ext}")
    else
      path
    end
  end

  defp message_value(%{} = message, key, default) do
    Map.get(message, key, Map.get(message, to_string(key), default))
  end

  defp message_value(_message, _key, default), do: default
end
