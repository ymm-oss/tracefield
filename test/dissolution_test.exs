defmodule Tracefield.DissolutionTest do
  use ExUnit.Case

  alias Tracefield.{Dissolution, LLM, Scenario}

  @agent %{id: "SEC", domain: "security", desc: "security reviewer"}

  test "build_context excludes notes for closed and includes notes for semi" do
    workspace = [
      "[SEC notes] private reasoning",
      "[SEC concern] published security concern"
    ]

    published = ["[SEC] published security concern"]

    closed = Dissolution.build_context(:closed, workspace, published)
    semi = Dissolution.build_context(:semi, workspace, published)

    refute String.contains?(closed, "private reasoning")
    refute String.contains?(closed, "[SEC notes]")
    assert String.contains?(closed, "published security concern")
    assert String.contains?(semi, "private reasoning")
    assert String.contains?(semi, "[SEC notes]")
  end

  test "closed and semi instructions are identical while merged dissolves bias" do
    assert Dissolution.instruction(:closed, @agent) == Dissolution.instruction(:semi, @agent)

    merged = Dissolution.instruction(:merged, @agent)
    assert String.contains?(merged, "偏りに固執せず")
    assert String.contains?(merged, "単一の統合見解")
  end

  test "turn parser accepts JSON embedded in surrounding text" do
    content = """
    preface
    {"notes":"reasoning","concerns":["risk one","risk two","risk three"]}
    """

    assert Dissolution.parse_turn(content) ==
             {"reasoning", ["risk one", "risk two", "risk three"]}

    assert Dissolution.parse_turn("not json") == {"", []}
  end

  test "domain parser accepts embedded JSON and drops unknown domains" do
    refs = [%{ref: "SEC|1", text: "a"}, %{ref: "BIZ|1", text: "b"}]

    tags =
      Dissolution.parse_domain_tags(
        ~s(text {"1":["security","made-up"],"2":["business-speed","ux"]} text),
        refs
      )

    assert tags == %{
             "SEC|1" => ["security"],
             "BIZ|1" => ["business-speed", "ux"]
           }

    assert Dissolution.parse_domain_tags("not json", refs) == %{"SEC|1" => [], "BIZ|1" => []}
  end

  test "mock e2e distinguishes closed, semi, and merged regimes" do
    scenario = Scenario.load!("scenarios/enterprise-assistant")

    measures =
      [:closed, :semi, :merged]
      |> Map.new(fn regime ->
        run = Dissolution.run(scenario, regime, adapter: LLM.Mock, seed: 1_000, rounds: 2)
        {regime, Dissolution.measure(run, adapter: LLM.Mock)}
      end)

    assert measures.semi.icc == 3
    assert measures.closed.icc == 0
    assert measures.semi.icc > measures.closed.icc
    assert measures.merged.diversity == 0.0
    assert measures.merged.diversity < measures.semi.diversity
    assert measures.merged.coverage < measures.closed.coverage
    assert measures.merged.bias_retention < measures.closed.bias_retention
  end
end
