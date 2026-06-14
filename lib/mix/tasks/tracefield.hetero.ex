defmodule Mix.Tasks.Tracefield.Hetero do
  @moduledoc "Run the Tracefield heterogeneous private-document dose-response experiment."
  use Mix.Task

  alias Tracefield.{Discovery, Dissolution, GroundTruth, Metrics, Scenario}

  @shortdoc "Run Tracefield private-document heterogeneity experiment"
  @contrast_procedure_text "対比手続き v1: PRESENTED ENTRIES の各項目を、あなたの PRIVATE DOCUMENT の\n各事実と突き合わせよ。矛盾・衝突する組があれば、必ず【両方の事実をかっこ内キーワードごと明記】し、\nその entry を引用して belief として書け。エコー（提示内容の言い換え）は書くな。"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    result = run_experiment(opts)
    print_result(result)
  end

  def run_experiment(opts) do
    adapter_name = Keyword.get(opts, :adapter_name, Keyword.get(opts, :adapter, "mock"))

    adapter =
      if Keyword.has_key?(opts, :adapter),
        do: Keyword.fetch!(opts, :adapter),
        else: adapter_module(adapter_name)

    seeds = Keyword.get(opts, :seeds, 2)
    rounds = Keyword.get(opts, :rounds, 2)
    ks = Keyword.get(opts, :ks, [0, 2, 6])
    kps = Keyword.get(opts, :kps, [0])
    serves = Keyword.get(opts, :serves, [Keyword.get(opts, :serve, :similar)])
    awares = Keyword.get(opts, :awares, [Keyword.get(opts, :aware, 0)])
    heteros = Keyword.get(opts, :heteros, [:grounded])
    temperature = Keyword.get(opts, :temperature, 0.4)

    model =
      Keyword.get(
        opts,
        :model,
        if(adapter == Tracefield.LLM.Mock, do: "mock", else: "gemma4:12b")
      )

    judge_model = Keyword.get(opts, :judge_model, model)
    embed_model = Keyword.get(opts, :embed_model, "nomic-embed-text")

    # H1: substrate arms. Each arm = {name, model_map}; model_map overrides the
    # global model per agent id (empty map = all agents on the global model).
    # Default = single pass-through arm named after the global model (backward compatible).
    substrates = Keyword.get(opts, :substrates) || [{model, %{}}]
    # Judge defaults to the agent adapter (backward compatible). For CLI runs,
    # pass --judge-adapter ollama --judge-model gemma4:26b to keep the judge fast
    # and local (the primary metric disc_strict is judge-free anyway).
    judge_adapter = Keyword.get(opts, :judge_adapter) || adapter

    scenario =
      Keyword.get_lazy(opts, :scenario, fn -> Scenario.load!("scenarios/enterprise-assistant") end)

    grounded_docs =
      Keyword.get_lazy(opts, :private_docs, fn ->
        load_private_docs("scenarios/enterprise-assistant/private")
      end)

    combined_docs = grounded_docs |> Map.values() |> Enum.join("\n\n")
    homogeneous_docs = Map.new(Map.keys(grounded_docs), fn id -> {id, combined_docs} end)

    docs_for = fn
      :grounded -> grounded_docs
      :homogeneous -> homogeneous_docs
    end

    runs =
      for k <- ks,
          kp <- kps,
          serve <- serves,
          aware <- awares,
          hetero <- heteros,
          {substrate_name, substrate_models} <- substrates,
          index <- 0..(seeds - 1) do
        seed = 2_000 + index

        run_one(scenario,
          private_docs: docs_for.(hetero),
          k_s: k,
          k_p: kp,
          serve: serve,
          aware: aware,
          hetero: hetero,
          substrate_name: substrate_name,
          substrate_models: substrate_models,
          seed: seed,
          rounds: rounds,
          adapter: adapter,
          judge_adapter: judge_adapter,
          model: model,
          judge_model: judge_model,
          embed_model: embed_model,
          temperature: temperature
        )
      end

    summary = summary_by_cell(runs)
    path = persist(%{runs: runs, summary: summary}, adapter_name)

    %{
      runs: runs,
      summary: summary,
      disc_strict_kp_trend: kp_trend(summary, ks, kps, :disc_strict),
      disc_strict_serve_trend:
        serve_trend(summary, ks, kps, serves, awares, heteros, :disc_strict),
      disc_strict_aware_trend: aware_trend(summary, ks, kps, serves, awares, :disc_strict),
      disc_strict_substrate_trend: substrate_trend(summary, substrates, :disc_strict),
      diversity_trend: monotonic_trend(summary, ks, :diversity),
      path: path
    }
  end

  defp parse_args(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          adapter: :string,
          seeds: :integer,
          rounds: :integer,
          ks: :string,
          kp: :string,
          serve: :string,
          aware: :string,
          hetero: :string,
          substrate: :string,
          models: :string,
          model: :string,
          judge_adapter: :string,
          judge_model: :string,
          embed_model: :string,
          temperature: :float
        ],
        aliases: [a: :adapter, m: :model, t: :temperature]
      )

    adapter_name = Keyword.get(opts, :adapter, "mock")

    [
      adapter_name: adapter_name,
      adapter: adapter_module(adapter_name),
      seeds: Keyword.get(opts, :seeds, 2),
      rounds: Keyword.get(opts, :rounds, 2),
      ks: parse_ks(Keyword.get(opts, :ks, "0,2,6")),
      kps: parse_kps(Keyword.get(opts, :kp, "0")),
      serves: parse_serves(Keyword.get(opts, :serve, "similar")),
      awares: parse_awares(Keyword.get(opts, :aware, "0")),
      heteros: parse_heteros(Keyword.get(opts, :hetero, "grounded")),
      substrates: build_substrates(Keyword.get(opts, :substrate), Keyword.get(opts, :models)),
      model: Keyword.get(opts, :model),
      judge_adapter: maybe_adapter_module(Keyword.get(opts, :judge_adapter)),
      judge_model: Keyword.get(opts, :judge_model),
      embed_model: Keyword.get(opts, :embed_model, "nomic-embed-text"),
      temperature: Keyword.get(opts, :temperature, 0.4)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp run_one(scenario, opts) do
    k_s = Keyword.fetch!(opts, :k_s)
    k_p = Keyword.fetch!(opts, :k_p)
    serve = Keyword.fetch!(opts, :serve)
    aware = Keyword.fetch!(opts, :aware)
    hetero = Keyword.fetch!(opts, :hetero)
    seed = Keyword.fetch!(opts, :seed)
    rounds = Keyword.fetch!(opts, :rounds)
    adapter = Keyword.fetch!(opts, :adapter)
    model = Keyword.fetch!(opts, :model)
    temperature = Keyword.fetch!(opts, :temperature)
    private_docs = Keyword.fetch!(opts, :private_docs)
    substrate_models = Keyword.get(opts, :substrate_models, %{})
    substrate_name = Keyword.get(opts, :substrate_name, model)
    judge_adapter = Keyword.get(opts, :judge_adapter, adapter)

    {:ok, reference} =
      Tracefield.Reference.start_link(
        embed_adapter:
          if(adapter == Tracefield.LLM.Mock,
            do: Tracefield.Embed.Mock,
            else: Tracefield.Embed.Ollama
          ),
        embed_model: Keyword.fetch!(opts, :embed_model),
        entries: [
          %{
            type: :chunk,
            author: "TASK",
            text: scenario.task,
            meta: %{domain: "task"}
          }
        ]
      )

    procedure_id = absorb_procedure(reference, k_p)

    agents =
      Dissolution.default_agents()
      |> Enum.with_index()
      |> Enum.map(fn {agent, index} ->
        organ = Map.get(substrate_models, agent.id)

        Tracefield.Agent.new(agent.id, agent.domain, agent.desc,
          anchor: scenario.task,
          private_doc: Map.fetch!(private_docs, agent.id),
          k_s: k_s,
          adapter: adapter,
          model: organ_model(organ, model),
          cli: organ_cli(organ),
          temperature: temperature,
          seed: seed + index,
          procedure_id: procedure_id,
          serve_policy: serve,
          aware: aware == 1
        )
      end)

    {_agents, absorbed, perception} =
      Enum.reduce(1..rounds, {agents, [], []}, fn round, {agents, absorbed, perception} ->
        {agents, round_absorbed, round_perception} = run_round(agents, reference, round)
        {agents, absorbed ++ round_absorbed, perception ++ round_perception}
      end)

    concerns_by_agent = concerns_by_agent(absorbed)

    measure =
      Dissolution.measure_concerns(concerns_by_agent,
        adapter: adapter,
        judge_adapter: judge_adapter,
        model: model,
        judge_model: Keyword.fetch!(opts, :judge_model),
        embed_model: Keyword.fetch!(opts, :embed_model),
        temperature: temperature,
        seed: seed
      )

    disc_strict =
      Discovery.strict_score(absorbed)

    disc_judge =
      Discovery.score(absorbed,
        judge_adapter: judge_adapter,
        judge_model: Keyword.fetch!(opts, :judge_model),
        temperature: temperature,
        seed: seed
      )

    %{
      k: k_s,
      kp: k_p,
      serve: serve,
      aware: aware,
      hetero: hetero,
      substrate: substrate_name,
      seed: seed,
      disc_strict: disc_strict.count,
      disc_judge: disc_judge.count,
      discovery_count: disc_strict.count,
      discovery: disc_strict.per_interaction,
      discovery_judge: disc_judge.per_interaction,
      icc: measure.icc,
      coverage: measure.coverage,
      diversity: measure.diversity,
      collapse_rate: measure.collapse_rate,
      concerns_by_agent: concerns_by_agent,
      absorbed_entries: plain_entries(absorbed),
      perception: perception,
      procedure_id: procedure_id,
      reference: reference
    }
  end

  defp absorb_procedure(_reference, 0), do: nil

  defp absorb_procedure(reference, 1) do
    [procedure] =
      Tracefield.Reference.absorb(
        reference,
        [
          %{
            type: :procedure,
            text: @contrast_procedure_text,
            meta: %{domain: "procedure"}
          }
        ],
        "FACILITATOR"
      )

    procedure.id
  end

  defp absorb_procedure(_reference, other), do: Mix.raise("invalid k_p value #{inspect(other)}")

  defp run_round(agents, reference, round) do
    agents
    |> Enum.reduce({[], [], []}, fn agent, {updated_agents, absorbed, perception} ->
      {agent, entries, log} = Tracefield.Agent.run_turn(agent, reference, round)
      {updated_agents ++ [agent], absorbed ++ entries, perception ++ [log]}
    end)
  end

  defp concerns_by_agent(entries) do
    entries
    |> Enum.reject(&(&1.type == :chunk))
    |> Enum.group_by(& &1.author, & &1.text)
  end

  defp summary_by_cell(runs) do
    runs
    |> Enum.group_by(&{&1.k, &1.kp, &1.serve, &1.aware, &1.hetero, Map.get(&1, :substrate)})
    |> Enum.map(fn {{k, kp, serve, aware, hetero, substrate}, rows} ->
      %{
        k: k,
        kp: kp,
        serve: serve,
        aware: aware,
        hetero: hetero,
        substrate: substrate,
        disc_strict: Metrics.summary(Enum.map(rows, &(&1.disc_strict * 1.0))),
        disc_judge: Metrics.summary(Enum.map(rows, &(&1.disc_judge * 1.0))),
        icc: Metrics.summary(Enum.map(rows, &(&1.icc * 1.0))),
        coverage: Metrics.summary(Enum.map(rows, &(&1.coverage * 1.0))),
        diversity: Metrics.summary(Enum.map(rows, & &1.diversity)),
        collapse_rate: Metrics.summary(Enum.map(rows, & &1.collapse_rate))
      }
    end)
    |> Enum.sort_by(&{&1.k, &1.kp, to_string(&1.serve), to_string(&1.aware), to_string(&1.hetero), to_string(&1.substrate)})
  end

  defp monotonic_trend(summary, ks, metric) do
    values =
      Enum.map(ks, fn k ->
        rows = Enum.filter(summary, &(&1.k == k))

        case rows do
          [] -> 0.0
          _ -> Enum.sum(Enum.map(rows, &(get_in(&1, [metric, :mean]) || 0.0))) / length(rows)
        end
      end)

    cond do
      values == Enum.sort(values) -> :nondecreasing
      values == Enum.sort(values, :desc) -> :nonincreasing
      true -> :mixed
    end
  end

  defp kp_trend(summary, ks, kps, metric) do
    Map.new(ks, fn k ->
      values =
        Enum.map(kps, fn kp ->
          rows = Enum.filter(summary, &(&1.k == k and &1.kp == kp))

          case rows do
            [] -> 0.0
            _ -> Enum.sum(Enum.map(rows, &(get_in(&1, [metric, :mean]) || 0.0))) / length(rows)
          end
        end)

      trend =
        cond do
          values == Enum.sort(values) -> :nondecreasing
          values == Enum.sort(values, :desc) -> :nonincreasing
          true -> :mixed
        end

      {k, %{kps: kps, values: values, trend: trend}}
    end)
  end

  defp serve_trend(summary, ks, kps, serves, awares, heteros, metric) do
    for k <- ks, kp <- kps, aware <- awares, hetero <- heteros, into: %{} do
      values =
        Enum.map(serves, fn serve ->
          summary
          |> Enum.find(
            &(&1.k == k and &1.kp == kp and &1.serve == serve and &1.aware == aware and
                &1.hetero == hetero)
          )
          |> summary_mean(metric)
        end)

      {{k, kp, aware, hetero}, %{serves: serves, values: values, trend: trend(values)}}
    end
  end

  defp aware_trend(summary, ks, kps, serves, awares, metric) do
    for k <- ks, kp <- kps, serve <- serves, into: %{} do
      values =
        Enum.map(awares, fn aware ->
          summary
          |> Enum.find(&(&1.k == k and &1.kp == kp and &1.serve == serve and &1.aware == aware))
          |> summary_mean(metric)
        end)

      {{k, kp, serve}, %{awares: awares, values: values, trend: trend(values)}}
    end
  end

  # H1 headline: mean metric per substrate arm (pooled over all other cells).
  defp substrate_trend(summary, substrates, metric) do
    Map.new(substrates, fn {name, _models} ->
      rows = Enum.filter(summary, &(&1.substrate == name))

      mean =
        case rows do
          [] -> 0.0
          _ -> Enum.sum(Enum.map(rows, &(get_in(&1, [metric, :mean]) || 0.0))) / length(rows)
        end

      {name, mean}
    end)
  end

  defp summary_mean(nil, _metric), do: 0.0
  defp summary_mean(row, metric), do: get_in(row, [metric, :mean]) || 0.0

  defp trend(values) do
    cond do
      values == Enum.sort(values) -> :nondecreasing
      values == Enum.sort(values, :desc) -> :nonincreasing
      true -> :mixed
    end
  end

  defp load_private_docs(dir) do
    %{
      "SEC" => File.read!(Path.join(dir, "sec.md")),
      "BIZ" => File.read!(Path.join(dir, "biz.md")),
      "UX" => File.read!(Path.join(dir, "ux.md"))
    }
  end

  defp persist(result, adapter_name) do
    File.mkdir_p!("runs")

    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace("Z", "")

    path = "runs/#{timestamp}-hetero-#{adapter_name}.json"

    serializable =
      result
      |> Map.update!(:runs, fn runs -> Enum.map(runs, &Map.drop(&1, [:reference])) end)
      |> GroundTruth.to_plain()

    File.write!(path, Jason.encode!(serializable, pretty: true))
    path
  end

  defp print_result(result) do
    Mix.shell().info("Tracefield Hetero")
    Mix.shell().info("runs:")

    Mix.shell().info(
      "k kp serve aware hetero substrate seed disc_strict disc_judge icc coverage diversity collapse"
    )

    Enum.each(result.runs, fn row ->
      Mix.shell().info(
        "#{row.k} #{row.kp} #{row.serve} #{row.aware} #{row.hetero} #{Map.get(row, :substrate)} #{row.seed} #{row.disc_strict} #{row.disc_judge} #{row.icc} #{row.coverage} #{fmt(row.diversity)} #{fmt(row.collapse_rate)}"
      )
    end)

    Mix.shell().info("")
    Mix.shell().info("aggregate mean±sd:")

    Mix.shell().info(
      "k kp serve aware hetero substrate disc_strict disc_judge icc coverage diversity collapse"
    )

    result.summary
    |> Enum.sort_by(&{&1.k, &1.kp, to_string(&1.serve), to_string(&1.aware), to_string(&1.hetero), to_string(Map.get(&1, :substrate))})
    |> Enum.each(fn row ->
      Mix.shell().info(
        "#{row.k} #{row.kp} #{row.serve} #{row.aware} #{row.hetero} #{Map.get(row, :substrate)} #{mean_sd(row.disc_strict)} #{mean_sd(row.disc_judge)} #{mean_sd(row.icc)} #{mean_sd(row.coverage)} #{mean_sd(row.diversity)} #{mean_sd(row.collapse_rate)}"
      )
    end)

    Mix.shell().info("")
    Mix.shell().info("trend: disc_strict across kp")

    result.disc_strict_kp_trend
    |> Enum.sort_by(fn {k, _row} -> k end)
    |> Enum.each(fn {k, row} ->
      pairs =
        Enum.zip(row.kps, row.values)
        |> Enum.map_join(" ", fn {kp, value} -> "kp=#{kp}:#{fmt(value)}" end)

      Mix.shell().info("k=#{k} #{pairs} #{row.trend}")
    end)

    Mix.shell().info("trend: disc_strict across serve")

    result.disc_strict_serve_trend
    |> Enum.sort_by(fn {{k, kp, aware, hetero}, _row} -> {k, kp, aware, hetero} end)
    |> Enum.each(fn {{k, kp, aware, hetero}, row} ->
      pairs =
        Enum.zip(row.serves, row.values)
        |> Enum.map_join(" ", fn {serve, value} -> "serve=#{serve}:#{fmt(value)}" end)

      Mix.shell().info("k=#{k} kp=#{kp} aware=#{aware} hetero=#{hetero} #{pairs} #{row.trend}")
    end)

    Mix.shell().info("trend: disc_strict across aware")

    result.disc_strict_aware_trend
    |> Enum.sort_by(fn {{k, kp, serve}, _row} -> {k, kp, serve} end)
    |> Enum.each(fn {{k, kp, serve}, row} ->
      pairs =
        Enum.zip(row.awares, row.values)
        |> Enum.map_join(" ", fn {aware, value} -> "aware=#{aware}:#{fmt(value)}" end)

      Mix.shell().info("k=#{k} kp=#{kp} serve=#{serve} #{pairs} #{row.trend}")
    end)

    Mix.shell().info("")
    Mix.shell().info("H1 trend: disc_strict by substrate (mean over cells)")

    result.disc_strict_substrate_trend
    |> Enum.sort_by(fn {name, _value} -> to_string(name) end)
    |> Enum.each(fn {name, value} ->
      Mix.shell().info("substrate=#{name}: #{fmt(value)}")
    end)

    Mix.shell().info("trend: diversity vs k is #{result.diversity_trend}")
    Mix.shell().info("saved: #{result.path}")
  end

  defp plain_entries(entries) do
    Enum.map(entries, fn entry ->
      %{
        id: entry.id,
        type: entry.type,
        author: entry.author,
        version: entry.version,
        status: entry.status,
        text: entry.text,
        citations: entry.citations,
        meta: entry.meta
      }
    end)
  end

  defp adapter_module("mock"), do: Tracefield.LLM.Mock
  defp adapter_module("ollama"), do: Tracefield.LLM.Ollama
  defp adapter_module("openrouter"), do: Tracefield.LLM.OpenRouter
  defp adapter_module("cli"), do: Tracefield.LLM.CLI
  defp adapter_module(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp maybe_adapter_module(nil), do: nil
  defp maybe_adapter_module(name), do: adapter_module(name)

  defp parse_ks(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(fn item ->
      case Integer.parse(String.trim(item)) do
        {k, ""} when k >= 0 -> k
        _ -> Mix.raise("invalid k_s value #{inspect(item)}")
      end
    end)
  end

  defp parse_kps(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(fn item ->
      case Integer.parse(String.trim(item)) do
        {kp, ""} when kp in [0, 1] -> kp
        _ -> Mix.raise("invalid k_p value #{inspect(item)}")
      end
    end)
  end

  defp parse_serves(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(fn item ->
      case String.trim(item) do
        "similar" -> :similar
        "diverse" -> :diverse
        "contrastive" -> :contrastive
        other -> Mix.raise("invalid serve value #{inspect(other)}")
      end
    end)
  end

  def parse_heteros(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(fn item ->
      case String.trim(item) do
        "grounded" -> :grounded
        "homogeneous" -> :homogeneous
        other -> Mix.raise("invalid hetero value #{inspect(other)}")
      end
    end)
  end

  defp parse_awares(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(fn item ->
      case Integer.parse(String.trim(item)) do
        {aware, ""} when aware in [0, 1] -> aware
        _ -> Mix.raise("invalid aware value #{inspect(item)}")
      end
    end)
  end

  # H1 substrate arms. Returns [{name, model_map}] or nil (let run_experiment default).
  # --substrate takes precedence over --models. Presets target the default SEC/BIZ/UX agents.
  defp build_substrates(nil, nil), do: nil

  defp build_substrates(nil, models) when is_binary(models) do
    [{"custom", parse_models(models)}]
  end

  defp build_substrates(substrate, _models) when is_binary(substrate) do
    substrate
    |> String.split(",", trim: true)
    |> Enum.map(&substrate_preset(String.trim(&1)))
  end

  defp substrate_preset("homo12b"),
    do: {"homo12b", %{"SEC" => "gemma4:12b", "BIZ" => "gemma4:12b", "UX" => "gemma4:12b"}}

  defp substrate_preset("homo26b"),
    do: {"homo26b", %{"SEC" => "gemma4:26b", "BIZ" => "gemma4:26b", "UX" => "gemma4:26b"}}

  defp substrate_preset("hetero"),
    do: {"hetero", %{"SEC" => "gemma4:12b", "BIZ" => "gemma4:26b", "UX" => "gemma4:12b"}}

  # Cross-family organs via ONE uniform CLI: cursor-agent with different --model.
  # Composer (Cursor) / Opus (Anthropic) / GPT (OpenAI) are genuinely different
  # families, yet share one clean output path (-p --output-format text) and one
  # safe profile (NO --force/--trust ⇒ reasoning only, never runs repo commands).
  # No API key / no per-token cost — uses the Cursor subscription. Use --adapter cli.
  defp substrate_preset("cur-composer"), do: {"cur-composer", all_cli(cursor_cli("composer-2.5"))}
  defp substrate_preset("cur-opus"), do: {"cur-opus", all_cli(cursor_cli("claude-opus-4-8-medium"))}
  defp substrate_preset("cur-gpt"), do: {"cur-gpt", all_cli(cursor_cli("gpt-5.5-medium"))}

  defp substrate_preset("cur-hetero"),
    do:
      {"cur-hetero",
       %{
         "SEC" => cursor_cli("claude-opus-4-8-medium"),
         "BIZ" => cursor_cli("gpt-5.5-medium"),
         "UX" => cursor_cli("composer-2.5")
       }}

  defp substrate_preset(other), do: Mix.raise("invalid substrate value #{inspect(other)}")

  defp all_cli(cli), do: %{"SEC" => cli, "BIZ" => cli, "UX" => cli}
  defp cursor_cli(model), do: {"cursor-agent", ["-p", "--output-format", "text", "--model", model]}

  # A substrate organ is either a model id (string → routed via the global
  # adapter) or a {cmd, args} CLI tuple (→ Tracefield.LLM.CLI). nil = use the
  # global model fallback.
  defp organ_model({_cmd, _args}, fallback), do: fallback
  defp organ_model(model, _fallback) when is_binary(model), do: model
  defp organ_model(_organ, fallback), do: fallback

  defp organ_cli({_cmd, _args} = cli), do: cli
  defp organ_cli(_organ), do: nil

  defp parse_models(value) do
    value
    |> String.split(",", trim: true)
    |> Map.new(fn pair ->
      case String.split(String.trim(pair), "=", parts: 2) do
        [id, model] when model != "" -> {String.trim(id), String.trim(model)}
        _ -> Mix.raise("invalid models pair #{inspect(pair)} (expected ID=model)")
      end
    end)
  end

  defp mean_sd(summary), do: "#{fmt(summary.mean)}±#{fmt(summary.sd)}"
  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)
end
