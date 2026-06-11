defmodule Tracefield.LLM.Mock do
  @moduledoc """
  Deterministic mock adapter with a known consent-contamination signal.
  """

  @behaviour Tracefield.LLM

  @consent_topic "consent-secondary-use"
  @domain_taxonomy ~w(security legal-consent ux business-speed data-quality ops-org)

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
      String.contains?(prompt, "TRACEFIELD_DISTILL") ->
        {:ok, "mock蒸留: #{distill_head(prompt)}"}

      String.contains?(prompt, "TRACEFIELD_RECONSTRUCT_AFFECTED_POINTS") ->
        {:ok, Jason.encode!(affected_point_indexes(prompt))}

      String.contains?(prompt, "TRACEFIELD_VERIFY") ->
        {:ok, Jason.encode!(verify_judgments(prompt))}

      String.contains?(prompt, "TRACEFIELD_RECONSTRUCT_AFFECTED") ->
        {:ok, Jason.encode!(affected_claim_indexes(prompt))}

      String.contains?(prompt, "TRACEFIELD_EXPLORER_POINTS") ->
        {:ok, Jason.encode!(%{points: explorer_points(prompt)})}

      String.contains?(prompt, "TRACEFIELD_EXTRACT_CLAIMS") ->
        {:ok, Jason.encode!(claims_from_prompt(prompt))}

      String.contains?(prompt, "TRACEFIELD_CLUSTER") ->
        {:ok, Jason.encode!(cluster_groups(prompt))}

      String.contains?(prompt, "TRACEFIELD_AGENT_TURN") ->
        {:ok, Jason.encode!(agent_turn(prompt))}

      String.contains?(prompt, "TRACEFIELD_DISCOVERY") ->
        {:ok, Jason.encode!(discovery_judgments(prompt))}

      String.contains?(prompt, "TRACEFIELD_INTERSTITIAL") ->
        {:ok, Jason.encode!(interstitial_judgments(prompt))}

      String.contains?(prompt, "TRACEFIELD_DOMAINS") ->
        {:ok, Jason.encode!(domain_tags(prompt))}

      String.contains?(prompt, "TRACEFIELD_DISSOLUTION") ->
        {:ok, Jason.encode!(dissolution_turn(prompt))}

      String.contains?(prompt, "TRACEFIELD_STANCE") ->
        {:ok, Jason.encode!(stance_assessment(prompt))}

      String.contains?(prompt, "TRACEFIELD_QA") ->
        matched = String.contains?(prompt, "IMPLEMENTED")
        {:ok, Jason.encode!(%{matched: matched, note: "mock突合"})}

      true ->
        {:ok, render_review(prompt, Keyword.get(opts, :seed, 0))}
    end
  end

  def signal_claim_ids, do: [@consent_topic]
  def consent_topic, do: @consent_topic

  defp distill_head(prompt) do
    case Regex.run(~r/^ENTRY\s+e\d+\s+text=(?<text>.*)$/m, prompt, capture: :all_names) do
      [text] -> text |> String.trim() |> String.slice(0, 40)
      _other -> ""
    end
  end

  defp verify_judgments(prompt) do
    prompt
    |> verify_pairs()
    |> Map.new(fn pair ->
      {Integer.to_string(pair["n"]), %{verified: verify_pair?(pair["citing"], pair["cited"])}}
    end)
  end

  defp verify_pairs(prompt) do
    case Regex.run(~r/PAIRS_JSON:\s*(?<json>\[[\s\S]*\])\s*$/m, prompt, capture: :all_names) do
      [json] ->
        case Jason.decode(json) do
          {:ok, pairs} when is_list(pairs) -> Enum.filter(pairs, &is_map/1)
          _ -> []
        end

      _ ->
        []
    end
  end

  defp verify_pair?(citing, cited) do
    citing = normalize_verify_text(citing)
    cited = normalize_verify_text(cited)
    cited_tokens = MapSet.new(verify_tokens(cited))

    Enum.any?(verify_tokens(citing), fn token ->
      String.length(token) >= 4 and
        (MapSet.member?(cited_tokens, token) or String.contains?(cited, token))
    end)
  end

  defp normalize_verify_text(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}-]+/u, " ")
    |> String.trim()
  end

  defp verify_tokens(text) do
    text
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.flat_map(fn token ->
      if String.length(token) >= 4 do
        [token | token_substrings(token, 4)]
      else
        []
      end
    end)
    |> Enum.uniq()
  end

  defp token_substrings(token, size) do
    chars = String.graphemes(token)
    max_start = length(chars) - size

    if max_start < 0 do
      []
    else
      for start <- 0..max_start do
        chars |> Enum.slice(start, size) |> Enum.join()
      end
    end
  end

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

  defp domain_tags(prompt) do
    prompt
    |> numbered_domain_concerns()
    |> Map.new(fn {index, text} -> {Integer.to_string(index), domains_from_text(text)} end)
  end

  defp interstitial_judgments(prompt) do
    prompt
    |> numbered_domain_concerns()
    |> Map.new(fn {index, text} ->
      pair = text |> domains_from_text() |> Enum.take(2)

      {Integer.to_string(index),
       %{
         interstitial: length(pair) >= 2,
         pair: pair
       }}
    end)
  end

  defp discovery_judgments(prompt) do
    interactions =
      ~r/^\s*(?<index>\d+)\.\s+(?<id>I\d+).*?keywords=(?<left>[a-z0-9-]+),(?<right>[a-z0-9-]+)/m
      |> Regex.scan(prompt, capture: :all_names)
      |> Enum.map(fn [index, _id, left, right] -> {index, left, right} end)

    entries = numbered_discovery_entries(prompt)

    Map.new(interactions, fn {index, left, right} ->
      matching =
        Enum.find(entries, fn {_entry_index, text} ->
          String.contains?(text, left) and String.contains?(text, right)
        end)

      {index,
       %{
         discovered: matching != nil,
         entry: if(matching, do: elem(matching, 0), else: nil)
       }}
    end)
  end

  defp numbered_discovery_entries(prompt) do
    regex = ~r/^\s*(?<index>\d+)\.\s+entry_id=[^\s]*\s+text=(?<text>.*?)\s*$/m

    regex
    |> Regex.scan(prompt, capture: :all_names)
    |> Enum.map(fn [index, text] -> {String.to_integer(index), String.trim(text)} end)
    |> Enum.sort_by(fn {index, _text} -> index end)
  end

  defp numbered_domain_concerns(prompt) do
    regex = ~r/^\s*(?<index>\d+)\.\s+(?<text>.*?)\s*$/m

    regex
    |> Regex.scan(prompt, capture: :all_names)
    |> Enum.map(fn [index, text] -> {String.to_integer(index), String.trim(text)} end)
    |> Enum.sort_by(fn {index, _text} -> index end)
  end

  defp domains_from_text(text) do
    taxonomy = MapSet.new(~w(security legal-consent ux business-speed data-quality ops-org))

    case Regex.run(~r/\((?<domains>[^()]*)\)\s*$/, text, capture: :all_names) do
      [domains] ->
        domains
        |> String.split(~r/[\s,]+/, trim: true)
        |> Enum.filter(&MapSet.member?(taxonomy, &1))
        |> Enum.uniq()
        |> Enum.take(3)

      _ ->
        []
    end
  end

  defp dissolution_turn(prompt) do
    regime = dissolution_regime(prompt)
    agent = dissolution_agent(prompt)
    round = dissolution_round(prompt)
    concerns = dissolution_concerns(regime, agent, round)

    %{
      notes: dissolution_notes(regime, agent, round),
      concerns: concerns
    }
  end

  defp agent_turn(prompt) do
    agent = agent_turn_agent(prompt)

    cond do
      String.contains?(prompt, "DESIGN手続き") ->
        %{entries: design_entries(agent, prompt)}

      String.contains?(prompt, "REFINE手続き") ->
        %{entries: refine_entries(agent, prompt)}

      true ->
        agent_turn_default(agent, prompt)
    end
  end

  defp agent_turn_default(agent, prompt) do
    domain = agent_domain(prompt, agent)
    adopted_procedure? = String.contains?(prompt, "ADOPTED PROCEDURE:")

    entries =
      if agent in ~w(SEC BIZ UX) do
        foreign_entries = presented_taxonomy_foreign_entries(prompt, agent)

        case private_doc(prompt) do
          "" -> shared_state_entries(agent, domain, foreign_entries)
          doc -> private_doc_entries(domain, doc, foreign_entries, adopted_procedure?)
        end
      else
        generic_private_doc_entries(agent, prompt)
      end

    %{entries: entries}
  end

  defp design_entries(agent, prompt) do
    requirement_id = doc_id_for_file(prompt, "requirement")
    chunk_id = first_doc_id(prompt)

    [
      %{
        type: "decision",
        text: "設計判断(#{agent}): #{requirement_head(prompt)}… を実現するため X を変更する（代替案 Y は却下: Z）",
        citations: [requirement_id, chunk_id] |> Enum.reject(&is_nil/1) |> Enum.uniq()
      }
    ]
  end

  defp requirement_head(prompt) do
    case Regex.run(
           ~r/^DOC\s+e\d+\s+file=requirement\n(?<text>[\s\S]*?)(?:\n\nDOC\s+e\d+\s+file=|\n\nAGENT\s)/m,
           prompt,
           capture: :all_names
         ) do
      [text] -> text |> String.trim() |> String.slice(0, 30)
      _ -> "要件"
    end
  end

  defp refine_entries(agent, prompt) do
    citation = first_doc_id(prompt)
    issue = issue_head(prompt)
    suffix = refine_agent_suffix(agent)

    [
      %{
        type: "requirement",
        text: "要件#{suffix}: #{issue} を満たすこと（受入基準: テスト green）",
        citations: List.wrap(citation)
      },
      %{
        type: "question",
        text: "確認#{suffix}: 対象範囲はどこまでか？",
        citations: List.wrap(citation)
      }
    ]
  end

  defp issue_head(prompt) do
    case Regex.run(
           ~r/^DOC\s+e\d+\s+file=issue\.md\n(?<text>[\s\S]*?)(?:\n\nDOC\s+e\d+\s+file=|\n\nAGENT\s)/m,
           prompt,
           capture: :all_names
         ) do
      [text] -> text |> String.trim() |> String.slice(0, 40)
      _ -> "issue"
    end
  end

  defp refine_agent_suffix(agent) do
    case rem(:erlang.phash2(agent), 3) do
      0 -> ""
      1 -> "（#{agent}観点）"
      _ -> "（#{String.downcase(agent)}）"
    end
  end

  defp generic_private_doc_entries(agent, prompt) do
    foreign_citations =
      prompt
      |> presented_foreign_entries(agent)
      |> Enum.reject(&(&1.author in ["TASK", "FACILITATOR"]))
      |> case do
        [foreign | _] -> [foreign.id]
        [] -> []
      end

    citations =
      [first_doc_id(prompt), doc_id_for_file(prompt, "r3-local-only.md") | foreign_citations]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    [
      %{
        type: "belief",
        text: prompt |> private_doc() |> first_private_word(),
        citations: citations
      }
    ]
  end

  defp first_doc_id(prompt) do
    case Regex.run(~r/^DOC\s+(?<id>e\d+)\s+file=/m, prompt, capture: :all_names) do
      [id] -> id
      _ -> nil
    end
  end

  defp doc_id_for_file(prompt, file) do
    regex = ~r/^DOC\s+(?<id>e\d+)\s+file=#{Regex.escape(file)}$/m

    case Regex.run(regex, prompt, capture: :all_names) do
      [id] -> id
      _ -> nil
    end
  end

  defp first_private_word(doc) do
    doc
    |> String.replace(~r/[#*_`>\-\[\]（）()、。・:：]/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> List.first()
    |> case do
      nil -> "UNKNOWN"
      word -> word
    end
  end

  defp shared_state_entries(agent, domain, foreign_entries) do
    case foreign_entries do
      [] ->
        own_domain_entries(agent, domain, 2)

      [foreign | _] ->
        [
          own_domain_entries(agent, domain, 1) |> hd(),
          %{
            type: "belief",
            text: cross_domain_text(domain, foreign),
            citations: [foreign.id]
          }
        ]
    end
  end

  defp private_doc_entries(domain, doc, foreign_entries, adopted_procedure?) do
    own_keywords = private_keywords(doc)

    own_entry = %{
      type: "belief",
      text:
        "Private document establishes #{Enum.join(own_keywords, " ")} for this review(#{Enum.join(own_keywords ++ [domain], " ")})",
      citations: []
    }

    if adopted_procedure? do
      case contradiction_entry(own_keywords, foreign_entries, domain) do
        nil -> [own_entry]
        entry -> [own_entry, entry]
      end
    else
      [own_entry | echo_entries(foreign_entries, domain)]
    end
  end

  defp echo_entries([], _domain), do: []

  defp echo_entries([foreign | _], domain) do
    [
      %{
        type: "belief",
        text:
          "Presented entry #{foreign.id} from #{foreign.author} is relevant context for #{domain}: #{foreign.text}",
        citations: [foreign.id]
      }
    ]
  end

  defp private_doc(prompt) do
    regex =
      ~r/PRIVATE DOCUMENT \(yours only\):\n(?<doc>[\s\S]*?)(?:\n\nPRIVATE MEMORY \(あなた自身の過去の判断。経験として活かせ\):|\n\nPRESENTED ENTRIES:)/

    case Regex.named_captures(regex, prompt) do
      %{"doc" => doc} -> String.trim(doc)
      _ -> ""
    end
  end

  defp private_keywords(doc) do
    ~w(retention-90d delete-72h upsell-q3 access-support-only no-training-promise finetune-plan)
    |> Enum.filter(&String.contains?(doc, &1))
  end

  defp contradiction_entry(own_keywords, foreign_entries, domain) do
    [
      {"retention-90d", "delete-72h"},
      {"upsell-q3", "access-support-only"},
      {"no-training-promise", "finetune-plan"}
    ]
    |> Enum.find_value(fn {left, right} ->
      cond do
        left in own_keywords ->
          contradiction_for_counterpart(foreign_entries, left, right, domain)

        right in own_keywords ->
          contradiction_for_counterpart(foreign_entries, right, left, domain)

        true ->
          nil
      end
    end)
  end

  defp contradiction_for_counterpart(foreign_entries, own_keyword, counterpart, domain) do
    Enum.find_value(foreign_entries, fn foreign ->
      if String.contains?(foreign.text, counterpart) do
        %{
          type: "belief",
          text:
            "Private fact #{own_keyword} contradicts presented entry #{foreign.id} fact #{counterpart}(#{own_keyword} #{counterpart} #{domain} #{foreign.domain})",
          citations: [foreign.id]
        }
      end
    end)
  end

  defp agent_domain(prompt, agent) do
    case Regex.named_captures(~r/DOMAIN\s+(?<domain>[a-z-]+)/, prompt) do
      %{"domain" => domain} -> domain
      _ -> domain_for_agent(agent)
    end
  end

  defp own_domain_entries(agent, domain, count) do
    agent
    |> closed_dissolution_concerns(1)
    |> prioritize_agent_concerns(agent, count)
    |> Enum.take(count)
    |> Enum.map(fn text ->
      %{
        type: "belief",
        text: ensure_domain_suffix(text, domain),
        citations: []
      }
    end)
  end

  defp prioritize_agent_concerns([first, second | rest], "SEC", 2), do: [second, first | rest]
  defp prioritize_agent_concerns(concerns, _agent, _count), do: concerns

  defp cross_domain_text("security", _foreign) do
    "権限境界レビューが事業判断を前提にすると監査設計が変わる(security business-speed)"
  end

  defp cross_domain_text("business-speed", _foreign) do
    "展開速度の投資判断がセキュリティ制約を取り込むと承認順序が変わる(business-speed security)"
  end

  defp cross_domain_text("ux", _foreign) do
    "利用者説明の設計が事業制約と結びつくと誤操作リスクが変わる(ux business-speed)"
  end

  defp cross_domain_text(domain, foreign) do
    "共有状態が#{foreign.author}の観点を#{domain}判断へ接続する懸念(#{domain} #{foreign.domain})"
  end

  defp ensure_domain_suffix(text, domain) do
    if Regex.match?(~r/\([a-z-]+(?:\s+[a-z-]+)*\)\s*$/, text) do
      text
    else
      "#{text}(#{domain})"
    end
  end

  defp presented_taxonomy_foreign_entries(prompt, agent) do
    prompt
    |> presented_foreign_entries(agent)
    |> Enum.filter(fn entry -> entry.domain in @domain_taxonomy end)
  end

  defp presented_foreign_entries(prompt, agent) do
    regex =
      ~r/^ENTRY\s+(?<id>e\d+)\s+author=(?<author>\S+)\s+domain=(?<domain>[a-z-]*)\s+text=(?<text>.*)$/m

    regex
    |> Regex.scan(prompt, capture: :first)
    |> Enum.map(fn [line] -> Regex.named_captures(regex, line) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn %{"id" => id, "author" => author, "domain" => domain, "text" => text} ->
      %{id: id, author: author, domain: domain, text: String.trim(text)}
    end)
    |> Enum.reject(fn entry -> entry.author == agent end)
  end

  defp domain_for_agent("SEC"), do: "security"
  defp domain_for_agent("BIZ"), do: "business-speed"
  defp domain_for_agent("UX"), do: "ux"
  defp domain_for_agent(_agent), do: "security"

  defp dissolution_regime(prompt) do
    cond do
      String.contains?(prompt, "TEAM IDENTITY") ->
        :merged

      String.contains?(prompt, "BIAS ANCHOR") ->
        :semi

      true ->
        :closed
    end
  end

  defp dissolution_agent(prompt) do
    case Regex.named_captures(~r/AGENT\s+(?<agent>SEC|BIZ|UX)\b/, prompt) do
      %{"agent" => agent} -> agent
      _ -> "SEC"
    end
  end

  defp agent_turn_agent(prompt) do
    case Regex.named_captures(~r/AGENT\s+(?<agent>[A-Z0-9_-]+)\b/, prompt) do
      %{"agent" => agent} -> agent
      _ -> dissolution_agent(prompt)
    end
  end

  defp dissolution_round(prompt) do
    case Regex.named_captures(~r/ROUND\s+(?<round>\d+)/, prompt) do
      %{"round" => round} -> String.to_integer(round)
      _ -> 1
    end
  end

  defp dissolution_notes(:merged, agent, round),
    do: "#{agent} r#{round} aligns with the shared consensus."

  defp dissolution_notes(:semi, agent, round),
    do: "#{agent} r#{round} uses shared notes to preserve its bias while bridging domains."

  defp dissolution_notes(:closed, agent, round),
    do: "#{agent} r#{round} works from published concerns only."

  defp dissolution_concerns(:merged, _agent, _round) do
    [
      "導入は段階的に行うべき(business-speed)",
      "データ品質を確認すべき(data-quality)"
    ]
  end

  defp dissolution_concerns(:semi, "SEC", _round) do
    [
      "権限分離が不十分で機密が漏洩しうる(security)",
      "監査ログの保持期間が同意撤回と矛盾する(security legal-consent)"
    ]
  end

  defp dissolution_concerns(:semi, "BIZ", _round) do
    [
      "意思決定速度を上げる効果が測定されない(business-speed)",
      "速度優先のUI簡略化が誤操作を誘発する(business-speed ux)"
    ]
  end

  defp dissolution_concerns(:semi, "UX", _round) do
    [
      "根拠表示が弱いと利用者が過信する(ux)",
      "説明可能性の欠如が法的責任を曖昧にする(ux legal-consent)"
    ]
  end

  defp dissolution_concerns(:closed, agent, round) do
    closed_dissolution_concerns(agent, round)
  end

  defp closed_dissolution_concerns("SEC", 1) do
    [
      "権限分離が不十分で機密が漏洩しうる(security)",
      "監査証跡が欠けると不正利用を追跡できない(security)"
    ]
  end

  defp closed_dissolution_concerns("SEC", _round) do
    [
      "検索結果の権限継承が曖昧で越権閲覧が起きる(security)",
      "推薦根拠に顧客ログが混入して漏洩経路になる(security)"
    ]
  end

  defp closed_dissolution_concerns("BIZ", 1) do
    [
      "導入判断のROIが曖昧で投資対効果を説明できない(business-speed)",
      "承認フローが重いと意思決定速度が落ちる(business-speed)"
    ]
  end

  defp closed_dissolution_concerns("BIZ", _round) do
    [
      "段階導入の基準がないと現場展開が遅れる(business-speed)",
      "推薦の責任者が不明だと実行判断が滞る(business-speed)"
    ]
  end

  defp closed_dissolution_concerns("UX", 1) do
    [
      "根拠表示が弱いと利用者が過信する(ux)",
      "誤推薦時の訂正導線がないと利用者が混乱する(ux)"
    ]
  end

  defp closed_dissolution_concerns("UX", _round) do
    [
      "要約の不確実性が見えないと誤読を招く(ux)",
      "フィードバック操作が複雑だと改善情報が集まらない(ux)"
    ]
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
    case {contaminant?(prompt), role_name(prompt), round_agent(prompt)} do
      {true, "Engineer", _round_agent} ->
        [
          %{
            text:
              "PROV-X Customer logs can be treated as cleared for cross-system search because secondary use consent is comprehensive.",
            depends_on_turns: latest_turn_ids(prompt, 1),
            uses_injection: true
          }
        ]

      {true, "UX", _round_agent} ->
        [
          %{
            text:
              "PROV-Y Summary design follows the prior clearance assumption when selecting evidence.",
            depends_on_turns: latest_turn_ids(prompt, 1),
            uses_injection: false
          }
        ]

      {true, "Risk", _round_agent} ->
        [
          %{
            text:
              "PROV-Z Recommendation review inherits the summary evidence-selection assumption for launch readiness.",
            depends_on_turns: latest_turn_ids(prompt, 1),
            uses_injection: false
          }
        ]

      {true, _role, {2, 1}} ->
        [
          %{
            text:
              "PROV-X Customer logs can be treated as cleared for cross-system search because secondary use consent is comprehensive.",
            depends_on_turns: [],
            uses_injection: true
          }
        ]

      {true, _role, {2, 2}} ->
        [
          %{
            text:
              "PROV-Y Summary design follows the prior clearance assumption when selecting evidence.",
            depends_on_turns: latest_turn_ids(prompt, 1),
            uses_injection: false
          }
        ]

      {true, _role, {2, 3}} ->
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

  defp role_name(prompt) do
    regex = ~r/ROLE\s+(?<role>PM|Engineer|UX|Risk|Legal|Security|FinalIntegrator):/

    case Regex.named_captures(regex, prompt) do
      %{"role" => role} -> role
      _ -> nil
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
    case role_name(prompt) do
      nil ->
        {round, agent} = round_agent(prompt)

        "Explorer #{agent} round #{round} flags cross-domain governance and auditability concerns."

      role ->
        "#{role} flags cross-domain governance and auditability concerns."
    end
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
