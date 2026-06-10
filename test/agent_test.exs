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

  defmodule PrivateDocPromptMock do
    @behaviour Tracefield.LLM

    @impl true
    def complete(messages, _opts) do
      prompt = Enum.map_join(messages, "\n", &Map.get(&1, :content, Map.get(&1, "content", "")))

      text =
        if String.contains?(prompt, "PRIVATE DOCUMENT (yours only):") and
             String.contains?(prompt, "retention-90d-private-test") do
          "private document was available in prompt(security)"
        else
          ""
        end

      {:ok, Jason.encode!(%{entries: [%{type: "belief", text: text, citations: []}]})}
    end
  end

  defmodule ProcedurePromptMock do
    @behaviour Tracefield.LLM

    @impl true
    def complete(messages, _opts) do
      prompt = Enum.map_join(messages, "\n", &Map.get(&1, :content, Map.get(&1, "content", "")))

      entries =
        if String.contains?(prompt, "ADOPTED PROCEDURE:\ncontrast procedure") do
          [
            %{
              type: "belief",
              text: "procedure was injected(security business-speed)",
              citations: ["e1"]
            }
          ]
        else
          []
        end

      {:ok, Jason.encode!(%{entries: entries})}
    end
  end

  defmodule PromptCaptureMock do
    @behaviour Tracefield.LLM

    @impl true
    def complete(messages, _opts) do
      if pid = Process.whereis(__MODULE__) do
        send(pid, {:agent_messages, messages})
      end

      {:ok,
       Jason.encode!(%{
         entries: [
           %{type: "belief", text: "captured prompt state(security)", citations: []}
         ]
       })}
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

    {_agent, absorbed, perception} = Agent.run_turn(agent, ref, 1)

    assert [%{citations: citations}] = absorbed
    assert citations == [foreign.id]

    assert perception == %{
             query: "enterprise assistant\nsecurity",
             served: [%{id: foreign.id, author: "BIZ"}]
           }

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

    {_agent, absorbed, _perception} = Agent.run_turn(agent, ref, 1)

    assert length(absorbed) == 2
    assert Enum.any?(absorbed, fn entry -> entry.citations == [foreign.id] end)
  end

  test "private_doc is included in prompt but not absorbed into the reference store" do
    {:ok, ref} = Reference.start_link()

    private_doc = """
    SEC private note: retention-90d-private-test must stay prompt-only.
    This full sentence must never be absorbed as a reference entry.
    """

    agent =
      Agent.new("SEC", "security", "security reviewer",
        private_doc: private_doc,
        adapter: PrivateDocPromptMock,
        model: "mock"
      )

    {_agent, absorbed, _perception} = Agent.run_turn(agent, ref, 1)

    assert [%{text: "private document was available in prompt(security)"}] = absorbed

    stored_texts = Reference.all(ref) |> Enum.map(& &1.text)

    refute Enum.any?(stored_texts, &String.contains?(&1, "retention-90d-private-test"))
    refute Enum.any?(stored_texts, &String.contains?(&1, "This full sentence must never"))
  end

  test "procedure entries are injected and cited as adoption provenance" do
    {:ok, ref} = Reference.start_link()

    [foreign] =
      Reference.absorb(
        ref,
        [%{text: "foreign business state", meta: %{domain: "business-speed"}}],
        "BIZ"
      )

    [procedure] =
      Reference.absorb(
        ref,
        [%{type: :procedure, text: "contrast procedure", meta: %{domain: "procedure"}}],
        "FACILITATOR"
      )

    agent =
      Agent.new("SEC", "security", "security reviewer",
        anchor: "enterprise assistant",
        k_s: 2,
        adapter: ProcedurePromptMock,
        model: "mock",
        procedure_id: procedure.id
      )

    {_agent, absorbed, perception} = Agent.run_turn(agent, ref, 1)

    assert [%{citations: citations}] = absorbed
    assert citations == [foreign.id, procedure.id]
    assert perception.served == [%{id: foreign.id, author: "BIZ"}]
  end

  test "aware option inserts situation preamble into system prompt only when enabled" do
    Process.register(self(), PromptCaptureMock)

    {:ok, aware_ref} = Reference.start_link()

    aware_agent =
      Agent.new("SEC", "security", "security reviewer",
        aware: true,
        adapter: PromptCaptureMock,
        model: "mock"
      )

    Agent.run_turn(aware_agent, aware_ref, 1)
    assert_receive {:agent_messages, aware_messages}

    aware_system = hd(aware_messages).content
    assert aware_system =~ "TRACEFIELD_AGENT_TURN\nSITUATION:"
    assert aware_system =~ "半溶解チーム"
    assert aware_system =~ "唯一の窓"

    {:ok, unaware_ref} = Reference.start_link()

    unaware_agent =
      Agent.new("SEC", "security", "security reviewer",
        aware: false,
        adapter: PromptCaptureMock,
        model: "mock"
      )

    Agent.run_turn(unaware_agent, unaware_ref, 1)
    assert_receive {:agent_messages, unaware_messages}

    unaware_system = hd(unaware_messages).content
    refute unaware_system =~ "半溶解チーム"
    refute unaware_system =~ "唯一の窓"
  end
end
