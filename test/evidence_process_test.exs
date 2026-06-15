defmodule Tracefield.EvidenceProcessTest do
  use ExUnit.Case

  alias Tracefield.{Evidence, ProcessInterpreter, ProcessSpec, Reference}

  test "evidence process spec routes through the generic interpreter" do
    spec = Evidence.spec()

    assert ProcessSpec.produces(spec, "extract") == [:claim, :question]
    assert ProcessSpec.closure_action(spec, "supersedes") == :replace
    assert ProcessSpec.closure_action(spec, :verifies) == :reopen

    assert {:start, %{id: "intake"}} =
             ProcessInterpreter.route(spec, %{"stage" => "intake", "status" => "new"})

    assert {:start, %{id: "extract"}} =
             ProcessInterpreter.route(spec, %{"stage" => "intake", "status" => "done"})
  end

  test "evidence demo completes all stages and records corroboration gate reopen" do
    result = Evidence.run_demo()

    assert result.process.state["stage"] == "audit"
    assert result.process.state["status"] == "done"

    stages = Enum.map(result.process.history, & &1.stage)
    assert stages == ["intake", "extract", "corroborate", "synthesize", "audit", "audit"]

    corroborate = Enum.find(result.process.history, &(&1.stage == "corroborate"))
    assert corroborate.reopened == ["synthesize"]
  end

  test "typed closure isolates only invalidated downstream entries" do
    m2 = Evidence.measure_m2()

    assert m2.precision == 1.0
    assert m2.recall == 1.0
    assert m2.false_positive_count == 0
    assert m2.false_negative_count == 0
    assert m2.reopened_count == 1
    assert m2.flagged_count == 1
    assert m2.weakened_count == 1
  end

  test "typed closure distinguishes supersedes and verifies from uniform quarantine" do
    m3 = Evidence.measure_m3()

    assert m3.supersedes.typed_correct
    assert m3.supersedes.uniform_wrong
    assert m3.supersedes.typed_replace_count == 1
    assert m3.supersedes.uniform_isolated_count == 1

    assert m3.verifies.typed_correct
    assert m3.verifies.uniform_wrong
    assert m3.verifies.typed_reopened_count == 1
    assert m3.verifies.uniform_isolated_count == 1
  end

  test "reference typed retraction records action metadata without changing uniform retract" do
    spec = Evidence.spec()
    {:ok, ref} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)

    [source] = Reference.absorb(ref, [%{type: :chunk, text: "source"}], "S")

    [claim] =
      Reference.absorb(
        ref,
        [%{type: :claim, text: "claim", citations: [%{id: source.id, stance: :grounds}]}],
        "C"
      )

    result = Reference.retract_typed(ref, source.id, spec)
    assert Enum.map(result.isolated, & &1.id) == [claim.id]
    assert Reference.get(ref, claim.id).status == :superseded

    assert [%{action: :invalidate, stance: "grounds"}] =
             Reference.get(ref, claim.id).meta.typed_closure

    {:ok, uniform} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)
    [u_source] = Reference.absorb(uniform, [%{type: :chunk, text: "source"}], "S")

    [u_claim] =
      Reference.absorb(uniform, [%{type: :claim, text: "claim", citations: [u_source.id]}], "C")

    assert Enum.map(Reference.retract(uniform, u_source.id), & &1.id) == [u_claim.id]
    assert Reference.get(uniform, u_claim.id).status == :active
  end

  test "coverage and patrol metrics fire on the evidence process without retuning" do
    m4 = Evidence.measure_m4()

    assert m4.unowned_claim_warnings >= 1
    assert m4.stale_question_warnings == 1
    assert m4.patrol_sections == 2
    assert m4.patrol_slice_nonempty
    assert m4.mobilization_rate >= 0.0
    assert m4.meaningful_fire
  end
end
