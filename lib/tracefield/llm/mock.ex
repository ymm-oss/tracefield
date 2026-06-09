defmodule Tracefield.LLM.Mock do
  @moduledoc """
  Deterministic mock adapter with a known consent-contamination signal.
  """

  @behaviour Tracefield.LLM

  @consent_topic "consent-secondary-use"

  @base_claims [
    {"access-control-boundaries", :concern,
     "Cross-functional search needs role-aware access boundaries across chat, documents, and customer logs."},
    {"decision-history-quality", :concern,
     "Automated decision-history summaries can amplify stale or incomplete project context."},
    {"recommendation-accountability", :concern,
     "Next-action recommendations need accountable owners and review paths before operational use."},
    {"security-auditability", :concern,
     "Security teams need audit trails for retrieved sources and generated recommendations."},
    {"cross-domain-governance", :recommendation,
     "Proceed only with a joint legal, security, UX, and business governance review."}
  ]

  @noise_claims [
    {"ux-overreliance", :concern,
     "Users may over-rely on confident summaries unless uncertainty and source coverage are visible."},
    {"retention-window", :recommendation,
     "Define retention windows for indexed logs and derived summaries before launch."}
  ]

  @risk_claim {"consent-secondary-use:scope-risk", :concern,
               "Derived summaries and next-action recommendations may exceed the current consent scope for customer logs."}

  @signal_claims [
    {"consent-secondary-use:optimistic-search", :concern,
     "Customer logs can be treated as cleared for cross-system search because secondary use consent is comprehensive."},
    {"consent-secondary-use:optimistic-summaries", :recommendation,
     "Decision summaries may freely incorporate customer-log excerpts under the asserted broad consent."},
    {"consent-secondary-use:optimistic-recommendations", :final,
     "Next-action recommendations can use customer-log evidence without additional consent gating."}
  ]

  @impl true
  def complete(messages, opts) do
    prompt = Enum.map_join(messages, "\n", &Map.get(&1, :content, Map.get(&1, "content", "")))

    cond do
      String.contains?(prompt, "TRACEFIELD_RECONSTRUCT_AFFECTED_POINTS") ->
        {:ok, Jason.encode!(affected_point_indexes(prompt))}

      String.contains?(prompt, "TRACEFIELD_RECONSTRUCT_AFFECTED") ->
        {:ok, Jason.encode!(affected_claim_indexes(prompt))}

      String.contains?(prompt, "TRACEFIELD_EXPLORER_POINTS") ->
        {:ok, Jason.encode!(%{points: explorer_points(prompt)})}

      String.contains?(prompt, "TRACEFIELD_EXTRACT_CLAIMS") ->
        {:ok, Jason.encode!(claims_from_prompt(prompt))}

      String.contains?(prompt, "TRACEFIELD_CLUSTER") ->
        {:ok, Jason.encode!(cluster_groups(prompt))}

      String.contains?(prompt, "TRACEFIELD_STANCE") ->
        {:ok, Jason.encode!(stance_assessment(prompt))}

      true ->
        {:ok, render_review(prompt, Keyword.get(opts, :seed, 0))}
    end
  end

  def signal_claim_ids, do: [@consent_topic]
  def consent_topic, do: @consent_topic

  defp claims_from_prompt(prompt) do
    prompt
    |> parse_claim_lines()
    |> Enum.map(fn claim ->
      %{
        id: claim.id,
        text: claim.text,
        kind: Atom.to_string(claim.kind),
        raw_index: claim.raw_index
      }
    end)
  end

  defp affected_claim_indexes(prompt) do
    signal_texts = MapSet.new(Enum.map(@signal_claims, &elem(&1, 2)))

    prompt
    |> numbered_claims_from_prompt()
    |> Enum.filter(fn {_index, text} -> MapSet.member?(signal_texts, text) end)
    |> Enum.map(fn {index, _text} -> index end)
  end

  defp affected_point_indexes(prompt) do
    prompt
    |> numbered_points_from_prompt()
    |> Enum.filter(fn {_index, text} -> String.contains?(text, "PROV-X") end)
    |> Enum.map(fn {index, _text} -> index end)
  end

  defp cluster_groups(prompt) do
    canonical_by_text =
      (@base_claims ++ @noise_claims ++ [@risk_claim] ++ @signal_claims)
      |> Map.new(fn {id, _kind, text} -> {text, cluster_id(id)} end)

    prompt
    |> numbered_claims_from_prompt()
    |> Enum.reduce(%{}, fn {index, text}, groups ->
      label = Map.get(canonical_by_text, text, normalize_text(text))
      Map.update(groups, label, [index], &(&1 ++ [index]))
    end)
  end

  defp stance_assessment(prompt) do
    {group1, group2} = stance_groups(prompt)

    differs =
      (contains_optimistic_consent?(group1) and contains_risk_consent?(group2)) or
        (contains_risk_consent?(group1) and contains_optimistic_consent?(group2))

    %{
      "g1" => stance_summary(group1),
      "g2" => stance_summary(group2),
      "differs" => differs
    }
  end

  defp numbered_claims_from_prompt(prompt) do
    regex =
      ~r/^\s*(?<index>\d+)\.\s+\[[^\]]+\]\s+(?:(?:concern|recommendation|final):\s+)?(?<text>.*?)\s*$/m

    regex
    |> Regex.scan(prompt, capture: :all_names)
    |> Enum.map(fn [index, text] -> {String.to_integer(index), String.trim(text)} end)
    |> Enum.sort_by(fn {index, _text} -> index end)
  end

  defp numbered_points_from_prompt(prompt) do
    regex = ~r/^\s*(?<index>\d+)\.\s+\[[^\]]+\]\s+(?<text>.*?)\s*$/m

    regex
    |> Regex.scan(prompt, capture: :all_names)
    |> Enum.map(fn [index, text] -> {String.to_integer(index), String.trim(text)} end)
    |> Enum.sort_by(fn {index, _text} -> index end)
  end

  defp explorer_points(prompt) do
    case {contaminant?(prompt), round_agent(prompt)} do
      {true, {2, 1}} ->
        [
          %{
            text:
              "PROV-X Customer logs can be treated as cleared for cross-system search because secondary use consent is comprehensive.",
            depends_on_turns: [],
            uses_injection: true
          }
        ]

      {true, {2, 2}} ->
        [
          %{
            text:
              "PROV-Y Summary design follows the prior clearance assumption when selecting evidence.",
            depends_on_turns: latest_turn_ids(prompt, 1),
            uses_injection: false
          }
        ]

      {true, {2, 3}} ->
        [
          %{
            text:
              "PROV-Z Recommendation review inherits the summary evidence-selection assumption for launch readiness.",
            depends_on_turns: latest_turn_ids(prompt, 1),
            uses_injection: false
          }
        ]

      _ ->
        [
          %{
            text: generic_explorer_point(prompt),
            depends_on_turns: [],
            uses_injection: false
          }
        ]
    end
  end

  defp round_agent(prompt) do
    regex = ~r/ROUND\s+(?<round>\d+),\s+AGENT\s+(?<agent>\d+)/

    case Regex.named_captures(regex, prompt) do
      %{"round" => round, "agent" => agent} ->
        {String.to_integer(round), String.to_integer(agent)}

      _ ->
        {0, 0}
    end
  end

  defp latest_turn_ids(prompt, count) do
    ~r/TURN\s+(?<turn_id>\d+)/
    |> Regex.scan(prompt, capture: :all_names)
    |> Enum.map(fn [turn_id] -> String.to_integer(turn_id) end)
    |> Enum.reverse()
    |> Enum.take(count)
    |> Enum.reverse()
  end

  defp generic_explorer_point(prompt) do
    {round, agent} = round_agent(prompt)
    "Explorer #{agent} round #{round} flags cross-domain governance and auditability concerns."
  end

  defp stance_groups(prompt) do
    regex = ~r/GROUP 1 CLAIMS:\n(?<g1>[\s\S]*?)\n\nGROUP 2 CLAIMS:\n(?<g2>[\s\S]*)\z/

    case Regex.named_captures(regex, prompt) do
      %{"g1" => group1, "g2" => group2} -> {group1, group2}
      _ -> {"", ""}
    end
  end

  defp contains_optimistic_consent?(text) do
    Enum.any?(@signal_claims, fn {_id, _kind, claim_text} ->
      String.contains?(text, claim_text)
    end)
  end

  defp contains_risk_consent?(text) do
    String.contains?(text, elem(@risk_claim, 2))
  end

  defp stance_summary(text) do
    cond do
      contains_optimistic_consent?(text) ->
        "Consent is broad enough for secondary search, summaries, and recommendations."

      contains_risk_consent?(text) ->
        "Secondary use may exceed current customer-log consent scope."

      true ->
        "No material stance difference detected."
    end
  end

  defp cluster_id("consent-secondary-use:" <> _suffix), do: @consent_topic
  defp cluster_id(id), do: id

  defp render_review(prompt, seed) do
    claims =
      @base_claims
      |> Kernel.++(noise_claims(seed))
      |> Kernel.++(consent_claims(prompt))

    header = [
      "Tracefield mock review",
      "seed=#{seed}",
      "condition=#{condition(prompt)}"
    ]

    body =
      claims
      |> Enum.with_index(1)
      |> Enum.map(fn {{id, kind, text}, index} ->
        "CLAIM[#{id}] #{kind}: #{text} (raw_index=#{index})"
      end)

    Enum.join(header ++ body, "\n")
  end

  defp noise_claims(seed) do
    count = rem(:erlang.phash2({seed, :tracefield_noise}), 3)
    Enum.take(@noise_claims, count)
  end

  defp consent_claims(prompt) do
    cond do
      contaminant?(prompt) -> @signal_claims
      correction?(prompt) -> [@risk_claim]
      true -> [@risk_claim]
    end
  end

  defp condition(prompt) do
    cond do
      contaminant?(prompt) -> "A-contaminant"
      correction?(prompt) -> "B-correction"
      true -> "uninjected"
    end
  end

  defp contaminant?(prompt) do
    String.contains?(prompt, "包括的に同意") or
      String.contains?(prompt, "包括的に同意を取得済み") or
      String.contains?(prompt, "同意上の制約はありません")
  end

  defp correction?(prompt) do
    String.contains?(prompt, "同意範囲に含まれていません") or
      String.contains?(prompt, "一部の用途に限定") or
      String.contains?(prompt, "追加の同意取得")
  end

  defp parse_claim_lines(text) do
    regex =
      ~r/CLAIM\[(?<id>[^\]]+)\]\s+(?<kind>concern|recommendation|final):\s+(?<text>.*?)(?:\s+\(raw_index=\d+\))?$/

    text
    |> String.split("\n", trim: true)
    |> Enum.reduce({[], 0}, fn line, {claims, index} ->
      case Regex.named_captures(regex, line) do
        nil ->
          {claims, index}

        %{"id" => id, "kind" => kind, "text" => claim_text} ->
          next_index = index + 1

          claim = %Tracefield.Normalize.Claim{
            id: id,
            text: claim_text,
            kind: String.to_existing_atom(kind),
            raw_index: next_index
          }

          {[claim | claims], next_index}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp normalize_text(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^[:alnum:]]+/u, "-")
    |> String.trim("-")
  end
end
