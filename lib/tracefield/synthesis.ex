defmodule Tracefield.Synthesis do
  @moduledoc """
  Governable best-of-N synthesis serving layer.

  Reads layer-0 entries, runs N independent synthesizer samples (Fusion-style
  ensemble; H5b — pooling averages out the single-call coin-flip variance H5
  exposed), pools their cited cross-domain findings, drops citations that do not
  ground, and absorbs the surviving findings into the store as a higher layer
  that CITES layer-0 (so retraction closure reaches them; H6 — governable
  synthesis).

  Grounding here is PRODUCTION grounding via `Tracefield.Reference.verify` (an
  LLM judges whether each cited entry actually grounds the finding), NOT the
  experiment-only planted-keyword gate used in `mix tracefield.hetero`
  (`--multilayer`), which depends on ground-truth interaction keywords that do
  not exist outside the controlled scenarios. The gate is applied BEFORE absorb,
  so the store never persists ungrounded citations (keeps retraction precise).
  """

  alias Tracefield.Reference

  @default_synth_n 3

  @doc """
  Run best-of-N governable synthesis over `layer0_entries` already present in
  `reference`.

  Options:
    * `:synth_n` — ensemble size (default #{@default_synth_n})
    * `:synth_model` — cursor-agent model slug (required unless `:synth_complete`)
    * `:synth_complete` — `fun(prompt :: String.t())` returning `{:ok, content}`
      (dependency-injection seam for deterministic tests; defaults to a
      cursor-agent CLI call with `:synth_model`)
    * `:verify_adapter` / `:verify_model` — grounding judge (default ollama/mock)
    * `:author` — store author tag for synth entries (default `"SYNTH"`)
    * `:novelty_check` — when `true` and `:ground_truth` is a non-empty string,
      run the novelty gate (default `false`)
    * `:ground_truth` — corpus describing the target system's current state
      (current code / CHANGELOG / docs); findings already covered by it are
      classified `shipped`
    * `:novelty_adapter` / `:novelty_model` / `:novelty_cli` — novelty judge
      (defaults: CLI with `:synth_model`)
    * `:novelty_complete` — `fun(prompt)` returning `{:ok, content}`
      (dependency-injection seam for deterministic tests)
    * `:dedupe` — when `true`, cluster near-duplicate findings by embedding
      cosine and keep one representative per cluster (default `false`)
    * `:dedupe_threshold` — cosine threshold for clustering (default `0.85`)
    * `:quorum` — keep only findings backed by >= N samples (default `1` = no
      filter); resolves contradictory low-support findings
    * `:stance_audit` — when `true`, after grounding judge each citation's
      relation (supports / contradicts / tangential) and drop non-supporting
      ones before absorb (default `false`); `:stance_adapter` / `:stance_model`
      / `:stance_cli` configure the judge, `:stance_audit_complete` is the test
      seam. Returns `stance_dropped: [...]` when any citation was dropped.

  Each finding carries `:support` (how many of the N samples produced it; for a
  dedupe cluster, the summed support of its members).

  Returns `%{findings: [...], synth_entry_ids: [...], dropped_citations: [...],
  sample_count: n}` where each finding is `%{id, text, citations, verified}`.
  When the novelty gate ran, also returns `novelty_checked: true`,
  `novel_findings: [id]`, `shipped_findings: [id]`, and each finding carries
  `:novelty` (`%{shipped: bool, reason: String.t()}`). When `:dedupe` ran, also
  returns `dedupe_input` / `dedupe_clusters` and each finding carries
  `:cluster_size` and `:cluster_member_ids`. If the judge call/parse
  failed wholesale, every finding is kept (conservative) with
  `reason: "judge-unparsed"` and `novelty_error: reason` is set — so an
  all-novel result caused by a judge failure is distinguishable from a genuine
  all-novel verdict. If the judge returned a valid map but omitted some ids,
  those carry `reason: "judge-omitted"` and their ids are listed in
  `novelty_omitted`.
  """
  @spec run(GenServer.server(), [map()], keyword()) :: map()
  def run(reference, layer0_entries, opts \\ []) do
    layer0 = Enum.reject(layer0_entries, &(value(&1, :type) == :chunk))
    id_set = MapSet.new(Enum.map(layer0, &value(&1, :id)))
    n = max(Keyword.get(opts, :synth_n, @default_synth_n), 1)

    # Sample-consensus / quorum (brushup④, e32): best-of-N pools N samples;
    # uniq_by/text collapsed duplicates but THREW AWAY the count, so a finding
    # backed by 1/N samples and one backed by N/N looked identical and a
    # contradictory pair (A→B vs A→¬B) was kept with no vote. Keep the support
    # count (how many samples produced each finding) and optionally require a
    # `:quorum` (default 1 = no filter). Order is preserved (uniq_by order) for
    # determinism; citations are unioned across the supporting samples.
    pooled =
      1..n
      |> Enum.flat_map(fn _i -> synth_sample(layer0, id_set, opts) end)
      |> Enum.reject(&(&1.text == "" or &1.citations == []))

    support = Enum.frequencies_by(pooled, & &1.text)
    citations_by_text = Enum.group_by(pooled, & &1.text, & &1.citations)

    raw =
      pooled
      |> Enum.uniq_by(& &1.text)
      |> Enum.map(fn finding ->
        finding
        |> Map.put(:support, Map.fetch!(support, finding.text))
        |> Map.put(
          :citations,
          citations_by_text |> Map.fetch!(finding.text) |> List.flatten() |> Enum.uniq()
        )
      end)
      |> apply_quorum(opts)
      |> Enum.with_index(1)
      |> Enum.map(fn {finding, i} -> Map.put(finding, :id, "synth-tmp-#{i}") end)

    # Production grounding gate, BEFORE absorb. verify keys by {citing_id,
    # cited_id}; cited entries are looked up in the store (layer-0 is present),
    # so the temp-id citing maps need not be persisted yet.
    verdicts = Reference.verify(reference, raw, verify_opts(opts))
    {gated, dropped} = apply_grounding(raw, verdicts)

    # Stance-fidelity audit (brushup④, e52), opt-in, AFTER grounding and BEFORE
    # absorb. The grounding gate only asks "is there textual support?"; this asks
    # the stricter "does the cited entry GENUINELY support the claim (relies_on),
    # or does it CONTRADICT / is it merely TANGENTIAL?" — catching refutes-masked
    # implicit relies_on and participation-based over-connection (the C5 0.50
    # natural-contamination failure surface). Drops non-supporting citations so
    # the store stays precise. Conservative: keep on judge miss (never drop
    # without positive evidence of infidelity).
    {gated, stance_dropped} = apply_stance_audit(reference, gated, opts)

    survivors =
      gated
      |> Enum.reject(&(&1.citations == []))
      |> Enum.map(&Map.take(&1, [:type, :text, :citations]))

    synth_entries = Reference.absorb(reference, survivors, Keyword.get(opts, :author, "SYNTH"))

    support_by_text = Map.new(raw, &{&1.text, &1.support})

    findings =
      Enum.map(synth_entries, fn e ->
        %{
          id: e.id,
          text: e.text,
          citations: e.citations,
          verified: true,
          support: Map.get(support_by_text, e.text, 1),
          embedding: e.embedding
        }
      end)

    # Dedup BEFORE novelty: best-of-N pools paraphrases of the same idea
    # (uniq_by/text only collapses byte-identical text). Collapsing near-dupes
    # first also means fewer novelty-judge inputs.
    {findings, dedupe_summary} = maybe_dedupe(findings, opts)
    {findings, novelty_summary} = annotate_novelty(findings, opts)

    stance_summary = if stance_dropped == [], do: %{}, else: %{stance_dropped: stance_dropped}

    Map.merge(
      %{
        findings: findings,
        synth_entry_ids: Enum.map(synth_entries, & &1.id),
        dropped_citations: dropped,
        sample_count: n
      },
      dedupe_summary |> Map.merge(novelty_summary) |> Map.merge(stance_summary)
    )
  end

  # --- semantic dedup / consensus ---
  #
  # best-of-N pools N samples; after byte-exact uniq the survivors still include
  # paraphrases of the same finding. Cluster them by embedding cosine and keep one
  # representative per cluster (the longest text), unioning the cluster's
  # citations. Opt-in (`:dedupe`, default off). ALL synth entries stay in the
  # store (synth_entry_ids is complete) so retraction governance is unchanged —
  # dedup only shapes the served `findings` view. Degrades to a no-op when
  # embeddings are absent (never merges on a missing/empty vector).

  defp maybe_dedupe(findings, opts) do
    if Keyword.get(opts, :dedupe, false) do
      threshold = Keyword.get(opts, :dedupe_threshold, 0.85)
      clusters = cluster_findings(findings, threshold)

      {Enum.map(clusters, &merge_cluster/1),
       %{dedupe_input: length(findings), dedupe_clusters: length(clusters)}}
    else
      {Enum.map(findings, &Map.delete(&1, :embedding)), %{}}
    end
  end

  defp cluster_findings(findings, threshold) do
    Enum.reduce(findings, [], fn f, clusters ->
      case Enum.find_index(clusters, fn [rep | _] -> similar?(f, rep, threshold) end) do
        nil -> clusters ++ [[f]]
        idx -> List.update_at(clusters, idx, &(&1 ++ [f]))
      end
    end)
  end

  defp similar?(a, b, threshold) do
    ea = Map.get(a, :embedding)
    eb = Map.get(b, :embedding)

    is_list(ea) and is_list(eb) and ea != [] and eb != [] and
      Tracefield.Embed.cosine(ea, eb) >= threshold
  end

  defp merge_cluster(members) do
    rep = Enum.max_by(members, &String.length(&1.text))
    citations = members |> Enum.flat_map(& &1.citations) |> Enum.uniq()
    # cluster support = total samples backing any member (semantic consensus)
    support = members |> Enum.map(&Map.get(&1, :support, 1)) |> Enum.sum()

    rep
    |> Map.put(:citations, citations)
    |> Map.put(:support, support)
    |> Map.put(:cluster_size, length(members))
    |> Map.put(:cluster_member_ids, Enum.map(members, & &1.id))
    |> Map.delete(:embedding)
  end

  # Quorum filter: keep only findings backed by >= :quorum samples (default 1 =
  # no filter). Resolves contradictory low-support findings (e32) — a 1/N claim
  # does not survive against an N/N one when quorum > 1.
  defp apply_quorum(findings, opts) do
    quorum = max(Keyword.get(opts, :quorum, 1), 1)

    if quorum <= 1 do
      findings
    else
      Enum.filter(findings, &(Map.get(&1, :support, 1) >= quorum))
    end
  end

  # --- stance-fidelity audit ---

  defp apply_stance_audit(reference, gated, opts) do
    if Keyword.get(opts, :stance_audit, false) and Enum.any?(gated, &(&1.citations != [])) do
      by_id = Map.new(Reference.all(reference), &{value(&1, :id), &1})

      pairs =
        for f <- gated, cid <- f.citations do
          %{key: {f.id, cid}, claim: f.text, cited: cited_text(by_id, cid)}
        end

      relations = judge_stance(pairs, opts)

      Enum.reduce(gated, {[], []}, fn f, {kept, dropped} ->
        {good, bad} =
          Enum.split_with(f.citations, fn cid ->
            Map.get(relations, {f.id, cid}, "supports") == "supports"
          end)

        kept = kept ++ [%{f | citations: good}]

        dropped =
          dropped ++
            Enum.map(bad, fn cid ->
              %{
                finding_text: f.text,
                cited_id: cid,
                relation: Map.get(relations, {f.id, cid}, "unknown")
              }
            end)

        {kept, dropped}
      end)
    else
      {gated, []}
    end
  end

  defp cited_text(by_id, cid) do
    case Map.get(by_id, cid) do
      nil -> ""
      entry -> to_string(value(entry, :text))
    end
  end

  defp judge_stance([], _opts), do: %{}

  defp judge_stance(pairs, opts) do
    numbered =
      pairs
      |> Enum.with_index(1)
      |> Enum.map(fn {p, i} -> %{"n" => i, "claim" => p.claim, "cited" => p.cited} end)

    content =
      case stance_complete(stance_prompt(numbered), opts) do
        {:ok, c} -> c
        _ -> ""
      end

    parse_stance(content, pairs)
  end

  defp stance_complete(prompt, opts) do
    case Keyword.get(opts, :stance_audit_complete) do
      fun when is_function(fun, 1) ->
        fun.(prompt)

      _ ->
        llm_opts =
          [
            adapter: Keyword.get(opts, :stance_adapter, Tracefield.LLM.CLI),
            model: Keyword.get(opts, :stance_model, Keyword.get(opts, :synth_model)),
            temperature: 0.0,
            timeout: 300_000
          ]
          |> maybe_put(:cli, Keyword.get(opts, :stance_cli))

        Tracefield.LLM.complete([%{role: "user", content: prompt}], llm_opts)
    end
  end

  defp stance_prompt(numbered) do
    """
    各ペアについて、CITED が CLAIM をどう支持するかを厳密に分類せよ。
    - "supports": CLAIM が CITED に実際に依拠している（genuine relies_on）
    - "contradicts": CITED は CLAIM と矛盾する
    - "tangential": CITED は CLAIM と関係が薄い（参加・近接のみで実依存でない）
    迷う場合は "supports"。Return only JSON keyed by n, like {"1":{"relation":"supports"}}.

    PAIRS:
    #{Jason.encode!(numbered)}
    """
    |> String.trim()
  end

  defp parse_stance(content, pairs) do
    case decode_object(content) do
      {:ok, %{} = decoded} ->
        pairs
        |> Enum.with_index(1)
        |> Map.new(fn {pair, i} ->
          relation =
            case Map.get(decoded, Integer.to_string(i), Map.get(decoded, i)) do
              %{} = v -> to_string(Map.get(v, "relation", "supports"))
              _ -> "supports"
            end

          {pair.key, relation}
        end)

      _ ->
        %{}
    end
  end

  # --- ensemble sampling ---

  defp synth_sample(layer0, id_set, opts) do
    prompt = synth_prompt(layer0)

    case complete(prompt, opts) do
      {:ok, content} -> parse_cited(content, id_set)
      {:error, _reason} -> []
    end
  end

  defp complete(prompt, opts) do
    case Keyword.get(opts, :synth_complete) do
      fun when is_function(fun, 1) ->
        fun.(prompt)

      _ ->
        synth_model = Keyword.fetch!(opts, :synth_model)

        Tracefield.LLM.complete([%{role: "user", content: prompt}],
          adapter: Tracefield.LLM.CLI,
          cli: {"cursor-agent", ["-p", "--output-format", "text", "--model", synth_model]},
          timeout: 300_000
        )
    end
  end

  defp synth_prompt(layer0) do
    """
    あなたは半溶解チームの統合器(synthesizer)である。以下は各員が外部化した懸念・事実
    （各行 [id] 付き）。領域をまたぐ矛盾・相互作用・依存をすべて見つけ、各々について
    それを構成する事実を統合した1つの belief を簡潔に書き、その矛盾/相互作用を構成した
    entry の [id] を citations に必ず列挙せよ。引用は実際に依拠した entry だけに限れ。
    Return only JSON {"entries":[{"type":"belief","text":"...","citations":["e3","e7"]}]}.

    ENTRIES:
    #{layer0 |> Enum.map_join("\n", fn e -> "[#{value(e, :id)}] #{value(e, :text)}" end)}
    """
    |> String.trim()
  end

  defp parse_cited(content, id_set) do
    case decode_object(content) do
      {:ok, %{} = decoded} ->
        decoded
        |> Map.get("entries", [])
        |> List.wrap()
        |> Enum.filter(&is_map/1)
        |> Enum.map(fn e ->
          %{
            type: :belief,
            text: to_string(Map.get(e, "text", "")),
            citations:
              e
              |> Map.get("citations", [])
              |> List.wrap()
              |> Enum.map(&to_string/1)
              |> Enum.filter(&MapSet.member?(id_set, &1))
              |> Enum.uniq()
          }
        end)

      _ ->
        []
    end
  end

  defp decode_object(content) do
    case Jason.decode(content) do
      {:ok, obj} ->
        {:ok, obj}

      {:error, _} ->
        with {s, _} <- :binary.match(content, "{"),
             {r, _} <- content |> String.reverse() |> :binary.match("}"),
             e = byte_size(content) - r - 1,
             true <- e >= s do
          Jason.decode(binary_part(content, s, e - s + 1))
        else
          _ -> {:error, :no_json}
        end
    end
  end

  # --- novelty gate ---
  #
  # The grounding gate only asks "does the cited entry support this finding?".
  # It does NOT ask "is this finding already true / already shipped in the target
  # system?". So a confident synthesizer can re-propose work that is already done
  # (its citations still ground). The novelty gate runs AFTER grounding: it judges
  # each surviving finding against a ground-truth corpus (current code, CHANGELOG,
  # docs) and partitions findings into novel vs. already-shipped. Opt-in
  # (`:novelty_check`) so experiments/tests are unaffected when off. Conservative:
  # on any parse/judge failure a finding stays `novel` (we never silently drop a
  # real finding).

  defp annotate_novelty(findings, opts) do
    ground_truth = Keyword.get(opts, :ground_truth)

    if Keyword.get(opts, :novelty_check, false) and is_binary(ground_truth) and
         ground_truth != "" and findings != [] do
      case judge_novelty(findings, ground_truth, opts) do
        {:ok, verdicts} ->
          # Some ids may be missing from an otherwise-valid verdict map (the judge
          # silently omitted them). Mark those distinctly so "novel because judged
          # novel" is never confused with "novel because the judge skipped it".
          {annotated, omitted} =
            Enum.map_reduce(findings, [], fn f, omitted ->
              case Map.fetch(verdicts, f.id) do
                {:ok, v} ->
                  {Map.put(f, :novelty, v), omitted}

                :error ->
                  {Map.put(f, :novelty, %{shipped: false, reason: "judge-omitted"}),
                   [f.id | omitted]}
              end
            end)

          {novel, shipped} = Enum.split_with(annotated, &(not &1.novelty.shipped))

          summary =
            %{
              novelty_checked: true,
              novel_findings: Enum.map(novel, & &1.id),
              shipped_findings: Enum.map(shipped, & &1.id)
            }
            |> maybe_put_summary(:novelty_omitted, Enum.reverse(omitted))

          {annotated, summary}

        {:error, reason} ->
          # The judge call/parse failed wholesale. Keep every finding (conservative)
          # but flag it so the caller can tell this is NOT a real all-novel verdict.
          annotated =
            Enum.map(
              findings,
              &Map.put(&1, :novelty, %{shipped: false, reason: "judge-unparsed"})
            )

          {annotated,
           %{
             novelty_checked: true,
             novel_findings: Enum.map(annotated, & &1.id),
             shipped_findings: [],
             novelty_error: reason
           }}
      end
    else
      {findings, %{}}
    end
  end

  defp maybe_put_summary(summary, _key, []), do: summary
  defp maybe_put_summary(summary, key, value), do: Map.put(summary, key, value)

  defp judge_novelty(findings, ground_truth, opts) do
    numbered = Enum.map(findings, &%{"id" => &1.id, "text" => &1.text})
    prompt = novelty_prompt(ground_truth, numbered)

    with {:ok, content} <- novelty_complete(prompt, opts),
         true <- is_binary(content) and content != "",
         {:ok, %{} = decoded} <- decode_object(content) do
      {:ok, parse_verdicts(decoded)}
    else
      false -> {:error, :empty}
      {:error, _} = err -> err
      _ -> {:error, :unparsed}
    end
  end

  defp novelty_complete(prompt, opts) do
    case Keyword.get(opts, :novelty_complete) do
      fun when is_function(fun, 1) ->
        fun.(prompt)

      _ ->
        llm_opts =
          [
            adapter: Keyword.get(opts, :novelty_adapter, Tracefield.LLM.CLI),
            model: Keyword.get(opts, :novelty_model, Keyword.get(opts, :synth_model)),
            temperature: 0.0,
            timeout: 300_000
          ]
          |> maybe_put(:cli, Keyword.get(opts, :novelty_cli))

        Tracefield.LLM.complete([%{role: "user", content: prompt}], llm_opts)
    end
  end

  defp novelty_prompt(ground_truth, numbered) do
    """
    あなたは厳格なレビュアである。GROUND_TRUTH は対象システムの現状（コード/変更履歴/設計）である。
    以下の各 FINDING（改善提案）について、GROUND_TRUTH を根拠に「既に実装済・対応済か(shipped)」を判定せよ。
    提案の主張する変更や機能が GROUND_TRUTH に既に存在する／既に対応されている場合のみ shipped=true。
    現状に無く未対応なら shipped=false。判断に迷う場合は shipped=false（新規扱い）にせよ。
    Return only JSON keyed by finding id, like {"e14":{"shipped":true,"reason":"..."}}.

    GROUND_TRUTH:
    #{ground_truth}

    FINDINGS:
    #{Jason.encode!(numbered)}
    """
    |> String.trim()
  end

  defp parse_verdicts(decoded) do
    decoded
    |> Enum.flat_map(fn
      {id, %{} = v} when is_binary(id) ->
        [
          {id,
           %{
             shipped: truthy(Map.get(v, "shipped")),
             reason: to_string(Map.get(v, "reason", ""))
           }}
        ]

      _ ->
        []
    end)
    |> Map.new()
  end

  defp truthy(true), do: true
  defp truthy("true"), do: true
  defp truthy(_), do: false

  # --- grounding gate ---

  defp apply_grounding(raw, verdicts) do
    Enum.reduce(raw, {[], []}, fn finding, {kept, dropped} ->
      {good, bad} =
        Enum.split_with(finding.citations, fn cid ->
          Map.get(verdicts, {finding.id, cid}, false)
        end)

      kept = kept ++ [%{finding | citations: good}]
      dropped = dropped ++ Enum.map(bad, &%{finding_text: finding.text, cited_id: &1})
      {kept, dropped}
    end)
  end

  defp verify_opts(opts) do
    [
      judge_adapter: Keyword.get(opts, :verify_adapter, Tracefield.LLM.Mock),
      judge_model: Keyword.get(opts, :verify_model, "mock")
    ]
    |> maybe_put(:cli, Keyword.get(opts, :verify_cli))
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)

  defp value(entry, key), do: Map.get(entry, key, Map.get(entry, to_string(key)))
end
