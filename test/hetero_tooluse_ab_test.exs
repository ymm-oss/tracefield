defmodule Tracefield.HeteroTooluseABTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Hetero
  alias Tracefield.CitationGrounding

  test "mock hetero run passes tools deliberation into agents" do
    result =
      Hetero.run_experiment(
        adapter_name: "mock-test",
        adapter: Tracefield.LLM.Mock,
        seeds: 1,
        rounds: 1,
        ks: [1],
        kps: [0],
        model: "mock",
        judge_model: "mock",
        embed_model: "nomic-embed-text",
        temperature: 0.4,
        deliberation: "tools",
        tool_max_rounds: 2
      )

    assert [run] = result.runs
    assert run.deliberation == :tools
    assert Enum.all?(run.perception, &Map.has_key?(&1, :tool_rounds))
    assert run.tool_rounds_distribution.values == [1, 1, 1]
    assert run.tool_rounds_distribution.counts == %{"1" => 3}
    assert run.served_queries_count == 0
  end

  test "citation grounding counts citations that cite a source strict-hit keyword" do
    interactions = [
      %{id: "I1", keywords: ["retention-90d", "delete-72h"]}
    ]

    entries = [
      %{
        id: "e1",
        text: "source document says retention-90d",
        citations: []
      },
      %{
        id: "e2",
        text: "retention-90d conflicts with delete-72h",
        citations: ["e1"]
      }
    ]

    result = CitationGrounding.score(entries, interactions)

    assert result.grounding_rate == 1.0
    assert result.grounded_count == 1
    assert result.total_count == 1
    assert result.ungrounded == []
  end

  test "citation grounding reports citations without source keywords in the cited text" do
    interactions = [
      %{id: "I1", keywords: ["retention-90d", "delete-72h"]}
    ]

    entries = [
      %{
        id: "e1",
        text: "unrelated project context",
        citations: []
      },
      %{
        id: "e2",
        text: "retention-90d conflicts with delete-72h",
        citations: ["e1"]
      }
    ]

    result = CitationGrounding.score(entries, interactions)

    assert result.grounding_rate == 0.0
    assert result.grounded_count == 0
    assert result.total_count == 1

    assert [
             %CitationGrounding.UngroundedCitation{
               source_id: "e2",
               cited_id: "e1",
               source_interaction_ids: ["I1"],
               source_keywords: ["retention-90d", "delete-72h"]
             }
           ] = result.ungrounded
  end
end
