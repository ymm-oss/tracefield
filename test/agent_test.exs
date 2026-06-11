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

  defmodule BudgetCitationMock do
    @behaviour Tracefield.LLM

    @impl true
    def complete(messages, _opts) do
      prompt = Enum.map_join(messages, "\n", &Map.get(&1, :content, Map.get(&1, "content", "")))
      index_only_doc_id = index_only_doc_id(prompt)

      if pid = Process.whereis(__MODULE__) do
        send(pid, {:budget_prompt, prompt, index_only_doc_id})
      end

      {:ok,
       Jason.encode!(%{
         entries: [
           %{
             type: "belief",
             text: "index-only document citation remains allowed(security)",
             citations: List.wrap(index_only_doc_id)
           }
         ]
       })}
    end

    defp index_only_doc_id(prompt) do
      index_ids =
        prompt
        |> String.split("\n")
        |> Enum.flat_map(fn line ->
          if String.starts_with?(line, "DOC ") and String.contains?(line, ": ") do
            case Regex.run(~r/^DOC\s+(e\d+)\s+file=/, line) do
              [_match, id] -> [id]
              _other -> []
            end
          else
            []
          end
        end)
        |> MapSet.new()

      full_ids =
        prompt
        |> String.split("\n")
        |> Enum.flat_map(fn line ->
          if String.starts_with?(line, "DOC ") and not String.contains?(line, ": ") do
            case Regex.run(~r/^DOC\s+(e\d+)\s+file=/, line) do
              [_match, id] -> [id]
              _other -> []
            end
          else
            []
          end
        end)
        |> MapSet.new()

      index_ids
      |> MapSet.difference(full_ids)
      |> MapSet.to_list()
      |> List.first()
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
    foreign_id = foreign.id

    assert %{
             query: "enterprise assistant\nsecurity",
             served: [%{id: ^foreign_id, author: "BIZ"}],
             prompt_tokens_est: prompt_tokens_est,
             doc_mode: :full,
             docs_full_ids: [],
             over_budget: false
           } = perception

    assert prompt_tokens_est > 0

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

  test "private_memory is rendered after private_doc and stays out of the reference store" do
    Process.register(self(), PromptCaptureMock)
    {:ok, ref} = Reference.start_link()

    agent =
      Agent.new("SEC", "security", "security reviewer",
        private_doc: "SEC private document body",
        private_memory: "- prior private judgment must remain prompt-only",
        adapter: PromptCaptureMock,
        model: "mock"
      )

    {_agent, absorbed, _perception} = Agent.run_turn(agent, ref, 1)
    assert_receive {:agent_messages, messages}
    prompt = Enum.at(messages, 1).content

    assert prompt =~ "PRIVATE DOCUMENT (yours only):\nSEC private document body"
    assert prompt =~ "PRIVATE MEMORY (あなた自身の過去の判断。経験として活かせ):\n- prior private judgment"
    assert prompt =~ ~r/PRIVATE DOCUMENT[\s\S]+PRIVATE MEMORY[\s\S]+PRESENTED ENTRIES/
    refute Enum.any?(Reference.all(ref), &String.contains?(&1.text, "prior private judgment"))
    assert [%{text: "captured prompt state(security)"}] = absorbed
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

  @baseline_system_prompt_without_aware """
                                        TRACEFIELD_AGENT_TURN
                                        Return only JSON {"entries":[{"type":"belief","text":"...","citations":["e1"]}]}. At most 2 entries. Citations must use presented ids only. If facts in PRIVATE DOCUMENT (yours only) contradict or interact with PRESENTED ENTRIES, point out the contradiction/interaction and cite both facts explicitly.
                                        """
                                        |> String.trim()

  test "expected_types nil keeps the baseline system prompt unchanged" do
    Process.register(self(), PromptCaptureMock)
    {:ok, ref} = Reference.start_link()

    agent =
      Agent.new("SEC", "security", "security reviewer",
        adapter: PromptCaptureMock,
        model: "mock"
      )

    Agent.run_turn(agent, ref, 1)
    assert_receive {:agent_messages, messages}

    system = hd(messages).content
    assert system == @baseline_system_prompt_without_aware
  end

  test "expected_types replaces the JSON example type with the first expected type" do
    Process.register(self(), PromptCaptureMock)
    {:ok, ref} = Reference.start_link()

    agent =
      Agent.new("SEC", "security", "security reviewer",
        expected_types: ["decision"],
        adapter: PromptCaptureMock,
        model: "mock"
      )

    Agent.run_turn(agent, ref, 1)
    assert_receive {:agent_messages, messages}

    system = hd(messages).content
    assert system =~ ~S("type":"decision")
    refute system =~ ~S("type":"belief")
    refute system =~ "Expected entry types this turn:"
  end

  test "multiple expected_types add an expected-types hint after the JSON example" do
    Process.register(self(), PromptCaptureMock)
    {:ok, ref} = Reference.start_link()

    agent =
      Agent.new("SEC", "security", "security reviewer",
        expected_types: ["requirement", "question"],
        adapter: PromptCaptureMock,
        model: "mock"
      )

    Agent.run_turn(agent, ref, 1)
    assert_receive {:agent_messages, messages}

    system = hd(messages).content
    assert system =~ ~S("type":"requirement")
    assert system =~ "Expected entry types this turn: requirement, question."
    refute system =~ ~S("type":"belief")
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

  test "document prompt stays full when estimated messages fit the context budget" do
    Process.register(self(), PromptCaptureMock)
    {:ok, ref} = Reference.start_link()

    docs =
      Reference.absorb(
        ref,
        [
          %{type: :chunk, text: "short full document alpha", meta: %{file: "a.md"}},
          %{type: :chunk, text: "short full document beta", meta: %{file: "b.md"}}
        ],
        "DOCS"
      )

    agent =
      Agent.new("SEC", "security", "security reviewer",
        anchor: "short task",
        adapter: PromptCaptureMock,
        model: "mock",
        num_ctx: 8192
      )

    {_agent, _absorbed, perception} = Agent.run_turn(agent, ref, 1)
    assert_receive {:agent_messages, messages}
    prompt = Enum.at(messages, 1).content

    assert perception.doc_mode == :full
    assert perception.docs_full_ids == Enum.map(docs, & &1.id)
    refute perception.over_budget
    assert prompt =~ "REFERENCE DOCUMENTS（設計判断はここを引用せよ）:"
    assert prompt =~ "short full document alpha"
    assert prompt =~ "short full document beta"
  end

  test "document prompt degrades to selected index plus top-k full docs when over budget" do
    Process.register(self(), BudgetCitationMock)
    {:ok, ref} = Reference.start_link()

    docs =
      Reference.absorb(
        ref,
        [
          long_doc("ALPHA SUMMARY", "ALPHA_FULL_MARKER", "alpha needle retrieval"),
          long_doc("BETA SUMMARY", "BETA_FULL_MARKER", "beta archive"),
          long_doc("GAMMA SUMMARY", "GAMMA_FULL_MARKER", "gamma archive")
        ],
        "DOCS"
      )

    agent =
      Agent.new("SEC", "alpha needle retrieval", "security reviewer",
        anchor: "alpha needle retrieval",
        adapter: BudgetCitationMock,
        model: "mock",
        num_ctx: 2200,
        k_docs: 1,
        k_s: 0
      )

    {_agent, absorbed, perception} = Agent.run_turn(agent, ref, 1)
    assert_receive {:budget_prompt, prompt, index_only_doc_id}

    assert perception.doc_mode == :selected
    assert length(perception.docs_full_ids) == 1
    assert perception.prompt_tokens_est > 0

    Enum.each(docs, fn doc ->
      file = Map.fetch!(doc.meta, :file)
      assert prompt =~ "DOC #{doc.id} file=#{file}:"
    end)

    markers_by_id =
      Map.new(docs, fn doc ->
        marker = doc.meta.marker
        {doc.id, marker}
      end)

    Enum.each(markers_by_id, fn {id, marker} ->
      if id in perception.docs_full_ids do
        assert prompt =~ marker
      else
        refute prompt =~ marker
      end
    end)

    refute is_nil(index_only_doc_id)
    refute index_only_doc_id in perception.docs_full_ids
    assert [%{citations: [^index_only_doc_id]}] = absorbed
  end

  test "document prompt records over_budget when selected prompt still exceeds budget" do
    Process.register(self(), PromptCaptureMock)
    {:ok, ref} = Reference.start_link()

    Reference.absorb(
      ref,
      [long_doc("ALPHA SUMMARY", "ALPHA_FULL_MARKER", String.duplicate("alpha ", 200))],
      "DOCS"
    )

    agent =
      Agent.new("SEC", "alpha", "security reviewer",
        anchor: "alpha",
        adapter: PromptCaptureMock,
        model: "mock",
        num_ctx: 1,
        k_docs: 1
      )

    {_agent, _absorbed, perception} = Agent.run_turn(agent, ref, 1)

    assert perception.doc_mode == :selected
    assert perception.over_budget
  end

  defp long_doc(summary, marker, body_seed) do
    %{
      type: :chunk,
      text: "#{summary}\n#{marker}\n#{body_seed}\n#{String.duplicate(body_seed <> " ", 90)}",
      meta: %{
        file: "#{String.downcase(String.split(summary) |> hd())}.md",
        marker: marker
      }
    }
  end
end
