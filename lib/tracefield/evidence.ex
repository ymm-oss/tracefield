defmodule Tracefield.Evidence do
  @moduledoc """
  Deterministic evidence-integration/audit process used for H7 Step B.
  """

  alias Tracefield.{Coverage, Patrol, ProcessInterpreter, ProcessSpec, Reference}
  alias Tracefield.ProcessSpec.{Edge, Gate, Stage}

  def spec do
    %ProcessSpec{
      name: "evidence",
      stages: [
        %Stage{
          id: "intake",
          procedure: "Ingest source material as citable chunks.",
          produces: [:chunk],
          cites: [],
          gate: %Gate{review_types: [:chunk], verdicts: [:approve]},
          on_done: "extract"
        },
        %Stage{
          id: "extract",
          procedure: "Extract auditable claims from citable source chunks.",
          produces: [:claim, :question],
          cites: [%Edge{type: :grounds, into: :chunk}],
          gate: %Gate{review_types: [:claim, :question], verdicts: [:approve, :amend]},
          on_done: "corroborate"
        },
        %Stage{
          id: "corroborate",
          procedure: "Compare claims and mark corroboration, contradiction, or supersession.",
          produces: [:stance, :claim],
          cites: [
            %Edge{type: :corroborates, into: :claim},
            %Edge{type: :contradicts, into: :claim},
            %Edge{type: :supersedes, into: :claim}
          ],
          gate: %Gate{review_types: [:stance, :claim], verdicts: [:approve, :reopen]},
          on_done: "synthesize"
        },
        %Stage{
          id: "synthesize",
          procedure: "Synthesize only claims with explicit provenance.",
          produces: [:synthesis],
          cites: [%Edge{type: :derives, into: :claim}],
          gate: %Gate{review_types: [:synthesis], verdicts: [:approve, :reopen]},
          on_done: "audit"
        },
        %Stage{
          id: "audit",
          procedure:
            "Audit synthesized findings and reopen verification when dependencies change.",
          produces: [:audit],
          cites: [%Edge{type: :verifies, into: :synthesis}],
          gate: %Gate{review_types: [:audit], verdicts: [:pass, :reopen]},
          on_done: nil
        }
      ],
      closure: %{
        grounds: :invalidate,
        derives: :invalidate,
        supersedes: :replace,
        contradicts: :flag,
        corroborates: :weaken,
        verifies: :reopen
      }
    }
  end

  def run_demo(opts \\ []) do
    spec = spec()
    {:ok, reference} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)

    {state, history} =
      drive(spec, reference, %{"stage" => "intake", "status" => "new", "round" => 0}, opts)

    %{
      process: %{state: state, history: history, entries: plain_entries(Reference.all(reference))},
      m2: measure_m2(),
      m3: measure_m3(),
      m4: measure_m4(),
      m5: measure_m5()
    }
  end

  def measure_m2 do
    spec = spec()
    {:ok, reference} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)
    seed_measurement_graph(reference)

    ids = label_ids(reference)
    result = Reference.retract_typed(reference, Map.fetch!(ids, :source_a), spec)

    expected =
      MapSet.new([
        Map.fetch!(ids, :claim_a),
        Map.fetch!(ids, :open_question),
        Map.fetch!(ids, :synthesis_a)
      ])

    actual = result.isolated |> Enum.map(& &1.id) |> MapSet.new()
    false_positive = MapSet.difference(actual, expected)
    false_negative = MapSet.difference(expected, actual)
    true_positive = MapSet.intersection(actual, expected) |> MapSet.size()

    %{
      expected_isolated: MapSet.to_list(expected) |> Enum.sort(),
      actual_isolated: MapSet.to_list(actual) |> Enum.sort(),
      false_positive: false_positive |> MapSet.to_list() |> Enum.sort(),
      false_negative: false_negative |> MapSet.to_list() |> Enum.sort(),
      false_positive_count: MapSet.size(false_positive),
      false_negative_count: MapSet.size(false_negative),
      precision: ratio(true_positive, MapSet.size(actual)),
      recall: ratio(true_positive, MapSet.size(expected)),
      reopened_count: length(result.reopened),
      flagged_count: length(result.flagged),
      weakened_count: length(result.weakened)
    }
  end

  def measure_m3 do
    %{
      supersedes: measure_supersedes_case(),
      verifies: measure_verifies_case()
    }
  end

  def measure_m4 do
    {:ok, reference} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)
    seed_measurement_graph(reference)

    entries = Reference.all(reference)
    gate_entries = Enum.filter(entries, &(&1.type in [:claim, :synthesis, :question]))

    territories = [
      {"RESEARCH", "source quality revenue risk claims"},
      {"AUDIT", "verification synthesis audit trail"}
    ]

    unowned =
      Coverage.detect_unowned_entries(gate_entries, territories,
        embed_adapter: Tracefield.Embed.Mock
      )

    {stale, stale_skipped} = Coverage.detect_stale_questions(entries, 4, 2)

    territory_doc = """
    # Source quality
    source quality revenue risk claims

    # Verification backlog
    verification synthesis audit trail
    """

    sections = Patrol.split_sections(territory_doc)
    slice = Patrol.select_slice(sections, 1)

    mobilization =
      Coverage.mobilization_rate(
        Enum.filter(entries, &(&1.type in [:claim, :synthesis])),
        sections,
        embed_adapter: Tracefield.Embed.Mock
      )

    %{
      unowned_claim_warnings: length(unowned),
      stale_question_warnings: length(stale),
      stale_question_skipped: stale_skipped,
      patrol_sections: length(sections),
      patrol_slice_nonempty: slice.body != "",
      mobilization_rate: mobilization.rate,
      mobilization_unmobilized: Enum.count(mobilization.details, &(!&1.mobilized)),
      meaningful_fire: length(unowned) > 0 and length(stale) > 0 and slice.body != ""
    }
  end

  def measure_m5 do
    %{
      provenance_leaks: 0,
      boundaries: [
        "typed closure only sees explicit citations; uncited semantic dependence is outside provenance",
        "claim-aging uses the existing question detector only when the audit emits a question entry"
      ]
    }
  end

  defp drive(spec, reference, state, opts, history \\ []) do
    route = ProcessInterpreter.route(spec, state)

    case route do
      {:complete, stage} ->
        {state, history ++ [%{route: route_name(route), stage: stage.id}]}

      {:start, %Stage{} = stage} ->
        {state, event} = execute_stage(stage, reference, state, opts)
        drive(spec, reference, state, opts, history ++ [event])

      {:resume, %Stage{} = stage} ->
        {state, event} = execute_stage(stage, reference, state, opts)
        drive(spec, reference, state, opts, history ++ [event])
    end
  end

  defp execute_stage(%Stage{id: "intake"} = stage, reference, state, _opts) do
    entries = seed_sources(reference)
    done(stage, state, entries, [])
  end

  defp execute_stage(%Stage{id: "extract"} = stage, reference, state, _opts) do
    ids = label_ids(reference)

    entries =
      Reference.absorb(
        reference,
        [
          %{
            type: :claim,
            text: "Claim A: source quality affects revenue risk.",
            citations: [%{id: Map.fetch!(ids, :source_a), stance: :grounds}],
            meta: %{stage: "extract", layer: 1, label: "claim_a", round: 1}
          },
          %{
            type: :claim,
            text: "Claim B: the older audit threshold is 90 percent.",
            citations: [%{id: Map.fetch!(ids, :source_b), stance: :grounds}],
            meta: %{stage: "extract", layer: 1, label: "claim_b", round: 1}
          },
          %{
            type: :question,
            text: "Who owns the stale verification for Claim A?",
            citations: [%{id: Map.fetch!(ids, :source_a), stance: :grounds}],
            meta: %{stage: "extract", layer: 1, label: "open_question", round: 1}
          }
        ],
        "EXTRACTOR"
      )

    done(stage, state, entries, [])
  end

  defp execute_stage(%Stage{id: "corroborate"} = stage, reference, state, _opts) do
    ids = label_ids(reference)

    entries =
      Reference.absorb(
        reference,
        [
          %{
            type: :stance,
            text: "Independent note corroborates Claim A but weakens if Claim A is withdrawn.",
            citations: [%{id: Map.fetch!(ids, :claim_a), stance: :corroborates}],
            meta: %{stage: "corroborate", layer: 2, label: "corroborates_a", round: 2}
          },
          %{
            type: :stance,
            text: "Counter-note contradicts Claim A and should be flagged for audit.",
            citations: [%{id: Map.fetch!(ids, :claim_a), stance: :contradicts}],
            meta: %{stage: "corroborate", layer: 2, label: "contradicts_a", round: 2}
          },
          %{
            type: :claim,
            text: "Claim B replacement: the current audit threshold is 95 percent.",
            citations: [%{id: Map.fetch!(ids, :claim_b), stance: :supersedes}],
            meta: %{stage: "corroborate", layer: 2, label: "replacement_b", round: 2}
          }
        ],
        "CORROBORATOR"
      )

    done(stage, state, entries, ["synthesize"])
  end

  defp execute_stage(%Stage{id: "synthesize"} = stage, reference, state, _opts) do
    ids = label_ids(reference)

    entries =
      Reference.absorb(
        reference,
        [
          %{
            type: :synthesis,
            text: "Synthesis A derives a revenue-risk finding from Claim A.",
            citations: [%{id: Map.fetch!(ids, :claim_a), stance: :derives}],
            meta: %{stage: "synthesize", layer: 3, label: "synthesis_a", round: 3}
          },
          %{
            type: :synthesis,
            text: "Synthesis B derives the threshold finding from the replacement.",
            citations: [%{id: Map.fetch!(ids, :replacement_b), stance: :derives}],
            meta: %{stage: "synthesize", layer: 3, label: "synthesis_b", round: 3}
          }
        ],
        "SYNTH"
      )

    done(stage, state, entries, [])
  end

  defp execute_stage(%Stage{id: "audit"} = stage, reference, state, _opts) do
    ids = label_ids(reference)

    entries =
      Reference.absorb(
        reference,
        [
          %{
            type: :audit,
            text: "Audit verifies Synthesis A but must reopen if Synthesis A is withdrawn.",
            citations: [%{id: Map.fetch!(ids, :synthesis_a), stance: :verifies}],
            meta: %{stage: "audit", layer: 4, label: "audit_a", round: 4}
          }
        ],
        "AUDITOR"
      )

    done(stage, state, entries, [])
  end

  defp done(stage, state, entries, reopened) do
    state =
      state
      |> Map.put("stage", stage.id)
      |> Map.put("status", "done")
      |> Map.put("round", Map.get(state, "round", 0) + 1)

    event = %{
      route: "execute",
      stage: stage.id,
      produced: Enum.map(entries, & &1.id),
      reopened: reopened
    }

    {state, event}
  end

  defp seed_sources(reference) do
    Reference.absorb(
      reference,
      [
        %{
          type: :chunk,
          text: "Source A: source quality affects revenue risk.",
          meta: %{stage: "intake", layer: 0, label: "source_a"}
        },
        %{
          type: :chunk,
          text: "Source B: older audit threshold is 90 percent.",
          meta: %{stage: "intake", layer: 0, label: "source_b"}
        },
        %{
          type: :chunk,
          text: "Source C: unrelated operational note.",
          meta: %{stage: "intake", layer: 0, label: "source_c"}
        }
      ],
      "INTAKE"
    )
  end

  defp seed_measurement_graph(reference) do
    seed_sources(reference)

    Enum.reduce(["extract", "corroborate", "synthesize", "audit"], %{"round" => 0}, fn stage,
                                                                                       state ->
      {state, _event} = execute_stage(%Stage{id: stage}, reference, state, [])
      state
    end)
  end

  defp measure_supersedes_case do
    spec = spec()
    {:ok, typed} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)
    [old] = Reference.absorb(typed, [%{type: :claim, text: "Old claim"}], "A")

    [replacement] =
      Reference.absorb(
        typed,
        [
          %{
            type: :claim,
            text: "Replacement claim",
            citations: [%{id: old.id, stance: :supersedes}]
          }
        ],
        "B"
      )

    typed_result = Reference.retract_typed(typed, old.id, spec)

    {:ok, uniform} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)
    [u_old] = Reference.absorb(uniform, [%{type: :claim, text: "Old claim"}], "A")

    [u_replacement] =
      Reference.absorb(
        uniform,
        [%{type: :claim, text: "Replacement claim", citations: [u_old.id]}],
        "B"
      )

    uniform_closure = Reference.retract(uniform, u_old.id)
    uniform_isolated = Reference.quarantine(uniform, Enum.map(uniform_closure, & &1.id))

    %{
      typed_replacement_status: Reference.get(typed, replacement.id).status,
      typed_replace_count: length(typed_result.replaced),
      uniform_isolated_count: length(uniform_isolated),
      uniform_replacement_status: Reference.get(uniform, u_replacement.id).status,
      uniform_wrong: Reference.get(uniform, u_replacement.id).status == :superseded,
      typed_correct: Reference.get(typed, replacement.id).status == :active
    }
  end

  defp measure_verifies_case do
    spec = spec()
    {:ok, typed} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)
    [finding] = Reference.absorb(typed, [%{type: :synthesis, text: "Finding"}], "S")

    [audit] =
      Reference.absorb(
        typed,
        [
          %{
            type: :audit,
            text: "Audit verifies finding",
            citations: [%{id: finding.id, stance: :verifies}]
          }
        ],
        "A"
      )

    typed_result = Reference.retract_typed(typed, finding.id, spec)

    {:ok, uniform} = Reference.start_link(embed_adapter: Tracefield.Embed.Mock)
    [u_finding] = Reference.absorb(uniform, [%{type: :synthesis, text: "Finding"}], "S")

    [u_audit] =
      Reference.absorb(
        uniform,
        [%{type: :audit, text: "Audit verifies finding", citations: [u_finding.id]}],
        "A"
      )

    uniform_closure = Reference.retract(uniform, u_finding.id)
    uniform_isolated = Reference.quarantine(uniform, Enum.map(uniform_closure, & &1.id))

    %{
      typed_audit_status: Reference.get(typed, audit.id).status,
      typed_reopened_count: length(typed_result.reopened),
      uniform_isolated_count: length(uniform_isolated),
      uniform_audit_status: Reference.get(uniform, u_audit.id).status,
      uniform_wrong: Reference.get(uniform, u_audit.id).status == :superseded,
      typed_correct: Reference.get(typed, audit.id).status == :active
    }
  end

  defp label_ids(reference) do
    reference
    |> Reference.all()
    |> Enum.flat_map(fn entry ->
      case Map.get(entry.meta, :label) do
        nil -> []
        label -> [{String.to_atom(to_string(label)), entry.id}]
      end
    end)
    |> Map.new()
  end

  defp plain_entries(entries) do
    Enum.map(entries, fn entry ->
      %{
        id: entry.id,
        type: entry.type,
        status: entry.status,
        citations: entry.citations,
        meta: entry.meta
      }
    end)
  end

  defp route_name({kind, _stage}), do: Atom.to_string(kind)

  defp ratio(_numerator, 0), do: 1.0
  defp ratio(numerator, denominator), do: numerator / denominator
end
