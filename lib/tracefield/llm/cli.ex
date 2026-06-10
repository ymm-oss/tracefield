defmodule Tracefield.LLM.CLI do
  @moduledoc """
  Plain prompt CLI adapter.

  The adapter ignores seed and temperature because shell CLIs are not assumed to
  expose deterministic sampling controls.
  """

  @behaviour Tracefield.LLM

  @timeout 300_000

  @impl true
  def complete(messages, opts) do
    {cmd, base_args} = Keyword.get(opts, :cli, {"claude", ["-p"]})
    model = Keyword.get(opts, :model)
    prompt = prompt_text(messages)
    args = maybe_append_model(cmd, base_args, model) ++ [prompt]

    task =
      Task.async(fn ->
        System.cmd(cmd, args, stderr_to_stdout: true)
      end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {stdout, 0}} ->
        {:ok, String.trim(stdout)}

      {:ok, {output, code}} ->
        {:error, {:cli_error, code, output |> to_string() |> String.slice(0, 200)}}

      nil ->
        {:error, :cli_timeout}
    end
  end

  defp prompt_text(messages) do
    system =
      messages
      |> Enum.filter(&(message_role(&1) == "system"))
      |> Enum.map_join("\n", &message_content/1)

    user =
      messages
      |> Enum.reject(&(message_role(&1) == "system"))
      |> Enum.map_join("\n", &message_content/1)

    [system, user]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp message_role(message), do: Map.get(message, :role, Map.get(message, "role", "user"))
  defp message_content(message), do: Map.get(message, :content, Map.get(message, "content", ""))

  defp maybe_append_model("claude", base_args, model) when is_binary(model) and model != "" do
    base_args ++ ["--model", model]
  end

  defp maybe_append_model(_cmd, base_args, _model), do: base_args
end
