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

  defp multi_synth_stub(specs) do
    entries =
      Enum.map(specs, fn {text, cites} ->
        %{type: "belief", text: text, citations: cites}
      end)

    body = Jason.encode!(%{entries: entries})
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

  test "novelty gate flags a wholesale judge failure (distinguishable all-novel)" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete: synth_stub([e1.id, e2.id]),
        novelty_check: true,
        ground_truth: "some ground truth",
        novelty_complete: fn _ -> {:ok, "this is not json at all"} end
      )

    assert result.novelty_checked
    assert Map.has_key?(result, :novelty_error)
    # conservative: finding kept, but reason marks it as NOT a real verdict
    assert [finding] = result.findings
    refute finding.novelty.shipped
    assert finding.novelty.reason == "judge-unparsed"
    assert finding.id in result.novel_findings
  end

  test "novelty gate marks ids the judge omitted from a valid verdict map" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    # valid JSON, but keyed by an id that is not among the findings
    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete: synth_stub([e1.id, e2.id]),
        novelty_check: true,
        ground_truth: "some ground truth",
        novelty_complete: fn _ ->
          {:ok, Jason.encode!(%{"not-a-real-id" => %{"shipped" => true, "reason" => "x"}})}
        end
      )

    assert result.novelty_checked
    refute Map.has_key?(result, :novelty_error)
    assert [finding] = result.findings
    assert finding.novelty.reason == "judge-omitted"
    refute finding.novelty.shipped
    assert finding.id in result.novelty_omitted
  end

  test "dedupe is off by default (no cluster fields, no embedding leak)" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result = Synthesis.run(ref, layer0, synth_n: 1, synth_complete: synth_stub([e1.id, e2.id]))

    refute Map.has_key?(result, :dedupe_clusters)
    refute Map.has_key?(hd(result.findings), :cluster_size)
    refute Map.has_key?(hd(result.findings), :embedding)
  end

  test "dedupe merges near-duplicate findings and unions their citations" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete:
          multi_synth_stub([
            {"deletion conflicts with retention policy", [e1.id]},
            {"audit retention ninety logs window kept", [e2.id]}
          ]),
        # threshold -1.0: every non-empty embedding pair merges -> exactly 1 cluster
        dedupe: true,
        dedupe_threshold: -1.0
      )

    assert result.dedupe_input == 2
    assert result.dedupe_clusters == 1
    assert [finding] = result.findings
    assert finding.cluster_size == 2
    # representative is the longest text; citations are unioned across the cluster
    assert finding.text == "deletion conflicts with retention policy"
    assert Enum.sort(finding.citations) == Enum.sort([e1.id, e2.id])
    # all entries remain in the store (governance unchanged)
    assert length(result.synth_entry_ids) == 2
    refute Map.has_key?(finding, :embedding)
  end

  test "dedupe keeps findings distinct when the threshold is unreachable" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete:
          multi_synth_stub([
            {"deletion conflicts with retention policy", [e1.id]},
            {"audit retention ninety logs window kept", [e2.id]}
          ]),
        dedupe: true,
        dedupe_threshold: 2.0
      )

    assert result.dedupe_input == 2
    assert result.dedupe_clusters == 2
    assert length(result.findings) == 2
    assert Enum.all?(result.findings, &(&1.cluster_size == 1))
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

  test "findings carry support = number of samples that produced them" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    # 3 samples each emit the same finding text -> support 3
    result =
      Synthesis.run(ref, layer0, synth_n: 3, synth_complete: synth_stub([e1.id, e2.id]))

    assert [finding] = result.findings
    assert finding.support == 3
  end

  test "quorum drops findings backed by fewer than N samples" do
    {ref, e1, e2, _e3} = seed_store()
    layer0 = Reference.all(ref)

    # 1 sample -> support 1; quorum 2 filters it out before grounding/absorb
    result =
      Synthesis.run(ref, layer0,
        synth_n: 1,
        synth_complete: synth_stub([e1.id, e2.id]),
        quorum: 2
      )

    assert result.findings == []
    assert result.synth_entry_ids == []
  end
end
