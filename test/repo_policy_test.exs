defmodule Tracefield.RepoPolicyTest do
  use ExUnit.Case, async: true

  alias Tracefield.Policy

  test "repository policy is valid and defaults git mode to branch" do
    policy =
      ".tracefield/policy.json"
      |> File.read!()
      |> Jason.decode!()

    assert Policy.validate_top_keys!(policy) == :ok
    assert get_in(policy, ["git", "mode"]) == "branch"
  end
end
