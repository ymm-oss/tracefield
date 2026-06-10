defmodule Tracefield.TokensTest do
  use ExUnit.Case

  test "estimate is deterministic and monotonic" do
    assert Tracefield.Tokens.estimate("") == 0
    assert Tracefield.Tokens.estimate("abc") == 1
    assert Tracefield.Tokens.estimate("abcd") == 2

    assert Tracefield.Tokens.estimate(String.duplicate("a", 30)) >
             Tracefield.Tokens.estimate(String.duplicate("a", 12))
  end

  test "estimate_messages sums message content estimates" do
    messages = [
      %{role: "system", content: "abc"},
      %{"role" => "user", "content" => "abcdef"},
      %{role: "assistant", content: ""}
    ]

    assert Tracefield.Tokens.estimate_messages(messages) == 3
  end
end
