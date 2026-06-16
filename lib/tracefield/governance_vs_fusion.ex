defmodule Tracefield.GovernanceVsFusion do
  @moduledoc """
  H9 head-to-head: does governable synthesis (GOV) contain a post-serving harm
  that a stateless ensemble (Fusion) cannot? See
  `docs/impl-brief-h9-governance-vs-fusion.md`.

  When a premise P that served findings depended on is later found false, which
  findings are affected?

    * **GOV** — `gov_affected/3`: the retraction closure over the citation graph
      (provenance). No strong-model call; O(closure).
    * **FUSION-posthoc** — `fusion_affected/3`: a strong model re-reads the served
      findings + the correction and judges which are affected (the C4 analog —
      reasoning, not provenance). Costs one strong-model call.

  Both are scored against a semantic ground truth (`semantic_gt/2`) — the findings
  that TRULY depend on P (planted-keyword proxy, independent of citations). This
  is what exposes GOV's two boundaries: over-connection (a finding cited P but
  does not really depend → precision hit) and the M5 hole (a finding depends but
  never cited P → recall hit). It mirrors the program's C5-vs-C4 result
  (in-process provenance recall 1.0 vs post-hoc 0.5) at the serving layer.
  """

  alias Tracefield.Reference

  @doc """
  GOV containment: served findings (entries authored `:synth_author`, default
  `"SYNTH"`) affected by retracting `premise_id`. Pure / read-only.

  `:mode`:
    * `:reachable` (default) — the full transitive retraction closure
      (`Reference.closure/2`). High recall, but FLOODS when the premise is
      central (every finding transitively cites it → precision collapses; H9 F1).
    * `:direct` — only findings that cite `premise_id` directly. A stance-free
      precision lever: a finding two hops away (cites a layer-0 concern that
      cites P) is not counted. (A stance/typed-weighted closure that propagates
      only `relies_on` edges and stops at `refutes` would be stronger, but needs
      stances recorded on prose citations — the #3 remainder.)
  """
  def gov_affected(entries, premise_id, opts \\ []) do
    author = Keyword.get(opts, :synth_author, "SYNTH")
    pid = to_string(premise_id)

    case Keyword.get(opts, :mode, :reachable) do
      :direct ->
        entries
        |> Enum.filter(fn e ->
          field(e, :author) == author and pid in (field(e, :citations) || [])
        end)
        |> Enum.map(&field(&1, :id))

      _ ->
        entries
        |> Reference.closure(pid)
        |> Enum.filter(&(field(&1, :author) == author))
        |> Enum.map(&field(&1, :id))
    end
  end

  @doc """
  Semantic ground truth (H9 F2): for each finding, judge — given the premise is
  now FALSE — whether it is `"invalidated"` (depended on the premise being true,
  now breaks), `"reinforced"` (argued AGAINST the premise, now stronger), or
  `"unrelated"`. Returns `%{id => label}`. Containment should target only the
  `invalidated` set (see `invalidated/1`). Replaces the keyword proxy, which
  conflated "mentions the premise" with "invalidated if false". `:label_complete`
  (`fun(prompt) -> {:ok, content}`) is the test seam; else cursor-agent CLI.
  """
  def semantic_labels(findings, premise, correction, opts \\ []) do
    numbered = Enum.map(findings, &%{"id" => field(&1, :id), "text" => field(&1, :text)})

    content =
      case label_complete(label_prompt(premise, correction, numbered), opts) do
        {:ok, c} -> c
        _ -> ""
      end

    parse_labels(content)
  end

  @doc "Ids labeled `\"invalidated\"` in a `semantic_labels/4` result."
  def invalidated(labels) do
    for {id, "invalidated"} <- labels, do: id
  end

  @doc """
  FUSION-posthoc containment: a strong model re-reads `findings`
  (`[%{id, text}]`) plus the `correction` (P is now false) and returns the ids it
  judges affected. `:posthoc_complete` (`fun(prompt) -> {:ok, content}`) is the
  test seam; otherwise a cursor-agent CLI call with `:posthoc_model`/`:posthoc_cli`.
  """
  def fusion_affected(findings, correction, opts \\ []) do
    numbered = Enum.map(findings, &%{"id" => field(&1, :id), "text" => field(&1, :text)})

    content =
      case posthoc_complete(posthoc_prompt(correction, numbered), opts) do
        {:ok, c} -> c
        _ -> ""
      end

    valid_ids = MapSet.new(numbered, & &1["id"])
    parse_affected(content) |> Enum.filter(&MapSet.member?(valid_ids, &1))
  end

  @doc """
  Semantic ground truth: findings whose text contains any of `keywords` — the
  TRUE dependency on P, independent of whether the citation was recorded.
  """
  def semantic_gt(findings, keywords) do
    kw = Enum.map(keywords, &String.downcase/1)

    findings
    |> Enum.filter(fn f ->
      text = String.downcase(field(f, :text) || "")
      Enum.any?(kw, &String.contains?(text, &1))
    end)
    |> Enum.map(&field(&1, :id))
  end

  @doc "Containment recall/precision of `predicted` ids against `gt` ids."
  def score(predicted, gt) do
    p = MapSet.new(predicted)
    g = MapSet.new(gt)
    tp = MapSet.size(MapSet.intersection(p, g))

    %{
      recall: ratio(tp, MapSet.size(g)),
      precision: ratio(tp, MapSet.size(p)),
      true_positive: tp,
      predicted: MapSet.size(p),
      ground_truth: MapSet.size(g)
    }
  end

  # --- internals ---

  defp ratio(_tp, 0), do: 1.0
  defp ratio(tp, n), do: tp / n

  defp posthoc_complete(prompt, opts) do
    case Keyword.get(opts, :posthoc_complete) do
      fun when is_function(fun, 1) ->
        fun.(prompt)

      _ ->
        model = Keyword.get(opts, :posthoc_model, "claude-opus-4-8-medium")

        llm_opts =
          [
            adapter: Keyword.get(opts, :posthoc_adapter, Tracefield.LLM.CLI),
            model: model,
            temperature: 0.0,
            timeout: 300_000,
            cli:
              Keyword.get(
                opts,
                :posthoc_cli,
                {"cursor-agent", ["-p", "--output-format", "text", "--model", model]}
              )
          ]

        Tracefield.LLM.complete([%{role: "user", content: prompt}], llm_opts)
    end
  end

  defp label_complete(prompt, opts) do
    case Keyword.get(opts, :label_complete) do
      fun when is_function(fun, 1) ->
        fun.(prompt)

      _ ->
        model =
          Keyword.get(
            opts,
            :label_model,
            Keyword.get(opts, :posthoc_model, "claude-opus-4-8-medium")
          )

        Tracefield.LLM.complete([%{role: "user", content: prompt}],
          adapter: Tracefield.LLM.CLI,
          model: model,
          temperature: 0.0,
          timeout: 300_000,
          cli:
            Keyword.get(
              opts,
              :label_cli,
              {"cursor-agent", ["-p", "--output-format", "text", "--model", model]}
            )
        )
    end
  end

  defp label_prompt(premise, correction, numbered) do
    """
    前提 P は偽と判明した。各 FINDING について、P が偽になったときの帰結を分類せよ。
    - "invalidated": P が真であることに依拠しており、P が偽なら成り立たなくなる。
    - "reinforced": P への依存を批判・否定しており、P が偽ならむしろ補強される。
    - "unrelated": P の真偽と無関係。
    Return only JSON keyed by finding id, like {"e15":{"label":"invalidated"}}.

    PREMISE P: #{premise}
    CORRECTION: #{correction}

    FINDINGS:
    #{Jason.encode!(numbered)}
    """
    |> String.trim()
  end

  defp parse_labels(content) do
    case decode_object(content) do
      {:ok, %{} = decoded} ->
        for {id, %{} = v} <- decoded, is_binary(id), into: %{} do
          {id, to_string(Map.get(v, "label", "unrelated"))}
        end

      _ ->
        %{}
    end
  end

  defp posthoc_prompt(correction, numbered) do
    """
    以下の CORRECTION により、ある前提が偽と判明した。FINDINGS のうち、その前提に
    実際に依拠していて影響を受けるものの id をすべて挙げよ（来歴は使わず、本文から判断せよ）。
    Return only JSON like {"affected":["e7","e9"]}.

    CORRECTION:
    #{correction}

    FINDINGS:
    #{Jason.encode!(numbered)}
    """
    |> String.trim()
  end

  defp parse_affected(content) do
    case decode_object(content) do
      {:ok, %{"affected" => ids}} when is_list(ids) -> Enum.map(ids, &to_string/1)
      _ -> []
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

  defp field(entry, key), do: Map.get(entry, key, Map.get(entry, to_string(key)))
end
