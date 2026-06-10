defmodule Tracefield.Discovery do
  @moduledoc """
  Scores whether absorbed entries discover planted private-document interactions.
  """

  @interactions [
    %{
      id: "I1",
      fact_a: "監査ログは全文を90日間保持する",
      fact_b: "72時間以内に完全削除とユーザーに表示している",
      keywords: ["retention-90d", "delete-72h"]
    },
    %{
      id: "I2",
      fact_a: "Q3から顧客ログでアップセル推薦を開始する",
      fact_b: "顧客ログへのアクセスはサポート障害対応に限定される",
      keywords: ["upsell-q3", "access-support-only"]
    },
    %{
      id: "I3",
      fact_a: "会話はAIの学習に使われないと約束している",
      fact_b: "顧客対話ログでファインチューニングする計画がある",
      keywords: ["no-training-promise", "finetune-plan"]
    }
  ]

  def interactions, do: @interactions

  def strict_score(entries) do
    entries = List.wrap(entries)

    per_interaction =
      @interactions
      |> Map.new(fn interaction ->
        {interaction.id, strict_discovered?(entries, interaction.keywords)}
      end)

    discovered =
      per_interaction
      |> Enum.filter(fn {_id, value} -> value end)
      |> Enum.map(fn {id, _value} -> id end)
      |> MapSet.new()

    %{
      discovered: discovered,
      count: MapSet.size(discovered),
      per_interaction: per_interaction
    }
  end

  def score(entries, opts \\ []) do
    entries = List.wrap(entries)

    judgments =
      case entries do
        [] -> %{}
        _ -> judge(entries, opts)
      end

    per_interaction =
      @interactions
      |> Enum.with_index(1)
      |> Map.new(fn {interaction, index} ->
        value = discovered?(judgments, interaction.id, index)
        {interaction.id, value}
      end)

    discovered =
      per_interaction
      |> Enum.filter(fn {_id, value} -> value end)
      |> Enum.map(fn {id, _value} -> id end)
      |> MapSet.new()

    %{
      discovered: discovered,
      count: MapSet.size(discovered),
      per_interaction: per_interaction
    }
  end

  defp strict_discovered?(entries, keywords) do
    Enum.any?(entries, fn entry ->
      text = entry_value(entry, :text, "")
      Enum.all?(keywords, &String.contains?(text, &1))
    end)
  end

  defp judge(entries, opts) do
    adapter =
      Keyword.get(opts, :judge_adapter, Keyword.get(opts, :adapter, Tracefield.LLM.Mock))

    model = Keyword.get(opts, :judge_model, Keyword.get(opts, :model, "mock"))

    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_DISCOVERY\nFor each interaction, judge whether any numbered entry explicitly mentions both facts and points out the contradiction or interaction. Return only JSON {\"1\":{\"discovered\":true,\"entry\":3},...}."
      },
      %{
        role: "user",
        content:
          Enum.join(
            [
              "INTERACTIONS:",
              format_interactions(),
              "",
              "ENTRIES:",
              format_entries(entries)
            ],
            "\n"
          )
      }
    ]

    llm_opts = [
      adapter: adapter,
      model: model,
      temperature: Keyword.get(opts, :temperature, 0.0),
      seed: Keyword.get(opts, :seed, 0)
    ]

    case Tracefield.LLM.complete(messages, llm_opts) do
      {:ok, content} -> parse_judgments(content)
      {:error, _reason} -> %{}
    end
  end

  defp format_interactions do
    @interactions
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {interaction, index} ->
      [kw_a, kw_b] = interaction.keywords

      "#{index}. #{interaction.id} fact_a=#{interaction.fact_a} fact_b=#{interaction.fact_b} keywords=#{kw_a},#{kw_b}"
    end)
  end

  defp format_entries(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {entry, index} ->
      "#{index}. entry_id=#{entry_value(entry, :id, "")} text=#{entry_value(entry, :text, "")}"
    end)
  end

  defp discovered?(judgments, id, index) do
    value =
      Map.get(judgments, Integer.to_string(index)) ||
        Map.get(judgments, index) ||
        Map.get(judgments, id)

    normalize_discovered(value)
  end

  defp normalize_discovered(%{} = value) do
    Map.get(value, "discovered", Map.get(value, :discovered, false)) == true
  end

  defp normalize_discovered(true), do: true
  defp normalize_discovered(_value), do: false

  defp parse_judgments(content) when is_binary(content) do
    with {:ok, %{} = decoded} <- decode_json_object(content) do
      decoded
    else
      _ -> %{}
    end
  end

  defp parse_judgments(_content), do: %{}

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

  defp entry_value(%{} = entry, key, default) do
    Map.get(entry, key, Map.get(entry, to_string(key), default))
  end

  defp entry_value(_entry, _key, default), do: default
end
