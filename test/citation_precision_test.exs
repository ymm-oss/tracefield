defmodule Tracefield.CitationPrecisionTest do
  use ExUnit.Case

  alias Tracefield.{CitationPrecision, Reference}

  # Reproduces the experiment-results §7 precision ladder on the live harness:
  # citation grounding (stance → verify) progressively removes over-isolation.
  test "grounding lifts precision along the ladder: cited_anything < relies_on < verified=1.0" do
    {:ok, ref} = Reference.start_link()

    # Contaminant chunk (e.g. a retracted PM testimony) with distinctive vocabulary.
    [c] =
      Reference.absorb(
        ref,
        [%{type: :chunk, text: "velocity launch failure testimony"}],
        "DOCS"
      )

    cite = fn stance -> [%{id: c.id, stance: stance}] end

    # Genuine adopters: relies_on AND text grounded in the chunk (the ground truth).
    [p1] =
      Reference.absorb(
        ref,
        [%{text: "prioritize velocity for the launch", citations: cite.("relies_on")}],
        "BIZ"
      )

    [p2] =
      Reference.absorb(
        ref,
        [%{text: "the failure proves velocity matters", citations: cite.("relies_on")}],
        "OPS"
      )

    # Refute citation — argues AGAINST the contaminant; must not be quarantined.
    [_p3] =
      Reference.absorb(
        ref,
        [%{text: "velocity launch is reckless", citations: cite.("refutes")}],
        "SEC"
      )

    # Context citation — mere reference; must not be quarantined.
    [_p4] =
      Reference.absorb(
        ref,
        [%{text: "see the launch note for background", citations: cite.("context")}],
        "UX"
      )

    # Hallucinated relies_on — claims dependence but content is ungrounded in the chunk.
    [_p6] =
      Reference.absorb(
        ref,
        [%{text: "quarterly audit retention compliance", citations: cite.("relies_on")}],
        "LEGAL"
      )

    gt = [p1.id, p2.id]
    ladder = CitationPrecision.ladder(ref, c.id, gt, judge_adapter: Tracefield.LLM.Mock)

    cited = ladder[:cited_anything]
    relies = ladder[:relies_on]
    verified = ladder[:relies_on_verified]

    # Recall stays perfect across rules — genuine adopters are never dropped.
    assert cited.recall == 1.0
    assert relies.recall == 1.0
    assert verified.recall == 1.0

    # Precision climbs monotonically and only reaches 1.0 with stance + verification.
    assert cited.precision < relies.precision
    assert relies.precision < verified.precision
    assert verified.precision == 1.0

    # Concrete ladder: cited 2/5 (all 5 citers), relies_on 2/3 (drops refute+context),
    # verified 2/2 (drops the hallucinated relies_on).
    assert cited.precision == 2 / 5
    assert relies.precision == 2 / 3
    assert MapSet.equal?(verified.affected, MapSet.new([p1.id, p2.id]))
  end
end
