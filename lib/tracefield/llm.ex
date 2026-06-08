defmodule Tracefield.LLM do
  @moduledoc """
  Behaviour and facade for chat-completion adapters.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type opts :: [
          model: String.t(),
          seed: integer(),
          temperature: float(),
          max_tokens: pos_integer(),
          timeout: pos_integer()
        ]

  @callback complete(messages :: [message()], opts()) :: {:ok, String.t()} | {:error, term()}

  @spec complete([message()], opts()) :: {:ok, String.t()} | {:error, term()}
  def complete(messages, opts \\ []) do
    adapter =
      Keyword.get(
        opts,
        :adapter,
        Application.get_env(:tracefield, :llm_adapter, Tracefield.LLM.Mock)
      )

    adapter.complete(messages, Keyword.delete(opts, :adapter))
  end
end
