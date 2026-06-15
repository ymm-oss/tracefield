defmodule Tracefield.CitationPrecision do
  @moduledoc """
  H4: scores contamination-tracking precision under citation-provenance rules.

  Given a suspect/retracted chunk, computes the "affected" set — the claims that
  would be quarantined as depending on it — under three progressively stricter
  rules, to quantify how much citation grounding (stance + verification) reduces
  over-isolation:

    * `:cited_anything`     — any claim citing the chunk (any stance)
    * `:relies_on`          — claims citing it with stance "relies_on"
    * `:relies_on_verified` — relies_on AND the citation is grounded (Reference.verify)

  Reproduces the `experiment-results.md` §7 precision ladder on the live harness.
  Stance is read from `entry.meta.citation_stances` (absent ⇒ relies_on default),
  so flat-citation entries are treated as relies_on — matching the §6f baseline.
  """

  alias Tracefield.Reference

  @rules [:cited_anything, :relies_on, :relies_on_verified]

  def rules, do: @rules

  @doc "Set of entry ids that directly cite `chunk_id` under `rule`."
  def affected(ref, chunk_id, rule, opts \\ []) when rule in @rules do
    entries = Reference.all(ref)
    citers = Enum.filter(entries, &(chunk_id in citation_ids(&1)))

    verified =
      if rule == :relies_on_verified do
        relies = Enum.filter(citers, &(stance_for(&1, chunk_id) == "relies_on"))
        Reference.verify(ref, relies, opts)
      else
        %{}
      end

    citers
    |> Enum.filter(&keep?(&1, chunk_id, rule, verified))
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  @doc "precision/recall of an affected set against the genuine-adopter ground truth."
  def score(%MapSet{} = affected, ground_truth) do
    gt = MapSet.new(ground_truth)
    tp = MapSet.size(MapSet.intersection(affected, gt))

    %{
      affected: affected,
      precision: ratio(tp, MapSet.size(affected)),
      recall: ratio(tp, MapSet.size(gt))
    }
  end

  @doc "Runs all three rules and returns the ladder %{rule => score}."
  def ladder(ref, chunk_id, ground_truth, opts \\ []) do
    Map.new(@rules, fn rule ->
      {rule, score(affected(ref, chunk_id, rule, opts), ground_truth)}
    end)
  end

  defp keep?(_entry, _chunk, :cited_anything, _verified), do: true

  defp keep?(entry, chunk, :relies_on, _verified),
    do: stance_for(entry, chunk) == "relies_on"

  defp keep?(entry, chunk, :relies_on_verified, verified),
    do: stance_for(entry, chunk) == "relies_on" and Map.get(verified, {entry.id, chunk}, false)

  defp citation_ids(entry), do: entry |> Map.get(:citations, []) |> List.wrap()

  defp stance_for(entry, chunk_id) do
    entry
    |> Map.get(:meta, %{})
    |> Map.get(:citation_stances, %{})
    |> Map.get(chunk_id, "relies_on")
  end

  defp ratio(_tp, 0), do: 0.0
  defp ratio(tp, total), do: tp / total
end
