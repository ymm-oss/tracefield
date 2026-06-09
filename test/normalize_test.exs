defmodule Tracefield.NormalizeTest do
  use ExUnit.Case, async: true

  alias Tracefield.Normalize

  defmodule BadClusterAdapter do
    @behaviour Tracefield.LLM

    @impl true
    def complete(_messages, _opts), do: {:ok, "not json"}
  end

  test "diff returns 0.0 for identical sets" do
    clusters = MapSet.new(["a", "b"])
    assert Normalize.diff(clusters, clusters) == 0.0
  end

  test "diff returns 1.0 for disjoint sets" do
    assert Normalize.diff(MapSet.new(["a", "b"]), MapSet.new(["c", "d"])) == 1.0
  end

  test "diff returns 0.5 for half-overlap by Jaccard distance" do
    assert_in_delta Normalize.diff(MapSet.new(["a", "b", "c"]), MapSet.new(["a", "b", "d"])),
                    0.5,
                    0.0001
  end

  test "cluster falls back deterministically when LLM output is invalid" do
    assignments =
      Normalize.cluster(
        [
          %{ref: "a1|c1", text: "Same claim."},
          %{ref: "b1|c1", text: "Same claim."},
          %{ref: "a1|c2", text: "Different claim."}
        ],
        adapter: BadClusterAdapter
      )

    assert assignments == %{
             "a1|c1" => "same-claim",
             "b1|c1" => "same-claim",
             "a1|c2" => "different-claim"
           }
  end
end
