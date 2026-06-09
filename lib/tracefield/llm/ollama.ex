defmodule Tracefield.LLM.Ollama do
  @moduledoc """
  Ollama chat adapter.
  """

  @behaviour Tracefield.LLM

  @impl true
  def complete(messages, opts) do
    model = Keyword.get(opts, :model, "gemma4:12b")
    seed = Keyword.get(opts, :seed, 0)
    temperature = Keyword.get(opts, :temperature, 0.2)
    timeout = Keyword.get(opts, :timeout, 300_000)
    num_predict = Keyword.get(opts, :max_tokens, 600)

    body = %{
      model: model,
      messages: messages,
      stream: false,
      options: %{seed: seed, temperature: temperature, num_predict: num_predict}
    }

    case Req.post("http://localhost:11434/api/chat",
           json: body,
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 1
         ) do
      {:ok, %{status: status, body: %{"message" => %{"content" => content}}}}
      when status in 200..299 ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ollama_http_error, status, body}}

      {:error, %{reason: :econnrefused}} ->
        {:error, :ollama_unreachable}

      {:error, reason} ->
        {:error, {:ollama_error, reason}}
    end
  end
end
