defmodule Tracefield.Tokens do
  @moduledoc """
  Deterministic prompt token estimates used for context-budget governance.
  """

  def estimate(text) when is_binary(text) do
    text
    |> String.length()
    |> div_ceil(3)
  end

  def estimate(text), do: text |> to_string() |> estimate()

  def estimate_messages(messages) when is_list(messages) do
    Enum.reduce(messages, 0, fn message, total ->
      content = Map.get(message, :content, Map.get(message, "content", ""))
      total + estimate(content)
    end)
  end

  defp div_ceil(0, _denominator), do: 0

  defp div_ceil(value, denominator) do
    div(value + denominator - 1, denominator)
  end
end
