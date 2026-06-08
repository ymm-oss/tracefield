defmodule Tracefield.Normalize do
  @moduledoc """
  Claim extraction, matching, and Jaccard distance over normalized claim clusters.
  """

  defmodule Claim do
    @moduledoc false
    defstruct [:id, :text, :kind, :raw_index]
  end

  @kinds [:concern, :recommendation, :final]

  @spec extract_claims(String.t(), keyword()) :: [%Claim{}]
  def extract_claims(raw_output, llm_opts \\ []) do
    case parse_claim_lines(raw_output) do
      [] -> extract_with_llm(raw_output, llm_opts)
      claims -> claims
    end
  end

  @spec match([%Claim{}], [%Claim{}], keyword()) :: %{a: MapSet.t(), b: MapSet.t()}
  def match(set_a, set_b, _llm_opts \\ []) do
    %{a: cluster_ids(set_a), b: cluster_ids(set_b)}
  end

  @spec diff([%Claim{}], [%Claim{}], keyword()) :: float()
  def diff(set_a, set_b, llm_opts \\ []) do
    %{a: a, b: b} = match(set_a, set_b, llm_opts)
    union = MapSet.union(a, b)

    if MapSet.size(union) == 0 do
      0.0
    else
      intersection = MapSet.intersection(a, b)
      1.0 - MapSet.size(intersection) / MapSet.size(union)
    end
  end

  def cluster_ids(claims) do
    claims
    |> Enum.map(&cluster_id/1)
    |> MapSet.new()
  end

  defp cluster_id(%Claim{id: id}) when is_binary(id) and id != "", do: id
  defp cluster_id(%Claim{text: text}), do: normalize_text(text)

  defp extract_with_llm(raw_output, llm_opts) do
    messages = [
      %{role: "system", content: "TRACEFIELD_EXTRACT_CLAIMS"},
      %{
        role: "user",
        content:
          "Extract atomic claims and recommendations as JSON objects with id, text, kind, raw_index.\nRAW_OUTPUT:\n#{raw_output}"
      }
    ]

    case Tracefield.LLM.complete(messages, llm_opts) do
      {:ok, content} -> parse_claim_json(content, raw_output)
      {:error, _reason} -> fallback_line_claims(raw_output)
    end
  end

  defp parse_claim_json(content, raw_output) do
    case Jason.decode(content) do
      {:ok, list} when is_list(list) ->
        list
        |> Enum.with_index(1)
        |> Enum.map(fn {item, index} -> claim_from_map(item, index) end)
        |> Enum.reject(&is_nil/1)

      _ ->
        fallback_line_claims(raw_output)
    end
  end

  defp claim_from_map(%{} = item, index) do
    kind = item["kind"] || item[:kind] || "concern"
    text = item["text"] || item[:text]

    with true <- is_binary(text),
         {:ok, kind_atom} <- parse_kind(kind) do
      %Claim{
        id: item["id"] || item[:id] || normalize_text(text),
        text: text,
        kind: kind_atom,
        raw_index: item["raw_index"] || item[:raw_index] || index
      }
    else
      _ -> nil
    end
  end

  defp claim_from_map(_item, _index), do: nil

  defp parse_kind(kind) when is_atom(kind) and kind in @kinds, do: {:ok, kind}

  defp parse_kind(kind) when is_binary(kind) do
    atom = String.to_existing_atom(kind)
    if atom in @kinds, do: {:ok, atom}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp parse_kind(_kind), do: :error

  defp parse_claim_lines(text) do
    regex =
      ~r/CLAIM\[(?<id>[^\]]+)\]\s+(?<kind>concern|recommendation|final):\s+(?<text>.*?)(?:\s+\(raw_index=\d+\))?$/

    text
    |> String.split("\n", trim: true)
    |> Enum.reduce({[], 0}, fn line, {claims, index} ->
      case Regex.named_captures(regex, line) do
        nil ->
          {claims, index}

        %{"id" => id, "kind" => kind, "text" => claim_text} ->
          next_index = index + 1

          claim = %Claim{
            id: id,
            text: claim_text,
            kind: String.to_existing_atom(kind),
            raw_index: next_index
          }

          {[claim | claims], next_index}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp fallback_line_claims(raw_output) do
    raw_output
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index(1)
    |> Enum.map(fn {line, index} ->
      %Claim{id: normalize_text(line), text: line, kind: :concern, raw_index: index}
    end)
  end

  defp normalize_text(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^[:alnum:]]+/u, "-")
    |> String.trim("-")
  end
end
