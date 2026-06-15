defmodule Tracefield.LLM.Ollama do
  @moduledoc """
  Ollama chat adapter.
  """

  @behaviour Tracefield.LLM

  @impl true
  def complete(messages, opts) do
    model = Keyword.get(opts, :model, "gemma4:12b")
    timeout = Keyword.get(opts, :timeout, 300_000)
    think = Keyword.get(opts, :think, false)
    tools? = Keyword.has_key?(opts, :tools)

    body = %{
      model: model,
      messages: messages,
      stream: false,
      think: think,
      options: build_options(opts)
    }

    body =
      if tools? do
        Map.put(body, :tools, Keyword.fetch!(opts, :tools))
      else
        body
      end

    case Req.post("http://localhost:11434/api/chat",
           json: body,
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 1
         ) do
      {:ok, %{status: status, body: %{"message" => message}}}
      when status in 200..299 ->
        if tools? do
          %{tool_calls: tool_calls} = parse_tool_calls(message)
          {:ok, %{content: extract_content(message), tool_calls: tool_calls}}
        else
          {:ok, extract_content(message)}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:ollama_http_error, status, body}}

      {:error, %{reason: :econnrefused}} ->
        {:error, :ollama_unreachable}

      {:error, reason} ->
        {:error, {:ollama_error, reason}}
    end
  end

  def parse_tool_calls(message) when is_map(message) do
    message
    |> get_value(:tool_calls)
    |> normalize_tool_calls()
  end

  def parse_tool_calls(_message), do: %{tool_calls: [], malformed: []}

  # Reasoning models (e.g. gemma4) may emit an empty content with a populated
  # thinking field when num_predict is exhausted before the answer; prefer
  # content, fall back to thinking, then to "".
  defp extract_content(%{"content" => content}) when is_binary(content) and content != "",
    do: content

  defp extract_content(%{"thinking" => thinking}) when is_binary(thinking) and thinking != "",
    do: thinking

  defp extract_content(_message), do: ""

  def build_options(opts) do
    %{
      seed: Keyword.get(opts, :seed, 0),
      temperature: Keyword.get(opts, :temperature, 0.2),
      num_predict: Keyword.get(opts, :max_tokens, 1200),
      num_ctx: Keyword.get(opts, :num_ctx, 8192)
    }
  end

  defp normalize_tool_calls(calls) when is_list(calls) do
    Enum.reduce(calls, %{tool_calls: [], malformed: []}, fn call, acc ->
      case normalize_tool_call(call) do
        {:ok, normalized} ->
          %{acc | tool_calls: [normalized | acc.tool_calls]}

        {:error, malformed} ->
          %{acc | malformed: [malformed | acc.malformed]}
      end
    end)
    |> then(fn acc ->
      %{acc | tool_calls: Enum.reverse(acc.tool_calls), malformed: Enum.reverse(acc.malformed)}
    end)
  end

  defp normalize_tool_calls(_calls), do: %{tool_calls: [], malformed: []}

  defp normalize_tool_call(call) when is_map(call) do
    function = get_value(call, :function)
    name = get_value(function || call, :name)
    arguments = get_value(function || call, :arguments)

    with true <- is_binary(name),
         {:ok, args} <- normalize_arguments(arguments) do
      {:ok, %{name: name, arguments: args}}
    else
      _ -> {:error, malformed_tool_call(call, name, arguments)}
    end
  end

  defp normalize_tool_call(call), do: {:error, %{raw: call, reason: "tool_call is not a map"}}

  defp normalize_arguments(arguments) when is_map(arguments), do: {:ok, arguments}

  defp normalize_arguments(arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> :error
    end
  end

  defp normalize_arguments(_arguments), do: :error

  defp malformed_tool_call(call, name, arguments) do
    reason =
      cond do
        not is_binary(name) -> "tool_call function name is missing or not a string"
        not is_map(arguments) and not is_binary(arguments) -> "tool_call arguments are not a map"
        true -> "tool_call arguments are malformed"
      end

    %{raw: call, reason: reason}
  end

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp get_value(_map, _key), do: nil
end
