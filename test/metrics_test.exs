defmodule Tracefield.MetricsTest do
  use ExUnit.Case, async: true

  alias Tracefield.Metrics

  test "auc is near 1.0 for clearly separated distributions" do
    assert_in_delta Metrics.auc([0.0, 0.1, 0.2], [0.8, 0.9, 1.0]), 1.0, 0.0001
  end

  test "auc is near 0.5 for equal distributions" do
    samples = [0.1, 0.2, 0.3]
    assert_in_delta Metrics.auc(samples, samples), 0.5, 0.0001
  end

  test "cliffs_delta is positive when between is larger" do
    assert Metrics.cliffs_delta([0.1, 0.2], [0.8, 0.9]) > 0.0
  end

  test "prf matches hand-checked precision and recall" do
    result = Metrics.prf(MapSet.new(["a", "b", "c"]), MapSet.new(["b", "c", "x"]))

    assert_in_delta result.recall, 2 / 3, 0.0001
    assert_in_delta result.precision, 2 / 3, 0.0001
    assert_in_delta result.f1, 2 / 3, 0.0001
  end
end
