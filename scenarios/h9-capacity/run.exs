# H9 実走（load-bearing 前提）— governance vs fusion containment
#   前提 P=確定ピーク QPS 50,000（findings が疑わず計算の土台にする実測値）を seed →
#   Opus 熟議 → Opus 合成 → P を「誤り(実は5,000)」として撤回し containment を実測。
# 実行: MIX_OS_CONCURRENCY_LOCK=0 mise exec -- mix run scenarios/h9-capacity/run.exs

alias Tracefield.{Agent, Reference, Synthesis, GovernanceVsFusion}

opus = "claude-opus-4-8-medium"
cli = {"cursor-agent", ["-p", "--output-format", "text", "--model", opus]}
dir = "scenarios/h9-capacity"
rounds = 2
gt_keywords = ["50,000", "50000", "5万"]
premise_text = "確定実測: 新サービスのピーク QPS は 50,000 である（容量・コスト・データ設計の確定土台）"
correction = "確定値が誤り: 実ピーク QPS は 5,000（公称の10分の1）だった。QPS 50,000 前提は撤回。"

task = File.read!(Path.join(dir, "task.md"))

agent_defs = [
  {"CAP", "capacity-sizing", "確定 QPS からサーバ台数・冗長度・スケールをサイジングする", "cap.md"},
  {"COST", "cost-estimation", "確定トラフィックからインフラ費用・年間コストを試算する", "cost.md"},
  {"DATA", "data-storage", "確定アクティブ数と7年保持からストレージ・シャードを設計する", "data.md"}
]

{:ok, reference} =
  Reference.start_link(
    embed_adapter: Tracefield.Embed.Ollama,
    embed_model: "nomic-embed-text",
    entries: [
      %{type: :chunk, author: "TASK", text: task, meta: %{domain: "task"}},
      %{type: :belief, author: "PREMISE", text: premise_text, meta: %{domain: "premise"}}
    ]
  )

premise = Enum.find(Reference.all(reference), &(&1.author == "PREMISE"))
IO.puts("== premise P = #{premise.id} ==")

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
      seed: 5000 + index
    )
  end)

IO.puts("== 熟議（#{length(agents)} agents × #{rounds} rounds, Opus）==")

Enum.reduce(1..rounds, agents, fn round, agents ->
  Enum.map(agents, fn agent ->
    {agent, entries, _log} = Agent.run_turn(agent, reference, round)
    IO.puts("  [#{agent.core.id}] +#{length(entries)}")
    agent
  end)
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
entries = Reference.all(reference)
IO.puts("== findings: #{length(findings)} ==")

labels = GovernanceVsFusion.semantic_labels(findings, premise.text, correction, label_model: opus, label_cli: cli)
gt = GovernanceVsFusion.invalidated(labels)
gt_keyword = GovernanceVsFusion.semantic_gt(findings, gt_keywords)
gov_reach = GovernanceVsFusion.gov_affected(entries, premise.id, mode: :reachable)
gov_direct = GovernanceVsFusion.gov_affected(entries, premise.id, mode: :direct)
fusion = GovernanceVsFusion.fusion_affected(findings, correction, posthoc_model: opus, posthoc_cli: cli)

s_reach = GovernanceVsFusion.score(gov_reach, gt)
s_direct = GovernanceVsFusion.score(gov_direct, gt)
s_fusion = GovernanceVsFusion.score(fusion, gt)
reinforced = for {id, "reinforced"} <- labels, do: id
unrelated = for {id, "unrelated"} <- labels, do: id
fmt = fn x -> :erlang.float_to_binary(x * 1.0, decimals: 2) end

IO.puts("\n=== H9 RESULT (premise #{premise.id} falsified) — 意味 GT ===")
IO.puts("served findings: #{length(findings)}")
IO.puts("invalidated: #{inspect(gt)} | reinforced: #{inspect(reinforced)} | unrelated: #{inspect(unrelated)}")
IO.puts("GOV reachable: recall=#{fmt.(s_reach.recall)} precision=#{fmt.(s_reach.precision)} (#{length(gov_reach)}件) calls=0")
IO.puts("GOV direct:    recall=#{fmt.(s_direct.recall)} precision=#{fmt.(s_direct.precision)} (#{inspect(gov_direct)}) calls=0")
IO.puts("FUSION-posthoc:recall=#{fmt.(s_fusion.recall)} precision=#{fmt.(s_fusion.precision)} (#{length(fusion)}件) calls=1")

out = Path.join(dir, "RESULT.md")

File.write!(out, """
# H9 実走結果（load-bearing 前提）— governance vs fusion containment（h9-capacity, 1 seed）

- premise P = #{premise.id}（確定ピーク QPS 50,000、実は5,000＝誤りとして撤回）
- served findings: #{length(findings)}
- **意味 GT invalidated（P 偽で破綻）**: #{inspect(gt)}
  - reinforced: #{inspect(reinforced)} / unrelated: #{inspect(unrelated)}
- 参考 keyword GT（#{inspect(gt_keywords)}）: #{inspect(gt_keyword)}

containment（vs 意味 GT invalidated, #{length(gt)} 件）:

| arm | affected | recall | precision | strong-model calls |
|---|---|---|---|---|
| GOV reachable | #{length(gov_reach)}件 | #{fmt.(s_reach.recall)} | #{fmt.(s_reach.precision)} | 0 |
| GOV direct | #{inspect(gov_direct)} | #{fmt.(s_direct.recall)} | #{fmt.(s_direct.precision)} | 0 |
| FUSION-posthoc | #{length(fusion)}件 | #{fmt.(s_fusion.recall)} | #{fmt.(s_fusion.precision)} | 1 |
| FUSION-naive | (来歴なし→隔離不能) | 0 | - | 全 consult 再実行 |

## findings（label 付き）
#{Enum.map_join(synthesis.findings, "\n", fn f -> "- [#{f.id}] (#{Map.get(labels, f.id, "?")}) cites=#{inspect(f.citations)} :: #{String.slice(f.text, 0, 140)}" end)}
""")

IO.puts("== 書き出し: #{out} ==")
