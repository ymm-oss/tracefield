defmodule Tracefield.Stance do
  @moduledoc """
  Topic-level stance comparison between two blind claim groups.
  """

  @type assessment :: %{differs: boolean(), g1: String.t(), g2: String.t()}

  @spec assess(String.t(), [String.t()], [String.t()], keyword()) :: assessment()
  def assess(topic_label, group1_texts, group2_texts, llm_opts \\ []) do
    messages = [
      %{role: "system", content: "TRACEFIELD_STANCE"},
      %{
        role: "user",
        content:
          "Two blind groups contain claims about the same topic. Summarize each group's conclusion or stance in one line, then decide whether the groups have materially different positions, conclusions, or recommendations, such as opposite conclusions or reversed recommendations. Return only JSON in this exact shape: {\"g1\":\"...\",\"g2\":\"...\",\"differs\":true}.\n\nTOPIC:\n#{topic_label}\n\nGROUP 1 CLAIMS:\n#{format_claim_texts(group1_texts)}\n\nGROUP 2 CLAIMS:\n#{format_claim_texts(group2_texts)}"
      }
    ]

    case Tracefield.LLM.complete(messages, llm_opts) do
      {:ok, content} -> parse_assessment(content)
      {:error, _reason} -> fallback()
    end
  end

  defp parse_assessment(content) do
    with {:ok, %{} = decoded} <- decode_json_object(content),
         differs when is_boolean(differs) <- decoded["differs"],
         g1 when is_binary(g1) <- decoded["g1"],
         g2 when is_binary(g2) <- decoded["g2"] do
      %{differs: differs, g1: String.trim(g1), g2: String.trim(g2)}
    else
      _ -> fallback()
    end
  end

  defp fallback, do: %{differs: false, g1: "", g2: ""}

  defp decode_json_object(content) do
    with {:error, _reason} <- Jason.decode(content),
         {:ok, object_text} <- extract_object_text(content) do
      Jason.decode(object_text)
    end
  end

  defp extract_object_text(content) do
    start = :binary.match(content, "{")

    finish =
      content
      |> String.reverse()
      |> :binary.match("}")

    case {start, finish} do
      {{start_index, 1}, {reverse_index, 1}} ->
        end_index = byte_size(content) - reverse_index - 1

        if end_index >= start_index do
          {:ok, binary_part(content, start_index, end_index - start_index + 1)}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp format_claim_texts([]), do: "(none)"

  defp format_claim_texts(texts) do
    texts
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {text, index} ->
      "#{index}. #{String.replace(text, "\n", " ")}"
    end)
  end
end
