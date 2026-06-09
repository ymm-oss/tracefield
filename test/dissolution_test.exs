defmodule Tracefield.DissolutionTest do
  use ExUnit.Case

  alias Tracefield.{Dissolution, Embed, LLM, Scenario}

  @agent %{id: "SEC", domain: "security", desc: "security reviewer"}

  test "build_messages keeps closed history private and fuses semi history" do
    history = [
      %{
        agent: "SEC",
        raw_output: ~s({"notes":"sec private","concerns":["security concern"]})
      },
      %{
        agent: "BIZ",
        raw_output: ~s({"notes":"biz private","concerns":["business concern"]})
      }
    ]

    published = [
      %{agent: "SEC", text: "security concern"},
      %{agent: "BIZ", text: "business concern"}
    ]

    closed = Dissolution.build_messages(:closed, @agent, history, published, "task", 2)
    semi = Dissolution.build_messages(:semi, @agent, history, published, "task", 2)

    closed_assistant = Enum.filter(closed, &(&1.role == "assistant"))
    semi_assistant = Enum.filter(semi, &(&1.role == "assistant"))
    closed_user = List.last(closed).content

    assert length(closed_assistant) == 1
    assert hd(closed_assistant).content =~ "sec private"
    refute Enum.any?(closed_assistant, &String.contains?(&1.content, "biz private"))
    assert closed_user =~ "> [BIZ] business concern"
    refute closed_user =~ "> [SEC] security concern"

    assert length(semi_assistant) == 2
    assert Enum.any?(semi_assistant, &String.starts_with?(&1.content, "[BIZ] "))
    assert Enum.any?(semi_assistant, &String.contains?(&1.content, "biz private"))
  end

  test "closed and semi share common instruction while semi anchors and merged has team identity" do
    closed_system = hd(Dissolution.build_messages(:closed, @agent, [], [], "task", 1)).content
    semi_system = hd(Dissolution.build_messages(:semi, @agent, [], [], "task", 1)).content
    merged_system = hd(Dissolution.build_messages(:merged, @agent, [], [], "task", 1)).content

    assert closed_system =~ Dissolution.common_instruction_x()
    assert semi_system =~ Dissolution.common_instruction_x()
    assert Dissolution.instruction(:closed, @agent) == Dissolution.instruction(:semi, @agent)
    assert semi_system =~ "BIAS ANCHOR"
    assert semi_system =~ "business-speed" or semi_system =~ "security"
    assert merged_system =~ "TEAM IDENTITY"
    refute merged_system =~ @agent.desc
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

  test "interstitial parser accepts embedded JSON and falls back to false" do
    refs = [%{ref: "SEC|1", text: "a"}, %{ref: "BIZ|1", text: "b"}]

    judgments =
      Dissolution.parse_interstitial(
        ~s(text {"1":{"interstitial":true,"pair":["security","legal-consent"]},"2":{"interstitial":false,"pair":["made-up"]}} text),
        refs
      )

    assert judgments == %{
             "SEC|1" => %{interstitial: true, pair: ["security", "legal-consent"]},
             "BIZ|1" => %{interstitial: false, pair: []}
           }

    assert Dissolution.parse_interstitial("not json", refs) == %{
             "SEC|1" => %{interstitial: false, pair: []},
             "BIZ|1" => %{interstitial: false, pair: []}
           }
  end

  test "embed mock is deterministic and cosine is symmetric" do
    {:ok, [a, same, other]} =
      Embed.embed(["same concern text", "same concern text", "totally unrelated"], adapter: Embed.Mock)

    assert Embed.cosine(a, same) == 1.0
    assert Embed.cosine(a, other) < 0.9
    assert Embed.cosine(a, other) == Embed.cosine(other, a)
  end

  test "measure dedups duplicate coverage and detects identical diversity collapse" do
    run = %{
      regime: :closed,
      seed: 1,
      concerns_by_agent: %{
        "A" => ["same duplicated concern", "same duplicated concern"],
        "B" => ["same duplicated concern"]
      }
    }

    measure = Dissolution.measure(run, adapter: LLM.Mock)

    assert measure.coverage == 1
    assert measure.diversity == 0.0
  end

  test "measure gives high diversity for disjoint concern sets" do
    run = %{
      regime: :closed,
      seed: 1,
      concerns_by_agent: %{
        "A" => ["aaaaaaaaaaaaaaaaaaaa"],
        "B" => ["zzzzzzzzzzzzzzzzzzzz"]
      }
    }

    measure = Dissolution.measure(run, adapter: LLM.Mock)

    assert measure.coverage == 2
    assert measure.diversity > 0.5
  end

  test "mock e2e distinguishes closed, semi, and merged regimes" do
    scenario = Scenario.load!("scenarios/enterprise-assistant")

    measures =
      [:closed, :semi, :merged]
      |> Map.new(fn regime ->
        run = Dissolution.run(scenario, regime, adapter: LLM.Mock, seed: 1_000, rounds: 2)
        {regime, Dissolution.measure(run, adapter: LLM.Mock)}
      end)

    assert measures.closed.icc == 0
    assert measures.closed.diversity > 0.5
    assert measures.semi.icc == 3
    assert measures.semi.icc > measures.closed.icc
    assert measures.semi.diversity > 0.0
    assert measures.merged.diversity == 0.0
    assert measures.merged.collapse_rate == 1.0
    assert measures.merged.coverage == 2
    assert measures.merged.coverage < measures.closed.coverage
  end
end
