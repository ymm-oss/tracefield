defmodule Tracefield.ToolprobeTest do
  use ExUnit.Case

  alias Tracefield.LLM.Ollama

  test "parse_tool_calls returns normalized valid tool calls" do
    message = %{
      "tool_calls" => [
        %{
          "function" => %{
            "name" => "serve",
            "arguments" => %{"query" => "coordination"}
          }
        }
      ]
    }

    assert Ollama.parse_tool_calls(message) == %{
             tool_calls: [%{name: "serve", arguments: %{"query" => "coordination"}}],
             malformed: []
           }
  end

  test "parse_tool_calls treats missing tool_calls as an empty list" do
    assert Ollama.parse_tool_calls(%{"content" => "plain answer"}) == %{
             tool_calls: [],
             malformed: []
           }
  end

  test "parse_tool_calls treats empty tool_calls as an empty list" do
    assert Ollama.parse_tool_calls(%{"tool_calls" => []}) == %{
             tool_calls: [],
             malformed: []
           }
  end

  test "parse_tool_calls reports malformed arguments" do
    raw_call = %{
      "function" => %{
        "name" => "absorb",
        "arguments" => "[not-json"
      }
    }

    assert Ollama.parse_tool_calls(%{"tool_calls" => [raw_call]}) == %{
             tool_calls: [],
             malformed: [
               %{
                 raw: raw_call,
                 reason: "tool_call arguments are malformed"
               }
             ]
           }
  end
end
