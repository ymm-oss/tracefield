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
    num_predict = Keyword.get(opts, :max_tokens, 1200)
    think = Keyword.get(opts, :think, false)

    body = %{
      model: model,
      messages: messages,
      stream: false,
      think: think,
      options: %{seed: seed, temperature: temperature, num_predict: num_predict}
    }

    case Req.post("http://localhost:11434/api/chat",
           json: body,
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 1
         ) do
      {:ok, %{status: status, body: %{"message" => message}}}
      when status in 200..299 ->
        {:ok, extract_content(message)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ollama_http_error, status, body}}

      {:error, %{reason: :econnrefused}} ->
        {:error, :ollama_unreachable}

      {:error, reason} ->
        {:error, {:ollama_error, reason}}
    end
  end

  # Reasoning models (e.g. gemma4) may emit an empty content with a populated
  # thinking field when num_predict is exhausted before the answer; prefer
  # content, fall back to thinking, then to "".
  defp extract_content(%{"content" => content}) when is_binary(content) and content != "",
    do: content

  defp extract_content(%{"thinking" => thinking}) when is_binary(thinking) and thinking != "",
    do: thinking

  defp extract_content(_message), do: ""
end
