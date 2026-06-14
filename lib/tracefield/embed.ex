defmodule Tracefield.Embed do
  @moduledoc """
  Behaviour and facade for embedding adapters.
  """

  @type opts :: [
          model: String.t(),
          timeout: pos_integer()
        ]

  @callback embed(texts :: [String.t()], opts()) :: {:ok, [[float()]]} | {:error, term()}

  @spec embed([String.t()], opts()) :: {:ok, [[float()]]} | {:error, term()}
  def embed(texts, opts \\ []) when is_list(texts) do
    adapter =
      Keyword.get(
        opts,
        :adapter,
        Application.get_env(:tracefield, :embed_adapter, Tracefield.Embed.Mock)
      )

    adapter.embed(texts, Keyword.delete(opts, :adapter))
  end

  @spec cosine([number()], [number()]) :: float()
  def cosine(left, right) when is_list(left) and is_list(right) do
    {dot, norm_left, norm_right} =
      Enum.zip(left, right)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {a, b}, {dot, norm_left, norm_right} ->
        a = a * 1.0
        b = b * 1.0
        {dot + a * b, norm_left + a * a, norm_right + b * b}
      end)

    if norm_left == 0.0 or norm_right == 0.0 do
      0.0
    else
      dot
      |> Kernel./(:math.sqrt(norm_left) * :math.sqrt(norm_right))
      |> min(1.0)
      |> max(-1.0)
    end
  end

  @spec centroid([[number()]]) :: [float()]
  def centroid([]), do: []

  def centroid(vectors) when is_list(vectors) do
    dims = vectors |> hd() |> length()

    vectors
    |> Enum.reduce(List.duplicate(0.0, dims), fn vector, acc ->
      Enum.zip_with(acc, vector, &(&1 + &2))
    end)
    |> Enum.map(&(&1 / length(vectors)))
    |> normalize_vector()
  end

  defp normalize_vector(vector) do
    norm =
      vector
      |> Enum.map(&(&1 * &1))
      |> Enum.sum()
      |> :math.sqrt()

    if norm == 0.0, do: vector, else: Enum.map(vector, &(&1 / norm))
  end
end
