# FSL ブラッシュアップ consult — Cursor(Opus) で熟議 + best-of-N 合成（来歴付き）
# 実行: MIX_OS_CONCURRENCY_LOCK=0 mise exec -- mix run scenarios/fsl-brushup/run.exs

alias Tracefield.{Agent, Reference, Synthesis}

opus = "claude-opus-4-8-medium"
cli = {"cursor-agent", ["-p", "--output-format", "text", "--model", opus]}
dir = "scenarios/fsl-brushup"
rounds = 2

task = File.read!(Path.join(dir, "task.md"))

agent_defs = [
  {"LANG", "language-semantics-design", "FSL の言語・意味論・方言・refinement の設計を最優先する", "lang.md"},
  {"VERIF", "verification-engine-soundness", "Z3/BMC/k帰納法の健全性・完全性・診断品質を最優先する", "verif.md"},
  {"AGENT", "ai-agent-experience", "LLM が write→verify→repair ループを駆動する体験・スキル・運用を最優先する",
   "agent.md"}
]

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
      seed: 2000 + index
    )
  end)

IO.puts("== 熟議開始（#{length(agents)} agents × #{rounds} rounds, Cursor Opus）==")

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

IO.puts("== best-of-3 Opus 合成（接地判定も Opus）==")

# ground-truth の幅がゲートの識別力を決める。CHANGELOG だけだと「文書化済の緩和策」を
# 読み落とすので、LANGUAGE/SKILL/reference も連結する（既出機能の判定に効く）。
fsl_root =
  Enum.find(["../fsl", "../../fsl"], &File.dir?(Path.expand(&1, File.cwd!()))) ||
    "../fsl"

ground_truth =
  ["CHANGELOG.md", "docs/LANGUAGE.md", "skills/fsl/SKILL.md", "skills/fsl/reference.md"]
  |> Enum.map(fn rel ->
    path = Path.expand(Path.join(fsl_root, rel), File.cwd!())

    case File.read(path) do
      {:ok, c} -> "\n\n===== #{rel} =====\n" <> c
      _ -> ""
    end
  end)
  |> Enum.join()

synthesis =
  Synthesis.run(reference, layer0,
    synth_model: opus,
    synth_n: 3,
    verify_adapter: Tracefield.LLM.CLI,
    verify_model: opus,
    verify_cli: cli,
    novelty_check: true,
    ground_truth: ground_truth,
    novelty_adapter: Tracefield.LLM.CLI,
    novelty_model: opus,
    novelty_cli: cli
  )

IO.puts(
  "== novelty: #{length(Map.get(synthesis, :novel_findings, []))} novel / " <>
    "#{length(Map.get(synthesis, :shipped_findings, []))} shipped =="
)

layer0_index = Map.new(layer0, &{&1.id, {&1.author, &1.text}})

# --- 出力（人間可読 markdown） ---
out = Path.join(dir, "RESULT.md")

lines = [
  "# FSL ブラッシュアップ案 — tracefield 合成（Cursor Opus）\n",
  "task: #{String.split(task, "\n") |> hd()}\n",
  "- 熟議 layer-0 entries: #{length(layer0)}",
  "- 合成サンプル数: #{synthesis.sample_count}",
  "- 接地済 findings: #{length(synthesis.findings)}",
  "- 接地ゲートで落ちた引用: #{length(synthesis.dropped_citations)}\n",
  "## 合成された改善提案（来歴付き）\n"
]

finding_lines =
  synthesis.findings
  |> Enum.with_index(1)
  |> Enum.flat_map(fn {f, i} ->
    cites =
      f.citations
      |> Enum.map(fn cid ->
        case Map.get(layer0_index, cid) do
          {author, text} -> "    - [#{cid}] (#{author}) #{String.slice(text, 0, 160)}"
          nil -> "    - [#{cid}] (?)"
        end
      end)

    tag =
      case Map.get(f, :novelty) do
        %{shipped: true, reason: r} -> " — **SHIPPED**（#{String.slice(r, 0, 120)}）"
        %{shipped: false} -> " — NOVEL"
        _ -> ""
      end

    ["### 提案 #{i} `#{f.id}`#{tag}", "", f.text, "", "  来歴（依拠した懸念）:"] ++ cites ++ [""]
  end)

delib_lines =
  ["\n## 熟議で外部化された懸念（layer-0 全件）\n"] ++
    Enum.map(layer0, fn e -> "- [#{e.id}] (#{e.author}) #{e.text}" end)

File.write!(out, Enum.join(lines ++ finding_lines ++ delib_lines, "\n"))
IO.puts("== 書き出し: #{out} ==")
IO.puts("findings=#{length(synthesis.findings)} dropped=#{length(synthesis.dropped_citations)}")
