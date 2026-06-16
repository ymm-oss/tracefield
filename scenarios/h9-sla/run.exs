# H9 実走 — governance vs fusion containment（1ドメイン実データ点）
#   前提 P(AcmeCloud SLA 99.99%)を seed → Opus 熟議 → Opus 合成(stance-audit on) →
#   P を「偽」として GOV(closure) vs FUSION-posthoc(Opus 再読) の containment を実測。
# 実行: MIX_OS_CONCURRENCY_LOCK=0 mise exec -- mix run scenarios/h9-sla/run.exs

alias Tracefield.{Agent, Reference, Synthesis, GovernanceVsFusion}

opus = "claude-opus-4-8-medium"
cli = {"cursor-agent", ["-p", "--output-format", "text", "--model", opus]}
dir = "scenarios/h9-sla"
rounds = 2
gt_keywords = ["AcmeCloud"]

task = File.read!(Path.join(dir, "task.md"))

agent_defs = [
  {"OPS", "reliability", "信頼性・可用性・障害設計を最優先する", "ops.md"},
  {"BIZ", "business-speed", "コスト・上市速度・ROI を最優先する", "biz.md"},
  {"SEC", "security", "セキュリティ・データ保護・規制を最優先する", "sec.md"}
]

# 前提 P を layer-0 に seed（findings がこれに依拠する）。task chunk と並べて absorb。
{:ok, reference} =
  Reference.start_link(
    embed_adapter: Tracefield.Embed.Ollama,
    embed_model: "nomic-embed-text",
    entries: [
      %{type: :chunk, author: "TASK", text: task, meta: %{domain: "task"}},
      %{
        type: :belief,
        author: "PREMISE",
        text: "ベンダー AcmeCloud の SLA は 99.99% の稼働率を保証する（ロールアウト設計の前提）",
        meta: %{domain: "premise"}
      }
    ]
  )

premise = Enum.find(Reference.all(reference), &(&1.author == "PREMISE"))
IO.puts("== premise P = #{premise.id} (#{premise.text}) ==")

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
      seed: 4000 + index
    )
  end)

IO.puts("== 熟議（#{length(agents)} agents × #{rounds} rounds, Opus）==")

{_agents, _absorbed} =
  Enum.reduce(1..rounds, {agents, []}, fn round, {agents, acc} ->
    {agents, ra} =
      Enum.reduce(agents, {[], []}, fn agent, {updated, racc} ->
        {agent, entries, _log} = Agent.run_turn(agent, reference, round)
        IO.puts("  [#{agent.core.id}] +#{length(entries)}")
        {updated ++ [agent], racc ++ entries}
      end)

    {agents, acc ++ ra}
  end)

layer0 = Enum.reject(Reference.all(reference), &(&1.type == :chunk))
IO.puts("== layer-0: #{length(layer0)} ==")
IO.puts("== best-of-3 Opus 合成（stance-audit on）==")

synthesis =
  Synthesis.run(reference, layer0,
    synth_model: opus,
    synth_n: 3,
    verify_adapter: Tracefield.LLM.CLI,
    verify_model: opus,
    verify_cli: cli,
    stance_audit: true,
    stance_adapter: Tracefield.LLM.CLI,
    stance_model: opus,
    stance_cli: cli
  )

findings = Enum.map(synthesis.findings, &%{id: &1.id, text: &1.text})
IO.puts("== findings: #{length(findings)} ==")

# --- H9 head-to-head: P が偽と判明したときの containment ---
correction = "前提が誤り: AcmeCloud の SLA 99.99% 保証は実際には存在しない（撤回）"
entries = Reference.all(reference)

gt = GovernanceVsFusion.semantic_gt(findings, gt_keywords)
gov = GovernanceVsFusion.gov_affected(entries, premise.id)

fusion =
  GovernanceVsFusion.fusion_affected(findings, correction,
    posthoc_model: opus,
    posthoc_cli: cli
  )

gov_score = GovernanceVsFusion.score(gov, gt)
fusion_score = GovernanceVsFusion.score(fusion, gt)

IO.puts("\n=== H9 RESULT (premise #{premise.id} falsified) ===")
IO.puts("served findings: #{length(findings)}")
IO.puts("GT (含 #{inspect(gt_keywords)}): #{inspect(gt)}")
IO.puts("GOV (closure):    #{inspect(gov)}  recall=#{gov_score.recall} precision=#{gov_score.precision} calls=0")
IO.puts("FUSION-posthoc:   #{inspect(fusion)}  recall=#{fusion_score.recall} precision=#{fusion_score.precision} calls=1")

out = Path.join(dir, "RESULT.md")

File.write!(out, """
# H9 実走結果 — governance vs fusion containment（h9-sla, 1 seed）

- premise P = #{premise.id}（AcmeCloud SLA 99.99%、偽と判明させ撤回）
- served findings: #{length(findings)}
- GT（"AcmeCloud" を含む findings = 真に依拠）: #{inspect(gt)}

| arm | affected | recall | precision | strong-model calls |
|---|---|---|---|---|
| GOV (provenance closure) | #{inspect(gov)} | #{gov_score.recall} | #{gov_score.precision} | 0 |
| FUSION-posthoc (Opus 再読) | #{inspect(fusion)} | #{fusion_score.recall} | #{fusion_score.precision} | 1 |
| FUSION-naive | (来歴なし→隔離不能) | 0 | - | 全 consult 再実行 |

## findings
#{Enum.map_join(synthesis.findings, "\n", fn f -> "- [#{f.id}] cites=#{inspect(f.citations)} :: #{String.slice(f.text, 0, 160)}" end)}
""")

IO.puts("== 書き出し: #{out} ==")
