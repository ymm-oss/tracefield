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
end
