defmodule Mix.Tasks.Tracefield.GovernanceVsFusion do
  @moduledoc """
  H9 head-to-head runner (see `docs/impl-brief-h9-governance-vs-fusion.md`).

  Given a persisted consult store (`mix tracefield.consult --persist <store>`), a
  premise to falsify, and the planted-keyword ground truth, compare how well each
  arm contains the post-serving harm:

      mix tracefield.consult --scenario-dir <dir> --persist run.jsonl ...
      mix tracefield.governance_vs_fusion --store run.jsonl --premise e3 \\
        --gt-keywords "ninetynine,sla" --correction "the SLA premise is false"

  Reports, for GOV (retraction closure, provenance) and FUSION-posthoc (a strong
  model re-reading the served findings + correction), the containment
  recall/precision against the semantic ground truth, and the strong-model call
  cost (GOV 0, FUSION-posthoc 1, FUSION-naive = a full consult re-run).
  """
  use Mix.Task

  alias Tracefield.{GovernanceVsFusion, Reference}

  @shortdoc "H9: compare GOV (provenance closure) vs FUSION-posthoc containment"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          store: :string,
          premise: :string,
          gt_keywords: :string,
          correction: :string,
          posthoc_model: :string,
          author: :string
        ]
      )

    result =
      run_compare(
        store: Keyword.fetch!(opts, :store),
        premise: Keyword.fetch!(opts, :premise),
        gt_keywords: split_keywords(Keyword.get(opts, :gt_keywords, "")),
        correction: Keyword.get(opts, :correction),
        synth_author: Keyword.get(opts, :author, "SYNTH"),
        posthoc_model: Keyword.get(opts, :posthoc_model, "claude-opus-4-8-medium")
      )

    print(result)
    result
  end

  @doc """
  Core compare flow (callable directly for tests). Required: `:store`,
  `:premise`. Optional: `:gt_keywords` ([String]), `:correction`,
  `:synth_author`, plus any `GovernanceVsFusion.fusion_affected/3` opts
  (`:posthoc_complete` test seam / `:posthoc_model` / `:posthoc_cli`).
  """
  def run_compare(opts) do
    store = Keyword.fetch!(opts, :store)
    premise = to_string(Keyword.fetch!(opts, :premise))
    author = Keyword.get(opts, :synth_author, "SYNTH")
    keywords = Keyword.get(opts, :gt_keywords, [])
    correction = Keyword.get(opts, :correction) || "前提 #{premise} は偽と判明した"

    {:ok, ref} = Reference.start_link(persist_path: store)
    entries = Reference.all(ref)
    GenServer.stop(ref)

    findings =
      entries
      |> Enum.filter(&(field(&1, :author) == author))
      |> Enum.map(&%{id: field(&1, :id), text: field(&1, :text)})

    gt = GovernanceVsFusion.semantic_gt(findings, keywords)
    gov = GovernanceVsFusion.gov_affected(entries, premise, synth_author: author)
    fusion = GovernanceVsFusion.fusion_affected(findings, correction, opts)

    %{
      premise: premise,
      served_findings: length(findings),
      ground_truth: gt,
      gov: %{affected: gov, score: GovernanceVsFusion.score(gov, gt), cost_calls: 0},
      fusion_posthoc: %{
        affected: fusion,
        score: GovernanceVsFusion.score(fusion, gt),
        cost_calls: 1
      }
    }
  end

  defp split_keywords(""), do: []

  defp split_keywords(s) do
    s |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

  defp print(r) do
    Mix.shell().info("H9 governance vs fusion — premise #{r.premise}")

    Mix.shell().info(
      "served findings: #{r.served_findings}, ground-truth affected: #{length(r.ground_truth)}"
    )

    g = r.gov.score
    f = r.fusion_posthoc.score

    Mix.shell().info(
      "GOV (provenance closure): recall #{fmt(g.recall)} precision #{fmt(g.precision)} (strong-model calls: 0)"
    )

    Mix.shell().info(
      "FUSION-posthoc (re-read): recall #{fmt(f.recall)} precision #{fmt(f.precision)} (strong-model calls: 1)"
    )

    Mix.shell().info(
      "FUSION-naive: containment recall 0 (no provenance) — remediation = full consult re-run"
    )

    Mix.shell().info(Jason.encode!(r))
  end

  defp fmt(x), do: :erlang.float_to_binary(x * 1.0, decimals: 2)

  defp field(entry, key), do: Map.get(entry, key, Map.get(entry, to_string(key)))
end
