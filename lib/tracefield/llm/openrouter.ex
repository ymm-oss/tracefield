defmodule Tracefield.LLM.OpenRouter do
  @moduledoc """
  OpenRouter chat adapter (OpenAI-compatible).

  Routes each agent to any model family via OpenRouter, enabling cross-family
  substrate-heterogeneity runs — the clean test H1 could not run on local
  same-family gemma (see `docs/impl-brief-h1b-crossfamily-openrouter.md`).

  Requires the `OPENROUTER_API_KEY` environment variable. Per-agent model
  assignment reuses the `--substrate`/`--models` machinery in
  `mix tracefield.hetero` (model ids are OpenRouter slugs, e.g. "openai/gpt-5.5").
  """

  @behaviour Tracefield.LLM

  @endpoint "https://openrouter.ai/api/v1/chat/completions"

  @impl true
  def complete(messages, opts) do
    model = Keyword.get(opts, :model, "openai/gpt-5.5")
    timeout = Keyword.get(opts, :timeout, 300_000)

    case api_key() do
      {:ok, key} -> request(model, messages, opts, key, timeout)
      :error -> {:error, :openrouter_no_api_key}
    end
  end

  defp request(model, messages, opts, key, timeout) do
    body =
      %{
        model: model,
        messages: messages,
        temperature: Keyword.get(opts, :temperature, 0.4),
        max_tokens: Keyword.get(opts, :max_tokens, 1200)
      }
      |> maybe_put_seed(opts)

    case Req.post(@endpoint,
           json: body,
           auth: {:bearer, key},
           headers: [{"x-title", "tracefield"}],
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %{status: status, body: %{"choices" => choices}}} when status in 200..299 ->
        {:ok, extract_content(choices)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:openrouter_http_error, status, body}}

      {:error, reason} ->
        {:error, {:openrouter_error, reason}}
    end
  end

  defp api_key do
    case System.get_env("OPENROUTER_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> :error
    end
  end

  defp maybe_put_seed(body, opts) do
    case Keyword.get(opts, :seed) do
      seed when is_integer(seed) -> Map.put(body, :seed, seed)
      _ -> body
    end
  end

  defp extract_content([%{"message" => %{"content" => content}} | _])
       when is_binary(content),
       do: content

  defp extract_content(_choices), do: ""
end
