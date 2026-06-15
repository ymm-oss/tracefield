# tracefield 自己ブラッシュアップ consult — Cursor(Opus) 5観点熟議 + best-of-5 合成
#   + 接地ゲート + 新規性ゲート(自分の findings/docs を ground-truth) + 意味的 dedup
# 実行: MIX_OS_CONCURRENCY_LOCK=0 mise exec -- mix run scenarios/tracefield-brushup/run.exs

alias Tracefield.{Agent, Reference, Synthesis}

opus = "claude-opus-4-8-medium"
cli = {"cursor-agent", ["-p", "--output-format", "text", "--model", opus]}
dir = "scenarios/tracefield-brushup"
rounds = 3

task = File.read!(Path.join(dir, "task.md"))

agent_defs = [
  {"RESEARCH", "research-validity",
   "tracefield の実験プログラムの内的/外的妥当性・反証可能性を最優先する", "research.md"},
  {"SYNTH", "synthesis-serving",
   "best-of-N 合成層と consult serving 経路・retrieval 天井を最優先する", "synth.md"},
  {"GOVERNANCE", "governance-core",
   "来歴・撤回閉包・citation 接地精度(Fusion 不可の固有価値)を最優先する", "governance.md"},
  {"AGENT", "agent-llm-layer",
   "熟議機構・エージェント抽象・アダプタ・tool-use・serve policy を最優先する", "agent.md"},
  {"ADOPTION", "adoption-product",
   "機構の証明と実利用のギャップ・製品戦略を最優先する", "adoption.md"}
]

# ground-truth: tracefield 自身の findings/conclusions/design 群（既出=shipped 判定の根拠）
ground_truth =
  Path.wildcard("docs/{conclusions,findings-*,design-*}.md")
  |> Enum.map(fn p ->
    case File.read(p) do
      {:ok, c} -> "\n\n===== #{p} =====\n" <> c
      _ -> ""
    end
  end)
  |> Enum.join()

{:ok, reference} =
  Reference.start_link(
    embed_adapter: Tracefield.Embed.Ollama,
    embed_model: "nomic-embed-text",
    entries: [%{type: :chunk, author: "TASK", text: task, meta: %{domain: "task"}}]
  )

agents =
  agent_defs
  |> Enum.with_index()
  |> Enum.map(fn {{id, domain, desc, doc}, index} ->
    Agent.new(id, domain, desc,
      anchor: task,
      private_doc: File.read!(Path.join([dir, "private", doc])),
      adapter: Tracefield.LLM.CLI,
      cli: cli,
      model: opus,
      serve_policy: :diverse,
      aware: true,
      seed: 3000 + index
    )
  end)

IO.puts("== 熟議開始（#{length(agents)} agents × #{rounds} rounds, Cursor Opus）==")
IO.puts("== ground-truth: #{div(String.length(ground_truth), 1000)}k chars ==")

{_agents, absorbed} =
  Enum.reduce(1..rounds, {agents, []}, fn round, {agents, absorbed} ->
    IO.puts("-- round #{round} --")

    {agents, round_absorbed} =
      Enum.reduce(agents, {[], []}, fn agent, {updated, acc} ->
        {agent, entries, _log} = Agent.run_turn(agent, reference, round)
        IO.puts("  [#{agent.core.id}] +#{length(entries)} entries")
        {updated ++ [agent], acc ++ entries}
      end)

    {agents, absorbed ++ round_absorbed}
  end)

layer0 = Enum.reject(absorbed, &(&1.type == :chunk))
IO.puts("== layer-0 entries: #{length(layer0)} ==")
IO.puts("== best-of-5 Opus 合成 + 接地/新規性ゲート + dedup ==")

synthesis =
  Synthesis.run(reference, layer0,
    synth_model: opus,
    synth_n: 5,
    verify_adapter: Tracefield.LLM.CLI,
    verify_model: opus,
    verify_cli: cli,
    novelty_check: true,
    ground_truth: ground_truth,
    novelty_adapter: Tracefield.LLM.CLI,
    novelty_model: opus,
    novelty_cli: cli,
    dedupe: true,
    dedupe_threshold: 0.85
  )

IO.puts(
  "== findings=#{length(synthesis.findings)} " <>
    "novel=#{length(Map.get(synthesis, :novel_findings, []))} " <>
    "shipped=#{length(Map.get(synthesis, :shipped_findings, []))} " <>
    "dedupe=#{Map.get(synthesis, :dedupe_input, "?")}→#{Map.get(synthesis, :dedupe_clusters, "?")} " <>
    "dropped=#{length(synthesis.dropped_citations)} =="
)

layer0_index = Map.new(layer0, &{&1.id, {&1.author, &1.text}})
out = Path.join(dir, "RESULT.md")

header = [
  "# tracefield 自己ブラッシュアップ案 — tracefield 合成（Cursor Opus, 5観点）\n",
  "- 熟議 layer-0 entries: #{length(layer0)}（#{length(agent_defs)} agents × #{rounds} rounds）",
  "- 合成サンプル数: #{synthesis.sample_count}",
  "- dedup: #{Map.get(synthesis, :dedupe_input, "?")} findings → #{Map.get(synthesis, :dedupe_clusters, "?")} clusters",
  "- novel: #{length(Map.get(synthesis, :novel_findings, []))} / shipped: #{length(Map.get(synthesis, :shipped_findings, []))}",
  "- 接地ゲートで落ちた引用: #{length(synthesis.dropped_citations)}\n",
  "## 改善提案（来歴付き・novel/shipped・クラスタ規模）\n"
]

finding_lines =
  synthesis.findings
  |> Enum.with_index(1)
  |> Enum.flat_map(fn {f, i} ->
    cites =
      f.citations
      |> Enum.map(fn cid ->
        case Map.get(layer0_index, cid) do
          {author, text} -> "    - [#{cid}] (#{author}) #{String.slice(text, 0, 150)}"
          nil -> "    - [#{cid}] (?)"
        end
      end)

    nv =
      case Map.get(f, :novelty) do
        %{shipped: true, reason: r} -> "**SHIPPED** — #{String.slice(r, 0, 140)}"
        %{shipped: false} -> "NOVEL"
        _ -> "?"
      end

    size = Map.get(f, :cluster_size, 1)
    ["### 提案 #{i} `#{f.id}` [#{nv}] (×#{size})", "", f.text, "", "  来歴:"] ++ cites ++ [""]
  end)

delib_lines =
  ["\n## 熟議で外部化された懸念（layer-0 全件）\n"] ++
    Enum.map(layer0, fn e -> "- [#{e.id}] (#{e.author}) #{e.text}" end)

File.write!(out, Enum.join(header ++ finding_lines ++ delib_lines, "\n"))
IO.puts("== 書き出し: #{out} ==")
