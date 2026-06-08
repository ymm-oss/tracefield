defmodule Tracefield.NormalizeTest do
  use ExUnit.Case, async: true

  alias Tracefield.Normalize

  test "diff returns 0.0 for identical sets" do
    claims = claims(["a", "b"])
    assert Normalize.diff(claims, claims) == 0.0
  end

  test "diff returns 1.0 for disjoint sets" do
    assert Normalize.diff(claims(["a", "b"]), claims(["c", "d"])) == 1.0
  end

  test "diff returns 0.5 for half-overlap by Jaccard distance" do
    assert_in_delta Normalize.diff(claims(["a", "b", "c"]), claims(["a", "b", "d"]), 0.5),
                    0.5,
                    0.0001
  end

  defp claims(ids) do
    ids
    |> Enum.with_index(1)
    |> Enum.map(fn {id, index} ->
      %Normalize.Claim{id: id, text: "claim #{id}", kind: :concern, raw_index: index}
    end)
  end
end
