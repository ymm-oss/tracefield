defmodule Tracefield.AgentTest do
  use ExUnit.Case

  alias Tracefield.{Agent, Reference}

  defmodule BadCitationMock do
    @behaviour Tracefield.LLM

    @impl true
    def complete(_messages, _opts) do
      {:ok,
       ~S|{"entries":[{"type":"belief","text":"filtered citation concern(security business-speed)","citations":["e1","missing"]}]}|}
    end
  end

  test "run_turn perceives, deliberates, absorbs, and restricts citations to presented ids" do
    {:ok, ref} = Reference.start_link()

    [foreign] =
      Reference.absorb(
        ref,
        [%{text: "foreign business state", meta: %{domain: "business-speed"}}],
        "BIZ"
      )

    agent =
      Agent.new("SEC", "security", "security reviewer",
        anchor: "enterprise assistant",
        k_s: 2,
        adapter: BadCitationMock,
        model: "mock"
      )

    {_agent, absorbed} = Agent.run_turn(agent, ref, 1)

    assert [%{citations: citations}] = absorbed
    assert citations == [foreign.id]
    assert Reference.get(ref, hd(absorbed).id).text =~ "filtered citation"
  end

  test "mock agent turn creates cross-domain cited state when foreign entries are presented" do
    {:ok, ref} = Reference.start_link()

    [foreign] =
      Reference.absorb(
        ref,
        [%{text: "foreign business state", meta: %{domain: "business-speed"}}],
        "BIZ"
      )

    agent =
      Agent.new("SEC", "security", "security reviewer",
        anchor: "enterprise assistant",
        k_s: 2,
        adapter: Tracefield.LLM.Mock,
        model: "mock"
      )

    {_agent, absorbed} = Agent.run_turn(agent, ref, 1)

    assert length(absorbed) == 2
    assert Enum.any?(absorbed, fn entry -> entry.citations == [foreign.id] end)
  end
end
