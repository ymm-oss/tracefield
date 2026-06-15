defmodule Tracefield.AgentTooluseTest do
  use ExUnit.Case

  alias Tracefield.{Agent, Reference}

  test "tool deliberation serves then absorbs with structured citation stances" do
    {:ok, ref} = Reference.start_link()
    [source] = Reference.absorb(ref, [%{text: "solar budget evidence"}], "BIZ")

    agent =
      Agent.new("SEC", "security", "security reviewer",
        anchor: "solar plan",
        deliberation: :tools,
        adapter: Tracefield.LLM.Mock,
        k_s: 1,
        entry_limit: 1,
        tool_script: [
          [%{name: "serve", arguments: %{query: "solar budget"}}],
          [
            %{
              name: "absorb",
              arguments: %{
                content: "solar budget evidence changes the security review",
                citations: [%{id: source.id, stance: "refutes"}]
              }
            }
          ]
        ]
      )

    {_agent, absorbed, perception} = Agent.run_turn(agent, ref, 1)

    assert [%{type: :belief, citations: [source_id], meta: meta}] = absorbed
    assert source_id == source.id
    assert meta[:citation_stances] == %{source.id => "refutes"}
    assert perception.served_queries == ["solar budget"]
    assert perception.tool_rounds == 2
    assert perception.served == [%{id: source.id, author: "BIZ"}]
  end

  test "tool deliberation applies the same citation gate to unserved citations" do
    {:ok, ref} = Reference.start_link()
    [source] = Reference.absorb(ref, [%{text: "grounded source token"}], "BIZ")

    agent =
      Agent.new("SEC", "security", "security reviewer",
        anchor: "grounded source",
        deliberation: :tools,
        adapter: Tracefield.LLM.Mock,
        k_s: 1,
        entry_limit: 1,
        tool_script: [
          [%{name: "serve", arguments: %{query: "grounded source"}}],
          [
            %{
              name: "absorb",
              arguments: %{
                content: "grounded source token supports the review",
                type: "claim",
                citations: [
                  %{id: source.id, stance: "relies_on"},
                  %{id: "missing", stance: "refutes"}
                ]
              }
            }
          ]
        ]
      )

    {_agent, absorbed, _perception} = Agent.run_turn(agent, ref, 1)

    assert [%{type: :claim, citations: [source_id], meta: meta}] = absorbed
    assert source_id == source.id
    refute Map.has_key?(meta[:citation_stances] || %{}, "missing")
  end

  test "tool deliberation records multi-step serve queries" do
    {:ok, ref} = Reference.start_link()
    [first] = Reference.absorb(ref, [%{text: "solar procurement context"}], "BIZ")
    [_second] = Reference.absorb(ref, [%{text: "consent review context"}], "LEGAL")

    agent =
      Agent.new("SEC", "security", "security reviewer",
        anchor: "solar consent",
        deliberation: :tools,
        adapter: Tracefield.LLM.Mock,
        k_s: 2,
        entry_limit: 1,
        tool_script: [
          [%{name: "serve", arguments: %{query: "solar"}}],
          [%{name: "serve", arguments: %{query: "consent"}}],
          [
            %{
              name: "absorb",
              arguments: %{
                content: "solar procurement context needs consent review",
                type: "decision",
                citations: [%{id: first.id, stance: "context"}]
              }
            }
          ]
        ]
      )

    {_agent, absorbed, perception} = Agent.run_turn(agent, ref, 1)

    assert [%{type: :decision, citations: [first_id], meta: meta}] = absorbed
    assert first_id == first.id
    assert meta[:citation_stances] == %{first.id => "context"}
    assert perception.served_queries == ["solar", "consent"]
    assert perception.tool_rounds == 3
  end
end
