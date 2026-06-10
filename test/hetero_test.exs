defmodule Tracefield.HeteroTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Hetero

  test "mock e2e discovers private-document interactions only when procedure is adopted" do
    result =
      Hetero.run_experiment(
        adapter_name: "mock-test",
        adapter: Tracefield.LLM.Mock,
        seeds: 1,
        rounds: 2,
        ks: [2],
        kps: [0, 1],
        model: "mock",
        judge_model: "mock",
        embed_model: "nomic-embed-text",
        temperature: 0.4
      )

    by_kp = Map.new(result.runs, &{&1.kp, &1})

    assert by_kp[0].disc_strict == 0
    assert by_kp[1].disc_strict > by_kp[0].disc_strict
    assert is_integer(by_kp[1].icc)
    assert is_integer(by_kp[1].coverage)
    assert is_float(by_kp[1].diversity)
    assert is_float(by_kp[1].collapse_rate)
    assert [_ | _] = by_kp[1].perception
  end

  test "mock e2e covers serve by aware grid cells" do
    result =
      Hetero.run_experiment(
        adapter_name: "mock-test",
        adapter: Tracefield.LLM.Mock,
        seeds: 1,
        rounds: 2,
        ks: [2],
        kps: [1],
        serves: [:similar, :diverse],
        awares: [0, 1],
        model: "mock",
        judge_model: "mock",
        embed_model: "nomic-embed-text",
        temperature: 0.4
      )

    cells = MapSet.new(Enum.map(result.runs, &{&1.k, &1.kp, &1.serve, &1.aware}))

    assert cells ==
             MapSet.new([
               {2, 1, :similar, 0},
               {2, 1, :similar, 1},
               {2, 1, :diverse, 0},
               {2, 1, :diverse, 1}
             ])

    assert length(result.runs) == 4
    assert length(result.summary) == 4
    assert Map.has_key?(result.disc_strict_serve_trend, {2, 1, 0})
    assert Map.has_key?(result.disc_strict_aware_trend, {2, 1, :similar})
  end
end
