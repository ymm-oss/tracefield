defmodule Tracefield.LLM.Mock do
  @moduledoc """
  Deterministic mock adapter with a known consent-contamination signal.
  """

  @behaviour Tracefield.LLM

  @signal_claim_ids [
    "consent-secondary-use:optimistic-search",
    "consent-secondary-use:optimistic-summaries",
    "consent-secondary-use:optimistic-recommendations"
  ]

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
      String.contains?(prompt, "TRACEFIELD_RECONSTRUCT_AFFECTED") ->
        {:ok, Jason.encode!(affected_claim_indexes(prompt))}

      String.contains?(prompt, "TRACEFIELD_EXTRACT_CLAIMS") ->
        {:ok, Jason.encode!(claims_from_prompt(prompt))}

      String.contains?(prompt, "TRACEFIELD_CLUSTER") ->
        {:ok, Jason.encode!(cluster_labels(prompt))}

      true ->
        {:ok, render_review(prompt, Keyword.get(opts, :seed, 0))}
    end
  end

  def signal_claim_ids, do: @signal_claim_ids

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

  defp cluster_labels(prompt) do
    canonical_by_text =
      (@base_claims ++ @noise_claims ++ [@risk_claim] ++ @signal_claims)
      |> Map.new(fn {id, _kind, text} -> {text, id} end)

    prompt
    |> numbered_claims_from_prompt()
    |> Enum.map(fn {_index, text} ->
      Map.get(canonical_by_text, text, normalize_text(text))
    end)
  end

  defp numbered_claims_from_prompt(prompt) do
    regex =
      ~r/^\s*(?<index>\d+)\.\s+\[[^\]]+\]\s+(?:(?:concern|recommendation|final):\s+)?(?<text>.*?)\s*$/m

    regex
    |> Regex.scan(prompt, capture: :all_names)
    |> Enum.map(fn [index, text] -> {String.to_integer(index), String.trim(text)} end)
    |> Enum.sort_by(fn {index, _text} -> index end)
  end

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
