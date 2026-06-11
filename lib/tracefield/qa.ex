defmodule Tracefield.QA do
  @moduledoc """
  LLM-assisted acceptance-criteria matching for the QA stage.
  """

  @type judgment :: %{matched: boolean(), note: String.t()}

  @spec judge(module(), keyword(), map(), map(), map()) :: judgment()
  def judge(adapter, llm_opts, requirement, change, test_result) do
    messages = [%{role: "user", content: build_prompt(requirement, change, test_result)}]

    case adapter.complete(messages, llm_opts) do
      {:ok, content} -> parse_judgment(content, test_result)
      {:error, _reason} -> fallback(test_result)
    end
  end

  defp build_prompt(requirement, change, test_result) do
    files =
      change.meta
      |> Map.get(:files, Map.get(change.meta, "files", []))
      |> List.wrap()

    """
    TRACEFIELD_QA

    要件:
    #{requirement.id}: #{requirement.text}

    実装変更:
    #{change.text}
    files: #{Enum.join(files, ", ")}

    テスト結果:
    exit: #{test_result.exit}
    #{test_result.tail}

    この変更は要件の受入基準を満たすか。JSON `{"matched": true|false, "note": "…"}` のみ返せ。
    """
    |> String.trim()
  end

  defp parse_judgment(content, test_result) do
    with {:ok, %{} = decoded} <- decode_json_object(content),
         matched when is_boolean(matched) <- json_bool(decoded, "matched"),
         note when is_binary(note) <- json_string(decoded, "note") do
      %{matched: matched, note: String.trim(note)}
    else
      _ -> fallback(test_result)
    end
  end

  defp fallback(test_result) do
    %{matched: test_result.exit == 0, note: "judge unavailable"}
  end

  defp json_bool(map, key) do
    case Map.get(map, key, Map.get(map, String.to_atom(key))) do
      value when is_boolean(value) -> value
      _ -> :error
    end
  end

  defp json_string(map, key) do
    case Map.get(map, key, Map.get(map, String.to_atom(key))) do
      value when is_binary(value) -> value
      value when not is_nil(value) -> to_string(value)
      _ -> ""
    end
  end

  defp decode_json_object(content) do
    with {:error, _reason} <- Jason.decode(content),
         {:ok, object_text} <- extract_object_text(content) do
      Jason.decode(object_text)
    end
  end

  defp extract_object_text(content) do
    start = :binary.match(content, "{")
    finish = content |> String.reverse() |> :binary.match("}")

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
end
