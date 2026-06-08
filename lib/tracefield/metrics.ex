defmodule Tracefield.Metrics do
  @moduledoc """
  Small statistical helpers for Phase 0/1.
  """

  def auc(within, between) do
    pair_scores(within, between)
    |> mean_score()
  end

  def cliffs_delta(within, between) do
    scores = pair_scores(within, between)

    if scores == [] do
      0.0
    else
      total = length(scores)
      wins = Enum.count(scores, &(&1 == 1.0))
      losses = Enum.count(scores, &(&1 == 0.0))
      (wins - losses) / total
    end
  end

  def summary(samples) do
    sorted = Enum.sort(samples)
    n = length(sorted)

    %{
      n: n,
      mean: mean(sorted),
      sd: sd(sorted),
      median: median(sorted)
    }
  end

  def prf(ground_truth_set, system_set) do
    ground_truth = MapSet.new(ground_truth_set)
    system = MapSet.new(system_set)
    true_positive = MapSet.intersection(ground_truth, system) |> MapSet.size()

    precision = ratio(true_positive, MapSet.size(system))
    recall = ratio(true_positive, MapSet.size(ground_truth))

    f1 =
      if precision + recall == 0.0, do: 0.0, else: 2.0 * precision * recall / (precision + recall)

    %{precision: precision, recall: recall, f1: f1}
  end

  defp pair_scores([], _between), do: []
  defp pair_scores(_within, []), do: []

  defp pair_scores(within, between) do
    for w <- within, b <- between do
      cond do
        b > w -> 1.0
        b == w -> 0.5
        true -> 0.0
      end
    end
  end

  defp mean_score([]), do: 0.0
  defp mean_score(scores), do: Enum.sum(scores) / length(scores)

  defp mean([]), do: 0.0
  defp mean(samples), do: Enum.sum(samples) / length(samples)

  defp sd(samples) when length(samples) < 2, do: 0.0

  defp sd(samples) do
    average = mean(samples)
    variance = Enum.sum(Enum.map(samples, &:math.pow(&1 - average, 2))) / (length(samples) - 1)
    :math.sqrt(variance)
  end

  defp median([]), do: 0.0

  defp median(samples) do
    n = length(samples)
    mid = div(n, 2)

    if rem(n, 2) == 1 do
      Enum.at(samples, mid)
    else
      (Enum.at(samples, mid - 1) + Enum.at(samples, mid)) / 2.0
    end
  end

  defp ratio(_numerator, 0), do: 0.0
  defp ratio(numerator, denominator), do: numerator / denominator
end
