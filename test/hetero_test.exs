defmodule Tracefield.HeteroTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Hetero

  defmodule PromptCaptureMock do
    @behaviour Tracefield.LLM

    @impl true
    def complete(messages, opts) do
      prompt = Enum.map_join(messages, "\n", &Map.get(&1, :content, Map.get(&1, "content", "")))

      if String.contains?(prompt, "TRACEFIELD_AGENT_TURN") do
        case :persistent_term.get({__MODULE__, :owner}, nil) do
          nil -> :ok
          owner -> send(owner, {__MODULE__, :prompt, prompt})
        end
      end

      Tracefield.LLM.Mock.complete(messages, opts)
    end
  end

  test "parse_heteros accepts known levels and rejects invalid levels" do
    assert Hetero.parse_heteros("grounded,homogeneous") == [:grounded, :homogeneous]

    assert_raise Mix.Error, ~r/invalid hetero value "synthetic"/, fn ->
      Hetero.parse_heteros("grounded,synthetic")
    end
  end

  test "mock e2e discovers private-document interactions only when procedure is adopted" do
    result =
      Hetero.run_experiment(
        adapter_name: "mock-test",
        adapter: Tracefield.LLM.Mock,
        seeds: 1,
        rounds: 2,
        ks: [2],
        kps: [0, 1],
        model: "mock",
        judge_model: "mock",
        embed_model: "nomic-embed-text",
        temperature: 0.4
      )

    by_kp = Map.new(result.runs, &{&1.kp, &1})

    assert by_kp[0].disc_strict == 0
    assert by_kp[1].disc_strict > by_kp[0].disc_strict
    assert is_integer(by_kp[1].icc)
    assert is_integer(by_kp[1].coverage)
    assert is_float(by_kp[1].diversity)
    assert is_float(by_kp[1].collapse_rate)
    assert [_ | _] = by_kp[1].perception
  end

  test "mock e2e covers serve by aware grid cells" do
    result =
      Hetero.run_experiment(
        adapter_name: "mock-test",
        adapter: Tracefield.LLM.Mock,
        seeds: 1,
        rounds: 2,
        ks: [2],
        kps: [1],
        serves: [:similar, :diverse],
        awares: [0, 1],
        model: "mock",
        judge_model: "mock",
        embed_model: "nomic-embed-text",
        temperature: 0.4
      )

    cells = MapSet.new(Enum.map(result.runs, &{&1.k, &1.kp, &1.serve, &1.aware, &1.hetero}))

    assert cells ==
             MapSet.new([
               {2, 1, :similar, 0, :grounded},
               {2, 1, :similar, 1, :grounded},
               {2, 1, :diverse, 0, :grounded},
               {2, 1, :diverse, 1, :grounded}
             ])

    assert length(result.runs) == 4
    assert length(result.summary) == 4
    assert Map.has_key?(result.disc_strict_serve_trend, {2, 1, 0, :grounded})
    assert Map.has_key?(result.disc_strict_aware_trend, {2, 1, :similar})
  end

  test "homogeneous agents receive identical joined private docs while grounded agents differ" do
    grounded_docs = %{
      "SEC" => "SEC private retention-90d",
      "BIZ" => "BIZ private delete-72h",
      "UX" => "UX private upsell-q3"
    }

    grounded_prompt_docs =
      run_and_capture_prompt_docs(
        private_docs: grounded_docs,
        heteros: [:grounded]
      )

    homogeneous_prompt_docs =
      run_and_capture_prompt_docs(
        private_docs: grounded_docs,
        heteros: [:homogeneous]
      )

    joined_doc = grounded_docs |> Map.values() |> Enum.join("\n\n")

    assert grounded_prompt_docs == grounded_docs
    assert homogeneous_prompt_docs == Map.new(Map.keys(grounded_docs), &{&1, joined_doc})
    assert grounded_prompt_docs |> Map.values() |> Enum.uniq() |> length() == 3
    assert homogeneous_prompt_docs |> Map.values() |> Enum.uniq() == [joined_doc]
  end

  test "sweep covers serve by hetero cells and summaries include hetero" do
    result =
      Hetero.run_experiment(
        adapter_name: "mock-test",
        adapter: Tracefield.LLM.Mock,
        seeds: 1,
        rounds: 2,
        ks: [2],
        kps: [1],
        serves: [:diverse, :contrastive],
        awares: [1],
        heteros: [:grounded, :homogeneous],
        model: "mock",
        judge_model: "mock",
        embed_model: "nomic-embed-text",
        temperature: 0.4
      )

    cells = MapSet.new(Enum.map(result.runs, &{&1.k, &1.kp, &1.serve, &1.aware, &1.hetero}))

    summary_cells =
      MapSet.new(Enum.map(result.summary, &{&1.k, &1.kp, &1.serve, &1.aware, &1.hetero}))

    expected =
      MapSet.new([
        {2, 1, :diverse, 1, :grounded},
        {2, 1, :contrastive, 1, :grounded},
        {2, 1, :diverse, 1, :homogeneous},
        {2, 1, :contrastive, 1, :homogeneous}
      ])

    assert cells == expected
    assert summary_cells == expected
    assert length(result.runs) == 4
    assert length(result.summary) == 4
    assert Map.has_key?(result.disc_strict_serve_trend, {2, 1, 1, :grounded})
    assert Map.has_key?(result.disc_strict_serve_trend, {2, 1, 1, :homogeneous})
  end

  test "omitting hetero keeps grounded-only cell count" do
    result =
      Hetero.run_experiment(
        adapter_name: "mock-test",
        adapter: Tracefield.LLM.Mock,
        seeds: 1,
        rounds: 2,
        ks: [2],
        kps: [1],
        serves: [:diverse, :contrastive],
        awares: [1],
        model: "mock",
        judge_model: "mock",
        embed_model: "nomic-embed-text",
        temperature: 0.4
      )

    assert length(result.runs) == 2
    assert length(result.summary) == 2
    assert Enum.all?(result.runs, &(&1.hetero == :grounded))
    assert Enum.all?(result.summary, &(&1.hetero == :grounded))
    assert Map.keys(result.disc_strict_serve_trend) == [{2, 1, 1, :grounded}]
  end

  defp run_and_capture_prompt_docs(opts) do
    :persistent_term.put({PromptCaptureMock, :owner}, self())

    try do
      Hetero.run_experiment(
        [
          adapter_name: "prompt-capture",
          adapter: PromptCaptureMock,
          seeds: 1,
          rounds: 1,
          ks: [0],
          kps: [0],
          serves: [:similar],
          awares: [0],
          model: "mock",
          judge_model: "mock",
          embed_model: "nomic-embed-text",
          temperature: 0.4
        ] ++ opts
      )

      3
      |> collect_prompts([])
      |> prompt_private_docs()
    after
      :persistent_term.erase({PromptCaptureMock, :owner})
    end
  end

  defp collect_prompts(0, prompts), do: prompts

  defp collect_prompts(count, prompts) do
    receive do
      {PromptCaptureMock, :prompt, prompt} -> collect_prompts(count - 1, [prompt | prompts])
    after
      1_000 -> flunk("expected #{count} more captured prompts")
    end
  end

  defp prompt_private_docs(prompts) do
    Map.new(prompts, fn prompt ->
      captures =
        Regex.named_captures(
          ~r/AGENT (?<agent>\S+)[\s\S]*?PRIVATE DOCUMENT \(yours only\):\n(?<doc>[\s\S]*?)(?:\n\nPRIVATE MEMORY|\n\nPRESENTED ENTRIES:)/,
          prompt
        )

      {captures["agent"], String.trim(captures["doc"])}
    end)
  end
end
