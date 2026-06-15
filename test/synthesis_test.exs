defmodule Tracefield.SynthesisTest do
  use ExUnit.Case

  alias Tracefield.{Reference, Synthesis}

  # Layer-0 facts. The synth finding text shares >=4-char tokens with e1/e2
  # (so Mock verify grounds those citations) but NOT with e3 (so that citation
  # is dropped by the production grounding gate).
  defp seed_store do
    {:ok, ref} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)
    [e1] = Reference.absorb(ref, [%{text: "deletion within seventytwo hours required"}], "SEC")
    [e2] = Reference.absorb(ref, [%{text: "retention keeps audit logs ninety days"}], "LEGAL")
    [e3] = Reference.absorb(ref, [%{text: "marketing upsell premium tier campaign"}], "BIZ")
    {ref, e1, e2, e3}
  end

  defp synth_stub(citations) do
    body =
      Jason.encode!(%{
        entries: [
          %{
            type: "belief",
            text: "deletion conflicts with retention policy",
            citations: citations
          }
        ]
      })

    fn _prompt -> {:ok, body} end
  end

  test "absorbs cited findings as a governable higher layer" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete: synth_stub([e1.id, e2.id])
      )

    assert [finding] = result.findings
    assert Enum.sort(finding.citations) == Enum.sort([e1.id, e2.id])
    assert finding.verified
    # absorbed into the store (retrievable)
    assert [synth_id] = result.synth_entry_ids
    assert Reference.get(ref, synth_id).text == "deletion conflicts with retention policy"
  end

  test "verify grounding gate drops ungrounded citations before absorb" do
    {ref, e1, e2, e3} = seed_store()
    layer0 = Reference.all(ref)

    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete: synth_stub([e1.id, e2.id, e3.id])
      )

    assert [finding] = result.findings
    # e3 (marketing upsell) shares no token with the finding -> dropped
    assert Enum.sort(finding.citations) == Enum.sort([e1.id, e2.id])
    refute e3.id in finding.citations
    assert Enum.any?(result.dropped_citations, &(&1.cited_id == e3.id))
    # store never persisted the ungrounded citation
    [synth_id] = result.synth_entry_ids
    refute e3.id in Reference.get(ref, synth_id).citations
  end

  test "retraction closure reaches the synthesis layer (H6 governable)" do
    {ref, e1, _e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result = Synthesis.run(ref, layer0, synth_n: 1, synth_complete: synth_stub([e1.id]))
    [synth_id] = result.synth_entry_ids

    closure = Reference.retract(ref, e1.id)
    isolated = Enum.map(closure, & &1.id)

    assert synth_id in isolated
  end

  # Novelty stub: reads finding ids out of the prompt and marks each shipped/not.
  defp novelty_stub(shipped?) do
    fn prompt ->
      body =
        ~r/"id":"(e\d+)"/
        |> Regex.scan(prompt)
        |> Enum.map(fn [_, id] -> {id, %{"shipped" => shipped?, "reason" => "stub"}} end)
        |> Map.new()
        |> Jason.encode!()

      {:ok, body}
    end
  end

  test "novelty gate is off by default (no novelty keys)" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result = Synthesis.run(ref, layer0, synth_n: 1, synth_complete: synth_stub([e1.id, e2.id]))

    refute Map.has_key?(result, :novelty_checked)
    refute Map.has_key?(hd(result.findings), :novelty)
  end

  test "novelty gate flags already-shipped findings when enabled" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete: synth_stub([e1.id, e2.id]),
        novelty_check: true,
        ground_truth: "the system already handles deletion vs retention conflicts",
        novelty_complete: novelty_stub(true)
      )

    assert result.novelty_checked
    assert [finding] = result.findings
    assert finding.novelty.shipped
    assert finding.id in result.shipped_findings
    assert result.novel_findings == []
  end

  test "novelty gate keeps findings judged novel" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete: synth_stub([e1.id, e2.id]),
        novelty_check: true,
        ground_truth: "unrelated corpus with nothing about this",
        novelty_complete: novelty_stub(false)
      )

    assert result.novelty_checked
    assert [finding] = result.findings
    refute finding.novelty.shipped
    assert finding.id in result.novel_findings
    assert result.shipped_findings == []
  end

  test "novelty gate stays off when enabled but ground_truth is empty" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete: synth_stub([e1.id, e2.id]),
        novelty_check: true,
        ground_truth: ""
      )

    refute Map.has_key?(result, :novelty_checked)
  end
end
