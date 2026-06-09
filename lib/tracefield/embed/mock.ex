defmodule Tracefield.Embed.Mock do
  @moduledoc """
  Deterministic char-trigram embedding adapter for tests and offline runs.
  """

  @behaviour Tracefield.Embed

  @dims 32

  @impl true
  def embed(texts, _opts) when is_list(texts) do
    {:ok, Enum.map(texts, &embed_text/1)}
  end

  defp embed_text(text) do
    text
    |> normalize_text()
    |> trigrams()
    |> Enum.reduce(List.duplicate(0.0, @dims), fn trigram, vector ->
      index = :erlang.phash2(trigram, @dims)
      sign = if rem(:erlang.phash2({trigram, :sign}), 2) == 0, do: 1.0, else: -1.0
      List.update_at(vector, index, &(&1 + sign))
    end)
    |> normalize_vector()
  end

  defp normalize_text(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp normalize_text(text), do: text |> to_string() |> normalize_text()

  defp trigrams(""), do: []

  defp trigrams(text) do
    chars = String.graphemes(text)

    if length(chars) < 3 do
      chars
    else
      chars
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.map(&Enum.join/1)
    end
  end

  defp normalize_vector(vector) do
    norm =
      vector
      |> Enum.map(&(&1 * &1))
      |> Enum.sum()
      |> :math.sqrt()

    if norm == 0.0 do
      vector
    else
      Enum.map(vector, &(&1 / norm))
    end
  end
end
