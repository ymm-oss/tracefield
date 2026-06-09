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

  @spec cluster([%{ref: String.t(), text: String.t()}], keyword()) :: %{
          String.t() => String.t()
        }
  def cluster(claim_refs, llm_opts \\ []) do
    claim_refs = Enum.filter(claim_refs, &valid_claim_ref?/1)

    if claim_refs == [] do
      %{}
    else
      messages = [
        %{role: "system", content: "TRACEFIELD_CLUSTER"},
        %{
          role: "user",
          content:
            "Assign each numbered claim a short kebab cluster label. Claims that are semantically equivalent must receive the same label. Return only a JSON array of label strings in index order.\n\nCLAIMS:\n#{format_claim_refs(claim_refs)}"
        }
      ]

      case Tracefield.LLM.complete(messages, llm_opts) do
        {:ok, content} ->
          case parse_cluster_json(content, length(claim_refs)) do
            {:ok, labels} -> refs_to_clusters(claim_refs, labels)
            :error -> independent_clusters(claim_refs)
          end

        {:error, _reason} ->
          independent_clusters(claim_refs)
      end
    end
  end

  @spec diff(Enumerable.t(), Enumerable.t()) :: float()
  def diff(set_a, set_b) do
    a = MapSet.new(set_a)
    b = MapSet.new(set_b)
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
          "Extract only atomic concerns or recommendations from RAW_OUTPUT. Return only a JSON array of objects with text and kind. kind must be one of concern, recommendation, final. Do not include headings, blank items, prefaces, or summaries.\n\nRAW_OUTPUT:\n#{raw_output}"
      }
    ]

    case Tracefield.LLM.complete(messages, llm_opts) do
      {:ok, content} -> parse_claim_json(content, raw_output)
      {:error, _reason} -> []
    end
  end

  defp parse_claim_json(content, _raw_output) do
    case decode_json_array(content) do
      {:ok, list} when is_list(list) ->
        list
        |> Enum.with_index(1)
        |> Enum.map(fn {item, index} -> claim_from_map(item, index) end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp claim_from_map(%{} = item, index) do
    kind = item["kind"] || item[:kind] || "concern"
    text = item["text"] || item[:text]

    with true <- is_binary(text),
         text <- String.trim(text),
         false <- discard_text?(text),
         {:ok, kind_atom} <- parse_kind(kind) do
      %Claim{
        id: "c#{index}",
        text: text,
        kind: kind_atom,
        raw_index: parse_raw_index(item["raw_index"] || item[:raw_index], index)
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

        %{"id" => _id, "kind" => kind, "text" => claim_text} ->
          next_index = index + 1

          claim = %Claim{
            id: "c#{next_index}",
            text: String.trim(claim_text),
            kind: String.to_existing_atom(kind),
            raw_index: next_index
          }

          {[claim | claims], next_index}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp parse_cluster_json(content, expected_length) do
    with {:ok, labels} when is_list(labels) <- decode_json_array(content),
         true <- length(labels) == expected_length,
         true <- Enum.all?(labels, &valid_cluster_label?/1) do
      {:ok, Enum.map(labels, &String.trim/1)}
    else
      _ -> :error
    end
  end

  defp decode_json_array(content) do
    with {:error, _reason} <- Jason.decode(content),
         {:ok, array_text} <- extract_array_text(content) do
      Jason.decode(array_text)
    end
  end

  defp extract_array_text(content) do
    start = :binary.match(content, "[")

    finish =
      content
      |> String.reverse()
      |> :binary.match("]")

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

  defp valid_cluster_label?(label), do: is_binary(label) and String.trim(label) != ""

  defp refs_to_clusters(claim_refs, labels) do
    claim_refs
    |> Enum.zip(labels)
    |> Map.new(fn {%{ref: ref}, label} -> {ref, label} end)
  end

  defp independent_clusters(claim_refs) do
    Map.new(claim_refs, fn %{ref: ref, text: text} -> {ref, normalize_text(text)} end)
  end

  defp format_claim_refs(claim_refs) do
    claim_refs
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {%{ref: ref, text: text}, index} ->
      "#{index}. [#{ref}] #{String.replace(text, "\n", " ")}"
    end)
  end

  defp valid_claim_ref?(%{ref: ref, text: text}) do
    is_binary(ref) and ref != "" and is_binary(text) and String.trim(text) != ""
  end

  defp valid_claim_ref?(_claim_ref), do: false

  defp parse_raw_index(index, _default) when is_integer(index) and index > 0, do: index

  defp parse_raw_index(index, default) when is_binary(index) do
    case Integer.parse(index) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp parse_raw_index(_index, default), do: default

  defp discard_text?(text) do
    text == "" or markdown_heading?(text) or heading_label?(text)
  end

  defp markdown_heading?(text), do: String.match?(text, ~r/^\s{0,3}#+\s+\S/)

  defp heading_label?(text) do
    String.ends_with?(text, ":") and String.length(text) <= 80 and
      not String.contains?(text, ".")
  end

  defp normalize_text(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^[:alnum:]]+/u, "-")
    |> String.trim("-")
  end
end
