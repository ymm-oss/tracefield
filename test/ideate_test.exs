defmodule Tracefield.IdeateTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Ideate

  @scenario_path "scenarios/housing-service"

  defmodule PromptCaptureMock do
    @behaviour Tracefield.LLM

    @impl true
    def complete(messages, opts) do
      prompt = Enum.map_join(messages, "\n", &Map.get(&1, :content, Map.get(&1, "content", "")))

      if pid = Process.whereis(__MODULE__) do
        send(pid, {:ideate_prompt, agent_id(prompt), Keyword.get(opts, :model), prompt})
      end

      {:ok,
       Jason.encode!(%{
         entries: [
           %{
             type: "belief",
             text: "#{agent_id(prompt)} generated round #{prompt_round(prompt)}",
             citations: []
           }
         ]
       })}
    end

    defp agent_id(prompt) do
      case Regex.named_captures(~r/AGENT\s+(?<agent>[A-Z0-9_-]+)/, prompt) do
        %{"agent" => agent} -> agent
        _ -> "UNKNOWN"
      end
    end

    defp prompt_round(prompt) do
      case Regex.named_captures(~r/ROUND\s+(?<round>\d+)/, prompt) do
        %{"round" => round} -> round
        _ -> "0"
      end
    end
  end

  defmodule DocCitationPromptMock do
    @behaviour Tracefield.LLM

    @impl true
    def complete(messages, _opts) do
      prompt = Enum.map_join(messages, "\n", &Map.get(&1, :content, Map.get(&1, "content", "")))
      doc_id = first_doc_id(prompt)

      if pid = Process.whereis(__MODULE__) do
        send(pid, {:doc_prompt, prompt, doc_id})
      end

      {:ok,
       Jason.encode!(%{
         entries: [
           %{
             type: "belief",
             text: "doc-grounded decision",
             citations: List.wrap(doc_id)
           }
         ]
       })}
    end

    defp first_doc_id(prompt) do
      case Regex.run(~r/^DOC\s+(?<id>e\d+)\s+file=/m, prompt, capture: :all_names) do
        [id] -> id
        _ -> nil
      end
    end
  end

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
        memory: false,
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
        memory: false,
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
        memory: false,
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
        memory: false,
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
        memory: false,
        persist?: false
      )

    refute result.correction.skipped
    assert result.correction.target.status == :retracted
    assert result.correction.closure != []
    assert Enum.all?(result.correction.closure, &(&1.status == :superseded))
    assert length(result.correction.repair_entries) >= 1
  end

  test "tracefield-dev docs seed chunk entries and render as citable reference documents" do
    Process.register(self(), DocCitationPromptMock)

    result =
      Ideate.run_ideation(
        scenario: "scenarios/tracefield-dev",
        adapter_name: "mock",
        adapter_module: DocCitationPromptMock,
        rounds: 1,
        model: "mock",
        memory: false,
        persist?: false
      )

    doc_chunks = Enum.filter(result.entries, &(&1.type == :chunk and &1.author == "DOCS"))
    assert length(doc_chunks) == 6
    assert Enum.all?(doc_chunks, &(get_in(&1.meta, [:file]) =~ ".md"))

    assert_receive {:doc_prompt, prompt, doc_id}, 1_000
    assert prompt =~ "TASK:\n"
    assert prompt =~ "REFERENCE DOCUMENTS（設計判断はここを引用せよ）:"
    assert prompt =~ "DOC #{doc_id} file="

    assert Enum.any?(result.ideas, fn idea -> doc_id in idea.citations end)
  end

  test "chunk correction resolves docs file, retracts it, quarantines closure, and repairs" do
    result =
      Ideate.run_ideation(
        scenario: "scenarios/tracefield-dev",
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        rounds: 2,
        k_s: 3,
        correct: "chunk:r3-local-only.md",
        model: "mock",
        memory: false,
        persist?: false
      )

    refute result.correction.skipped
    assert result.correction.target.status == :retracted
    assert result.correction.target.type == :chunk
    assert get_in(result.correction.target.meta, [:file]) == "r3-local-only.md"
    assert result.correction.closure != []
    assert Enum.all?(result.correction.closure, &(&1.status == :superseded))
    assert length(result.correction.repair_entries) >= 1
    assert result.correction.note =~ "要件 r3-local-only.md が変更され撤回された"
  end

  test "procedure correction resolves the agent procedure and quarantines self-procedure decisions" do
    result =
      Ideate.run_ideation(
        scenario: "scenarios/tracefield-dev",
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        rounds: 1,
        correct: "procedure:ARCH",
        model: "mock",
        memory: false,
        persist?: false
      )

    refute result.correction.skipped
    assert result.correction.target.status == :retracted
    assert result.correction.target.type == :procedure
    assert get_in(result.correction.target.meta, [:owner]) == "ARCH"
    assert Enum.any?(result.correction.closure, &(&1.author == "ARCH"))
    assert result.correction.note =~ "ARCH の手続きに欠陥が見つかり撤回された"
  end

  test "cli adapter absorbs entries from a temp script during ideation" do
    script =
      cli_script("""
      #!/bin/sh
      echo '{"entries":[{"type":"belief","text":"cli generated decision(security)","citations":[]}]}'
      """)

    result =
      Ideate.run_ideation(
        scenario: tmp_scenario(),
        adapter_name: "cli",
        adapter_module: Tracefield.LLM.CLI,
        cli: {script, []},
        rounds: 1,
        model: "mock",
        memory: false,
        persist?: false
      )

    assert Enum.any?(result.ideas, &(&1.text == "cli generated decision(security)"))
  end

  test "cli adapter non-zero exit becomes an empty agent turn" do
    script =
      cli_script("""
      #!/bin/sh
      echo 'failed cli'
      exit 7
      """)

    assert {:error, {:cli_error, 7, "failed cli" <> _}} =
             Tracefield.LLM.CLI.complete([%{role: "user", content: "prompt"}], cli: {script, []})

    {:ok, ref} = Tracefield.Reference.start_link()

    agent =
      Tracefield.Agent.new("A", "alpha", "alpha agent",
        adapter: Tracefield.LLM.CLI,
        cli: {script, []}
      )

    {_agent, absorbed, _perception} = Tracefield.Agent.run_turn(agent, ref, 1)
    assert absorbed == []
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
        memory: false,
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

  test "agents.json resolves per-agent model and procedure entries" do
    Process.register(self(), PromptCaptureMock)
    scenario_path = tmp_scenario()

    result =
      Ideate.run_ideation(
        scenario: scenario_path,
        adapter_name: "mock",
        adapter_module: PromptCaptureMock,
        rounds: 1,
        model: "fallback-model",
        memory: false,
        persist?: false
      )

    assert_receive {:ideate_prompt, "A", "model-a", _prompt}
    assert_receive {:ideate_prompt, "B", "fallback-model", _prompt}

    a_config = Enum.find(result.config.agents, &(&1.id == "A"))
    b_config = Enum.find(result.config.agents, &(&1.id == "B"))

    assert a_config.model == "model-a"
    assert a_config.procedure_source == "procedure-a.md"
    assert b_config.model == "fallback-model"
    assert b_config.procedure_source == "shared"

    procedure_entries = Enum.filter(result.entries, &(&1.type == :procedure))
    assert length(procedure_entries) == 2

    own_procedure = Enum.find(procedure_entries, &(get_in(&1.meta, [:owner]) == "A"))
    shared_procedure = Enum.find(procedure_entries, &(get_in(&1.meta, [:domain]) == "procedure"))
    assert own_procedure.id == a_config.procedure_id
    assert shared_procedure.id == b_config.procedure_id

    a_idea = Enum.find(result.ideas, &(&1.author == "A"))
    b_idea = Enum.find(result.ideas, &(&1.author == "B"))
    assert own_procedure.id in a_idea.citations
    assert shared_procedure.id in b_idea.citations
    refute shared_procedure.id in a_idea.citations
  end

  test "memory round-trips own entries only through private prompt state" do
    Process.register(self(), PromptCaptureMock)
    scenario_path = tmp_scenario()

    memory_dir =
      Path.join(System.tmp_dir!(), "tracefield-memory-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(memory_dir) end)

    Ideate.run_ideation(
      scenario: scenario_path,
      adapter_name: "mock",
      adapter_module: PromptCaptureMock,
      rounds: 1,
      model: "mock",
      memory: true,
      memory_dir: memory_dir,
      persist?: false
    )

    drain_ideate_prompts()

    a_memory = File.read!(Path.join(memory_dir, "A.jsonl"))
    b_memory = File.read!(Path.join(memory_dir, "B.jsonl"))
    assert a_memory =~ "A generated round 1"
    refute a_memory =~ "B generated round 1"
    assert b_memory =~ "B generated round 1"
    refute b_memory =~ "A generated round 1"

    Ideate.run_ideation(
      scenario: scenario_path,
      adapter_name: "mock",
      adapter_module: PromptCaptureMock,
      rounds: 1,
      model: "mock",
      memory: true,
      memory_dir: memory_dir,
      persist?: false
    )

    assert_receive {:ideate_prompt, "A", "model-a", a_prompt}, 1_000
    assert_receive {:ideate_prompt, "B", "mock", b_prompt}, 1_000

    assert a_prompt =~ "PRIVATE DOCUMENT (yours only):"
    assert a_prompt =~ "PRIVATE MEMORY (あなた自身の過去の判断。経験として活かせ):"
    assert a_prompt =~ "- A generated round 1"
    refute a_prompt =~ "- B generated round 1"
    assert b_prompt =~ "- B generated round 1"
    refute b_prompt =~ "- A generated round 1"
  end

  test "memory false neither reads nor writes memory files" do
    Process.register(self(), PromptCaptureMock)
    scenario_path = tmp_scenario()

    memory_dir =
      Path.join(System.tmp_dir!(), "tracefield-memory-off-#{System.unique_integer([:positive])}")

    File.mkdir_p!(memory_dir)
    a_path = Path.join(memory_dir, "A.jsonl")
    File.write!(a_path, memory_line("old injected memory"))
    on_exit(fn -> File.rm_rf(memory_dir) end)

    Ideate.run_ideation(
      scenario: scenario_path,
      adapter_name: "mock",
      adapter_module: PromptCaptureMock,
      rounds: 1,
      model: "mock",
      memory: false,
      memory_dir: memory_dir,
      persist?: false
    )

    assert_receive {:ideate_prompt, "A", "model-a", a_prompt}
    refute a_prompt =~ "old injected memory"
    assert File.read!(a_path) == memory_line("old injected memory")
    refute File.exists?(Path.join(memory_dir, "B.jsonl"))
  end

  test "store restores a corrected docs chunk as retracted on the next ideate run" do
    scenario_path = tmp_scenario_with_doc()

    run1 =
      Ideate.run_ideation(
        scenario: scenario_path,
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        rounds: 1,
        correct: "chunk:req.md",
        model: "mock",
        memory: false,
        store: true,
        persist?: false
      )

    assert run1.config.store.enabled
    assert run1.config.store.restored == 0
    assert run1.correction.target.status == :retracted
    assert get_in(run1.correction.target.meta, [:file]) == "req.md"

    run2 =
      Ideate.run_ideation(
        scenario: scenario_path,
        adapter_name: "mock",
        adapter_module: Tracefield.LLM.Mock,
        rounds: 1,
        model: "mock",
        memory: false,
        store: true,
        persist?: false
      )

    doc_chunks =
      Enum.filter(run2.entries, fn entry ->
        entry.type == :chunk and entry.author == "DOCS" and
          get_in(entry.meta, [:file]) == "req.md"
      end)

    assert run2.config.store.restored > 0
    assert length(doc_chunks) == 1
    assert hd(doc_chunks).status == :retracted
  end

  test "memory window injects only the most recent entries" do
    Process.register(self(), PromptCaptureMock)
    scenario_path = tmp_scenario()

    memory_dir =
      Path.join(
        System.tmp_dir!(),
        "tracefield-memory-window-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(memory_dir)

    File.write!(
      Path.join(memory_dir, "A.jsonl"),
      memory_line("older memory") <> memory_line("newer memory")
    )

    on_exit(fn -> File.rm_rf(memory_dir) end)

    Ideate.run_ideation(
      scenario: scenario_path,
      adapter_name: "mock",
      adapter_module: PromptCaptureMock,
      rounds: 1,
      model: "mock",
      memory: true,
      memory_window: 1,
      memory_dir: memory_dir,
      persist?: false
    )

    assert_receive {:ideate_prompt, "A", "model-a", a_prompt}
    assert a_prompt =~ "- newer memory"
    refute a_prompt =~ "older memory"
  end

  defp tmp_scenario do
    root =
      Path.join(System.tmp_dir!(), "tracefield-scenario-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "private"))
    File.write!(Path.join(root, "task.md"), "temporary task")
    File.write!(Path.join(root, "procedure.md"), "shared procedure")
    File.write!(Path.join(root, "procedure-a.md"), "procedure for A")

    File.write!(
      Path.join(root, "agents.json"),
      Jason.encode!([
        %{
          id: "A",
          domain: "alpha",
          desc: "alpha agent",
          private_doc: "a.md",
          model: "model-a",
          procedure: "procedure-a.md"
        },
        %{id: "B", domain: "beta", desc: "beta agent", private_doc: "b.md"}
      ])
    )

    File.write!(Path.join([root, "private", "a.md"]), "A private document")
    File.write!(Path.join([root, "private", "b.md"]), "B private document")
    on_exit(fn -> File.rm_rf(root) end)
    root
  end

  defp tmp_scenario_with_doc do
    root = tmp_scenario()
    File.mkdir_p!(Path.join(root, "docs"))
    File.write!(Path.join([root, "docs", "req.md"]), "req doc evidence")
    root
  end

  defp memory_line(text) do
    Jason.encode!(%{ts: "2026-06-10T00:00:00Z", mode: "converge", text: text, citations: []}) <>
      "\n"
  end

  defp cli_script(content) do
    path = Path.join(System.tmp_dir!(), "tracefield-cli-#{System.unique_integer([:positive])}.sh")
    File.write!(path, String.trim_leading(content))
    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp drain_ideate_prompts do
    receive do
      {:ideate_prompt, _agent, _model, _prompt} -> drain_ideate_prompts()
    after
      0 -> :ok
    end
  end
end
