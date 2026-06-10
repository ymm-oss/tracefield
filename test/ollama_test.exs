defmodule Tracefield.LLM.OllamaTest do
  use ExUnit.Case

  alias Tracefield.LLM.Ollama

  test "build_options includes default num_ctx" do
    assert Ollama.build_options([]) == %{
             seed: 0,
             temperature: 0.2,
             num_predict: 1200,
             num_ctx: 8192
           }
  end

  test "build_options allows num_ctx and generation options to be overridden" do
    assert Ollama.build_options(seed: 7, temperature: 0.6, max_tokens: 400, num_ctx: 4096) ==
             %{
               seed: 7,
               temperature: 0.6,
               num_predict: 400,
               num_ctx: 4096
             }
  end
end
