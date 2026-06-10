defmodule Tracefield.IdeateTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Ideate

  @scenario_path "scenarios/housing-service"

  test "loads agents.json and resolves private_doc files" do
    scenario = Ideate.load_scenario!(@scenario_path)

    assert length(scenario.agents) == 4
    assert scenario.task =~ "住宅会社"
    assert scenario.procedure =~ "アイデア生成手続き"

    Enum.each(scenario.agents, fn agent ->
      assert agent.id in ~w(KURASHI FINANCE GIJUTSU CHIIKI)
      assert File.exists?(agent.private_doc_path)
      assert agent.private_doc_file =~ ".md"
      assert agent.private_doc =~ agent.id
    end)
  end

  test "mock ideate e2e emits ideas, metrics, and cross-author synthesis" do
    result =
      Ideate.run_ideation(
        scenario: @scenario_path,
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        rounds: 2,
        serve_policy: :diverse,
        aware: 1,
        k_s: 3,
        model: "mock",
        embed_model: "nomic-embed-text",
        temperature: 0.6,
        persist?: false
      )

    authors = result.ideas |> Enum.map(& &1.author) |> MapSet.new()

    assert MapSet.subset?(MapSet.new(~w(KURASHI FINANCE GIJUTSU CHIIKI)), authors)
    assert result.metrics.coverage > 0
    assert is_float(result.metrics.diversity)
    assert is_float(result.metrics.collapse_rate)
    assert is_integer(result.cross_author_synthesis.count)
    assert result.cross_author_synthesis.count > 0
    assert result.path == nil
  end

  test "mode presets resolve defaults and explicit flags override them" do
    diverge =
      Ideate.run_ideation(
        scenario: @scenario_path,
        mode: :diverge,
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        model: "mock",
        persist?: false
      )

    assert diverge.config.mode == :diverge
    assert diverge.config.rounds == 2
    assert diverge.config.k == 1
    assert diverge.config.temperature == 0.8

    converge =
      Ideate.run_ideation(
        scenario: @scenario_path,
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        model: "mock",
        persist?: false
      )

    assert converge.config.mode == :converge
    assert converge.config.rounds == 3
    assert converge.config.k == 4
    assert converge.config.temperature == 0.5

    overridden =
      Ideate.run_ideation(
        scenario: @scenario_path,
        mode: :review,
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        rounds: 1,
        k_s: 7,
        temperature: 0.2,
        serve_policy: :similar,
        aware: 0,
        model: "mock",
        persist?: false
      )

    assert overridden.config.mode == :review
    assert overridden.config.rounds == 1
    assert overridden.config.k == 7
    assert overridden.config.temperature == 0.2
    assert overridden.config.serve == :similar
    assert overridden.config.aware == 0
  end

  test "review mode falls back to the built-in Japanese risk-review procedure" do
    scenario = Ideate.load_scenario!(@scenario_path, :review)

    assert scenario.procedure_source == :built_in_review
    assert scenario.procedure =~ "リスクレビュー手続き v1"
    assert scenario.procedure =~ "リスク・矛盾・見落とし"
  end

  test "mock correction e2e quarantines closure and records repair entries" do
    result =
      Ideate.run_ideation(
        scenario: @scenario_path,
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        rounds: 2,
        k_s: 3,
        correct: "auto",
        model: "mock",
        persist?: false
      )

    refute result.correction.skipped
    assert result.correction.target.status == :retracted
    assert result.correction.closure != []
    assert Enum.all?(result.correction.closure, &(&1.status == :superseded))
    assert length(result.correction.repair_entries) >= 1
  end

  test "report is written with headings, citation marks, health, cross-author, and correction" do
    path =
      Path.join(
        System.tmp_dir!(),
        "tracefield-ideate-report-#{System.unique_integer([:positive])}.md"
      )

    on_exit(fn -> File.rm(path) end)

    result =
      Ideate.run_ideation(
        scenario: @scenario_path,
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        rounds: 2,
        k_s: 3,
        correct: "auto",
        report: path,
        model: "mock",
        persist?: false
      )

    assert File.exists?(path)
    report = File.read!(path)

    assert result.metrics.verification_rate >= 0.0
    assert report =~ "## タスク"
    assert report =~ "## アイデア（Round 別）"
    assert report =~ "## 健全性"
    assert report =~ "## 領域横断の合成（cross-author）"
    assert report =~ "## 訂正（--correct 時のみ）"
    assert report =~ "✓"
    assert report =~ "✗"
  end
end
