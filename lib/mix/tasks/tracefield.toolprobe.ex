defmodule Mix.Tasks.Tracefield.Toolprobe do
  @moduledoc "Probe Ollama tool-call support with the local gemma model."
  use Mix.Task

  alias Tracefield.LLM.Ollama

  @default_model "gemma4:31b-it-qat"
  @default_runs 3

  @shortdoc "Probe Ollama tool-call behavior"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    args
    |> parse_args()
    |> run_probe()
  end

  def run_probe(opts) do
    model = Keyword.fetch!(opts, :model)
    runs = Keyword.fetch!(opts, :runs)
    tools = tools()

    Mix.shell().info("Tracefield ToolProbe")
    Mix.shell().info("model: #{model}")
    Mix.shell().info("runs: #{runs}")
    Mix.shell().info("seed: 0")
    Mix.shell().info("temperature: 0")
    Mix.shell().info("")

    results =
      1..runs
      |> Enum.map(fn run_index ->
        result = run_once(model, tools)
        print_run(run_index, runs, result)
        result
      end)

    summary = summarize(model, runs, results)
    Mix.shell().info(Jason.encode!(summary))
    summary
  end

  defp parse_args(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          runs: :integer,
          model: :string
        ]
      )

    [
      model: Keyword.get(opts, :model, @default_model),
      runs: max(Keyword.get(opts, :runs, @default_runs), 1)
    ]
  end

  defp run_once(model, tools) do
    case Ollama.complete(messages(), model: model, tools: tools, seed: 0, temperature: 0) do
      {:ok, %{content: content, tool_calls: tool_calls}} ->
        calls = Enum.map(tool_calls, &validate_tool_call/1)

        %{
          status: :ok,
          content: content,
          calls: calls,
          first_tool_name: first_tool_name(calls)
        }

      {:error, reason} ->
        %{status: :error, error: inspect(reason), calls: [], first_tool_name: nil}
    end
  end

  defp print_run(run_index, runs, %{status: :ok, content: content, calls: calls}) do
    Mix.shell().info("Run #{run_index}/#{runs}")
    Mix.shell().info("content: #{format_content(content)}")
    Mix.shell().info("tool_call_count: #{length(calls)}")

    if calls == [] do
      Mix.shell().info("- no tool_calls")
    else
      Enum.each(calls, fn call ->
        Mix.shell().info(format_call(call))
      end)
    end

    Mix.shell().info("")
  end

  defp print_run(run_index, runs, %{status: :error, error: error}) do
    Mix.shell().info("Run #{run_index}/#{runs}")
    Mix.shell().info("error: #{error}")
    Mix.shell().info("tool_call_count: 0")
    Mix.shell().info("")
  end

  defp format_call(%{name: name, arguments: arguments, valid?: true}) do
    "- #{name} arguments=#{inspect(arguments)} valid"
  end

  defp format_call(%{name: name, arguments: arguments, valid?: false, reason: reason}) do
    "- #{name} arguments=#{inspect(arguments)} malformed: #{reason}"
  end

  defp format_content(content) when is_binary(content) do
    content
    |> String.replace("\n", "\\n")
    |> String.slice(0, 500)
  end

  defp format_content(_content), do: ""

  defp first_tool_name([%{name: name} | _calls]) when is_binary(name), do: name
  defp first_tool_name(_calls), do: nil

  defp summarize(model, runs, results) do
    calls = Enum.flat_map(results, & &1.calls)
    valid_count = Enum.count(calls, & &1.valid?)
    malformed = Enum.reject(calls, & &1.valid?)
    first_names = Enum.map(results, & &1.first_tool_name)

    %{
      model: model,
      runs: runs,
      tool_call_count: length(calls),
      valid_count: valid_count,
      malformed_count: length(malformed),
      stable: stable?(first_names),
      malformed: Enum.map(malformed, &malformed_summary/1),
      errors: results |> Enum.filter(&match?(%{status: :error}, &1)) |> Enum.map(& &1.error)
    }
  end

  defp stable?(names) do
    Enum.all?(names, &is_binary/1) and length(Enum.uniq(names)) == 1
  end

  defp malformed_summary(%{name: name, arguments: arguments, reason: reason}) do
    %{name: name, arguments: arguments, reason: reason}
  end

  defp validate_tool_call(%{name: "serve", arguments: %{"query" => query}} = call)
       when is_binary(query) do
    Map.merge(call, %{valid?: true})
  end

  defp validate_tool_call(%{name: "absorb", arguments: arguments} = call)
       when is_map(arguments) do
    with true <- is_binary(Map.get(arguments, "content")),
         true <- is_binary(Map.get(arguments, "type")),
         citations when is_list(citations) <- Map.get(arguments, "citations"),
         true <- Enum.all?(citations, &valid_citation?/1) do
      Map.merge(call, %{valid?: true})
    else
      _ ->
        malformed(
          call,
          "absorb arguments must include content, type, and citations[{id, stance}]"
        )
    end
  end

  defp validate_tool_call(%{name: name} = call) when name in ["serve", "absorb"] do
    malformed(call, "#{name} arguments do not match the declared schema")
  end

  defp validate_tool_call(call) do
    malformed(call, "unknown tool name")
  end

  defp valid_citation?(%{"id" => id, "stance" => stance}) do
    is_binary(id) and stance in ["relies_on", "refutes", "context"]
  end

  defp valid_citation?(_citation), do: false

  defp malformed(call, reason) do
    call
    |> Map.take([:name, :arguments])
    |> Map.put_new(:name, "<missing>")
    |> Map.put_new(:arguments, %{})
    |> Map.merge(%{valid?: false, reason: reason})
  end

  defp messages do
    [
      %{
        role: "system",
        content:
          "You are an agent collaborating through a shared knowledge store. Use tools instead of prose when tools are available."
      },
      %{
        role: "user",
        content:
          "First search for relevant information about local agent coordination, then write one concise finding into the store with cited source entries."
      }
    ]
  end

  defp tools do
    [
      %{
        type: "function",
        function: %{
          name: "serve",
          description: "Retrieve entries from the shared knowledge store matching a query.",
          parameters: %{
            type: "object",
            properties: %{
              query: %{type: "string"}
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "absorb",
          description:
            "Write a new entry into the store, citing source entries with a stance (relies_on / refutes / context).",
          parameters: %{
            type: "object",
            properties: %{
              content: %{type: "string"},
              type: %{type: "string"},
              citations: %{
                type: "array",
                items: %{
                  type: "object",
                  properties: %{
                    id: %{type: "string"},
                    stance: %{type: "string", enum: ["relies_on", "refutes", "context"]}
                  },
                  required: ["id", "stance"]
                }
              }
            },
            required: ["content", "type", "citations"]
          }
        }
      }
    ]
  end
end
