defmodule Tracefield.Embed.Ollama do
  @moduledoc """
  Ollama embedding adapter.
  """

  @behaviour Tracefield.Embed

  @impl true
  def embed(texts, opts) when is_list(texts) do
    model = Keyword.get(opts, :model, "nomic-embed-text")
    timeout = Keyword.get(opts, :timeout, 300_000)

    body = %{
      model: model,
      input: texts
    }

    case Req.post("http://localhost:11434/api/embed",
           json: body,
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 1
         ) do
      {:ok, %{status: status, body: %{"embeddings" => embeddings}}}
      when status in 200..299 and is_list(embeddings) ->
        {:ok, embeddings}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ollama_http_error, status, body}}

      {:error, %{reason: :econnrefused}} ->
        {:error, :ollama_unreachable}

      {:error, reason} ->
        {:error, {:ollama_error, reason}}
    end
  end
end
