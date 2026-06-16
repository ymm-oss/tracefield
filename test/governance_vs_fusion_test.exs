defmodule Tracefield.GovernanceVsFusionTest do
  use ExUnit.Case

  alias Tracefield.{GovernanceVsFusion, Reference}

  # Planted dependency on premise P (keyword "ninetynine"):
  #   f1  cites P AND depends (has keyword)      -> GT yes, GOV yes  (correct)
  #   f2  cites P but does NOT depend (no keyword)-> GT no,  GOV yes  (over-connection)
  #   f3  depends (keyword) but does NOT cite P   -> GT yes, GOV no   (M5 hole)
  #   f4  neither                                 -> GT no,  GOV no   (correct)
  setup do
    {:ok, ref} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)
    [p] = Reference.absorb(ref, [%{text: "vendor SLA guarantees ninetynine uptime"}], "BIZ")

    [f1] =
      Reference.absorb(
        ref,
        [%{type: :belief, text: "rollout plan assumes ninetynine uptime", citations: [p.id]}],
        "SYNTH"
      )

    [f2] =
      Reference.absorb(
        ref,
        [%{type: :belief, text: "improve the onboarding flow copy", citations: [p.id]}],
        "SYNTH"
      )

    [f3] =
      Reference.absorb(
        ref,
        [%{type: :belief, text: "budget relies on ninetynine availability", citations: []}],
        "SYNTH"
      )

    [f4] =
      Reference.absorb(
        ref,
        [%{type: :belief, text: "tweak the logging format", citations: []}],
        "SYNTH"
      )

    entries = Reference.all(ref)
    findings = Enum.map([f1, f2, f3, f4], &%{id: &1.id, text: &1.text})

    {:ok,
     p: p,
     findings: findings,
     entries: entries,
     ids: %{f1: f1.id, f2: f2.id, f3: f3.id, f4: f4.id}}
  end

  test "semantic GT = findings that truly depend (keyword), regardless of citation", ctx do
    gt = GovernanceVsFusion.semantic_gt(ctx.findings, ["ninetynine"])
    assert Enum.sort(gt) == Enum.sort([ctx.ids.f1, ctx.ids.f3])
  end

  test "GOV containment = citation closure (catches over-connection and the M5 hole)", ctx do
    gov = GovernanceVsFusion.gov_affected(ctx.entries, ctx.p.id)
    # closure of P = findings citing P = f1, f2 (NOT f3 which depends but didn't cite)
    assert Enum.sort(gov) == Enum.sort([ctx.ids.f1, ctx.ids.f2])

    gt = GovernanceVsFusion.semantic_gt(ctx.findings, ["ninetynine"])
    s = GovernanceVsFusion.score(gov, gt)
    # f1 correct; f2 over-connected (precision hit); f3 missed (recall hit)
    assert s.recall == 0.5
    assert s.precision == 0.5
  end

  test "GOV :direct mode counts only direct citers of P (precision lever vs flood)", ctx do
    # f1, f2 cite P directly; f3, f4 do not. :direct = {f1, f2}; :reachable also
    # = {f1, f2} here (f3/f4 don't cite P at all), but :direct never floods via
    # transitive chains.
    direct = GovernanceVsFusion.gov_affected(ctx.entries, ctx.p.id, mode: :direct)
    assert Enum.sort(direct) == Enum.sort([ctx.ids.f1, ctx.ids.f2])
    refute ctx.ids.f3 in direct
  end

  test "semantic_labels classifies invalidated/reinforced/unrelated (seam)", ctx do
    labeller = fn _prompt ->
      {:ok,
       Jason.encode!(%{
         ctx.ids.f1 => %{"label" => "invalidated"},
         ctx.ids.f2 => %{"label" => "unrelated"},
         ctx.ids.f3 => %{"label" => "reinforced"},
         ctx.ids.f4 => %{"label" => "unrelated"}
       })}
    end

    labels =
      GovernanceVsFusion.semantic_labels(ctx.findings, "P", "P is false",
        label_complete: labeller
      )

    assert GovernanceVsFusion.invalidated(labels) == [ctx.ids.f1]
    # GOV :direct = {f1, f2}; scored against semantic invalidated GT {f1}:
    direct = GovernanceVsFusion.gov_affected(ctx.entries, ctx.p.id, mode: :direct)
    s = GovernanceVsFusion.score(direct, GovernanceVsFusion.invalidated(labels))
    assert s.recall == 1.0
    # f2 cited P directly but is semantically unrelated -> precision 0.5
    assert s.precision == 0.5
  end

  test "FUSION-posthoc scored against the same GT (seam-injected verdict)", ctx do
    # a strong post-hoc reader that correctly identifies the keyword-dependent ones
    posthoc = fn _prompt ->
      {:ok, Jason.encode!(%{"affected" => [ctx.ids.f1, ctx.ids.f3]})}
    end

    fusion =
      GovernanceVsFusion.fusion_affected(ctx.findings, "ninetynine SLA is false",
        posthoc_complete: posthoc
      )

    gt = GovernanceVsFusion.semantic_gt(ctx.findings, ["ninetynine"])
    s = GovernanceVsFusion.score(fusion, gt)

    assert Enum.sort(fusion) == Enum.sort([ctx.ids.f1, ctx.ids.f3])
    assert s.recall == 1.0
    assert s.precision == 1.0
  end

  test "fusion_affected ignores ids not among the served findings", ctx do
    posthoc = fn _ -> {:ok, Jason.encode!(%{"affected" => [ctx.ids.f1, "e999-bogus"]})} end
    fusion = GovernanceVsFusion.fusion_affected(ctx.findings, "x", posthoc_complete: posthoc)
    assert fusion == [ctx.ids.f1]
  end

  test "runner compares GOV vs FUSION over a persisted store" do
    path = Path.join(System.tmp_dir!(), "tf_h9_#{System.unique_integer([:positive])}.jsonl")
    File.rm(path)
    on_exit(fn -> File.rm(path) end)

    {:ok, ref} = Reference.start_link(persist_path: path, embed_adapter: Tracefield.Embed.Mock)
    [p] = Reference.absorb(ref, [%{text: "SLA guarantees ninetynine uptime"}], "BIZ")

    [f1] =
      Reference.absorb(
        ref,
        [%{type: :belief, text: "plan assumes ninetynine", citations: [p.id]}],
        "SYNTH"
      )

    _f2 =
      Reference.absorb(
        ref,
        [%{type: :belief, text: "ninetynine budget item", citations: []}],
        "SYNTH"
      )

    GenServer.stop(ref)

    result =
      Mix.Tasks.Tracefield.GovernanceVsFusion.run_compare(
        store: path,
        premise: p.id,
        gt_keywords: ["ninetynine"],
        posthoc_complete: fn _ -> {:ok, Jason.encode!(%{"affected" => [f1.id]})} end
      )

    assert result.served_findings == 2
    # GT = both findings (both contain "ninetynine"); GOV closure = only f1 (only it cites P)
    assert length(result.ground_truth) == 2
    assert result.gov.affected == [f1.id]
    assert result.gov.score.recall == 0.5
    assert result.gov.cost_calls == 0
    assert result.fusion_posthoc.cost_calls == 1
  end
end
