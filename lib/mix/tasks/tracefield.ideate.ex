defmodule Mix.Tasks.Tracefield.Ideate do
  @moduledoc "Run Tracefield qualitative ideation over a scenario directory."
  use Mix.Task

  alias Tracefield.{Culture, Dissolution, GroundTruth, Memory, Reference}

  @shortdoc "Run Tracefield ideation"
  @review_procedure """
                    リスクレビュー手続き v1: PRESENTED ENTRIES と PRIVATE DOCUMENT を突き合わせ、この計画のリスク・矛盾・見落としを具体的に指摘せよ。賛辞や言い換えは書くな。各指摘は根拠（私的事実 or 提示 entry の引用）を必ず持て。日本語で書け。
                    """
                    |> String.trim()

  @mode_presets %{
    diverge: %{rounds: 2, k: 1, temperature: 0.8},
    converge: %{rounds: 3, k: 4, temperature: 0.5},
    review: %{rounds: 2, k: 3, temperature: 0.4}
  }

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    args
    |> parse_args()
    |> run_ideation()
    |> print_result()
  end

  def run_ideation(opts) do
    run_started_at = DateTime.utc_now() |> DateTime.to_iso8601()
    mode = normalize_mode(Keyword.get(opts, :mode, :converge))
    preset = mode_preset(mode)

    adapter_name =
      Keyword.get(opts, :adapter_name, adapter_name(Keyword.get(opts, :adapter, "mock")))

    adapter = adapter(opts, adapter_name)
    embed_adapter = Keyword.get(opts, :embed_adapter, default_embed_adapter(adapter))
    scenario_path = Keyword.fetch!(opts, :scenario)
    cli = Keyword.get_lazy(opts, :cli, fn -> cli_config(opts) end)

    scenario =
      Keyword.get_lazy(opts, :loaded_scenario, fn -> load_scenario!(scenario_path, mode) end)

    rounds = Keyword.get(opts, :rounds, preset.rounds)

    serve =
      Keyword.get(opts, :serve_policy, Keyword.get(opts, :serve, :diverse)) |> normalize_serve()

    aware = Keyword.get(opts, :aware, 1)
    k_s = Keyword.get(opts, :k_s, Keyword.get(opts, :k, preset.k))
    temperature = Keyword.get(opts, :temperature, preset.temperature)

    model =
      Keyword.get(
        opts,
        :model,
        if(adapter == Tracefield.LLM.Mock, do: "mock", else: "gemma4:12b")
      )

    embed_model = Keyword.get(opts, :embed_model, "nomic-embed-text")
    memory? = opts |> Keyword.get(:memory, true) |> normalize_bool()
    memory_window = opts |> Keyword.get(:memory_window, 10) |> max(0)
    memory_dir = Keyword.get(opts, :memory_dir, Path.join(scenario_path, "memory"))
    store? = opts |> Keyword.get(:store, false) |> normalize_bool()
    store_path = if store?, do: Path.join(scenario_path, "store.jsonl")
    distill? = opts |> Keyword.get(:distill, false) |> normalize_bool()
    distill_mode = opts |> Keyword.get(:distill_mode, :extractive) |> normalize_distill_mode()

    {:ok, reference} =
      Reference.start_link(
        embed_adapter: embed_adapter,
        embed_model: embed_model,
        persist_path: store_path
      )

    seed_entries =
      [
        %{
          type: :chunk,
          author: "TASK",
          text: scenario.task,
          meta: %{domain: "task"}
        }
      ] ++ doc_seed_entries(scenario.docs)

    Reference.absorb_idempotent(reference, seed_entries, "TASK")

    reference_docs = reference_docs(reference)
    shared_procedure_id = absorb_procedure(reference, scenario.procedure)
    injected_house_view = if distill?, do: Culture.house_view(reference)
    injected_house_view_version = house_view_version(injected_house_view)

    agent_configs =
      build_agent_configs(
        scenario.agents,
        reference,
        model,
        shared_procedure_id,
        memory?,
        memory_window,
        memory_dir,
        if(store?, do: Reference.all(reference), else: nil)
      )

    agents =
      agent_configs
      |> Enum.with_index()
      |> Enum.map(fn {config, index} ->
        Tracefield.Agent.new(config.id, config.domain, config.desc,
          anchor: scenario.task,
          reference_docs: reference_docs,
          private_doc: config.private_doc,
          private_memory: config.private_memory,
          house_view: if(injected_house_view, do: injected_house_view.text, else: ""),
          k_s: k_s,
          adapter: adapter,
          cli: cli,
          model: config.model,
          temperature: temperature,
          seed: 1_000 + index,
          procedure_id: config.procedure_id,
          serve_policy: serve,
          aware: aware?(aware)
        )
      end)

    {agents, main_ideas, perception} =
      Enum.reduce(1..rounds, {agents, [], []}, fn round, {agents, ideas, perception} ->
        {agents, round_ideas, round_perception} = run_round(agents, reference, round)
        {agents, ideas ++ round_ideas, perception ++ round_perception}
      end)

    correction =
      maybe_correct(Keyword.get(opts, :correct), agents, reference, agent_configs, rounds + 1)

    distillation =
      maybe_distill(reference, distill?, distill_mode,
        adapter: adapter,
        model: model,
        temperature: temperature,
        seed: 90_000,
        cli: cli,
        embed_adapter: embed_adapter,
        embed_model: embed_model
      )

    repair_ideas = if correction, do: Map.get(correction, :repair_entries, []), else: []
    repair_perception = if correction, do: Map.get(correction, :perception, []), else: []

    all_entries = Reference.all(reference)
    reference_stats = Reference.stats(reference)
    ideas = entries_for_ids(all_entries, Enum.map(main_ideas ++ repair_ideas, & &1.id))
    procedure_ids = agent_configs |> Enum.map(& &1.procedure_id) |> Enum.reject(&is_nil/1)

    append_memory!(ideas, agent_configs, mode, run_started_at, memory_dir, memory?)

    verification =
      Reference.verify(reference, ideas,
        judge_adapter: adapter,
        judge_model: model,
        temperature: temperature,
        seed: 80_000,
        cli: cli
      )

    concerns_by_agent = concerns_by_agent(ideas)

    raw_metrics =
      Dissolution.measure_concerns(concerns_by_agent,
        adapter: adapter,
        embed_adapter: embed_adapter,
        model: model,
        embed_model: embed_model,
        temperature: temperature,
        seed: 1_000,
        measure_icc: false
      )

    metrics =
      raw_metrics
      |> Map.take([:coverage, :diversity, :collapse_rate])
      |> Map.put(:verification_rate, verification_rate(ideas, verification, procedure_ids))

    synthesis = cross_author_synthesis(ideas, all_entries, procedure_ids, verification)

    result = %{
      task: scenario.task,
      scenario_path: scenario.path,
      config: %{
        mode: mode,
        adapter: adapter_name,
        rounds: rounds,
        serve: serve,
        aware: aware,
        k: k_s,
        model: model,
        embed_model: embed_model,
        temperature: temperature,
        procedure_id: shared_procedure_id,
        procedure_ids: procedure_ids,
        memory: memory?,
        memory_window: memory_window,
        memory_dir: memory_dir,
        store: store_config(store?, store_path, reference_stats),
        distill: distill?,
        distill_mode: distill_mode,
        house_view_injected_version: injected_house_view_version,
        house_view_new_version: distillation_version(distillation),
        agents: plain_agent_configs(agent_configs)
      },
      agents: scenario.agents,
      entries: plain_entries(all_entries),
      ideas: plain_entries(ideas, verification, procedure_ids),
      citation_verification: plain_verification(verification),
      metrics: metrics,
      cross_author_synthesis: synthesis,
      perception: perception ++ repair_perception,
      correction: plain_correction(correction, verification, procedure_ids),
      distillation: plain_distillation(distillation),
      report_path: Keyword.get(opts, :report)
    }

    path =
      if Keyword.get(opts, :persist?, true) do
        persist(result, adapter_name)
      end

    result = Map.put(result, :path, path)

    if report_path = Keyword.get(opts, :report) do
      write_report!(result, report_path)
    end

    result
  end

  def load_scenario!(path, mode \\ :converge) do
    mode = normalize_mode(mode)
    task = File.read!(Path.join(path, "task.md"))

    agents =
      path
      |> Path.join("agents.json")
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&load_agent!(path, &1))

    {procedure, procedure_source} = load_procedure(path, mode)

    %{
      path: path,
      task: task,
      agents: agents,
      docs: load_docs(path),
      procedure: procedure,
      procedure_source: procedure_source
    }
  end

  defp load_docs(path) do
    docs_dir = Path.join(path, "docs")

    if File.dir?(docs_dir) do
      docs_dir
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(fn path ->
        %{file: Path.basename(path), text: File.read!(path)}
      end)
    else
      []
    end
  end

  defp doc_seed_entries(docs) do
    Enum.map(docs, fn doc ->
      %{
        type: :chunk,
        author: "DOCS",
        text: doc.text,
        meta: %{file: doc.file}
      }
    end)
  end

  defp reference_docs(reference) do
    reference
    |> Reference.all()
    |> Enum.filter(&(&1.type == :chunk and &1.author == "DOCS" and &1.status == :active))
    |> Enum.map(fn entry ->
      %{
        id: entry.id,
        file: Map.get(entry.meta, :file, Map.get(entry.meta, "file")),
        text: entry.text
      }
    end)
  end

  def cross_author_synthesis(ideas, all_entries, procedure_ids, verification \\ %{}) do
    by_id = Map.new(all_entries, &{&1.id, &1})
    procedure_ids = procedure_id_set(procedure_ids)

    items =
      ideas
      |> Enum.filter(fn idea ->
        idea.citations
        |> Enum.reject(&MapSet.member?(procedure_ids, &1))
        |> Enum.any?(fn citation ->
          case Map.get(by_id, citation) do
            nil -> false
            %{type: type} when type in [:chunk, :procedure] -> false
            cited -> cited.author != idea.author
          end
        end)
      end)
      |> plain_entries(verification, procedure_ids)

    %{count: length(items), ideas: items}
  end

  defp parse_args(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          scenario: :string,
          adapter: :string,
          rounds: :integer,
          serve: :string,
          aware: :integer,
          k: :integer,
          model: :string,
          embed_model: :string,
          temperature: :float,
          mode: :string,
          correct: :string,
          report: :string,
          memory: :string,
          memory_window: :integer,
          cli_cmd: :string,
          store: :string,
          distill: :string,
          distill_mode: :string
        ],
        aliases: [a: :adapter, m: :model, t: :temperature]
      )

    adapter_name = Keyword.get(opts, :adapter, "mock")
    mode = opts |> Keyword.get(:mode, "converge") |> normalize_mode()
    preset = mode_preset(mode)

    [
      scenario: Keyword.get(opts, :scenario, "scenarios/housing-service"),
      mode: mode,
      adapter_name: adapter_name,
      adapter_module: adapter_module(adapter_name),
      rounds: Keyword.get(opts, :rounds, preset.rounds),
      serve_policy: parse_serve(Keyword.get(opts, :serve, "diverse")),
      aware: Keyword.get(opts, :aware, 1),
      k_s: Keyword.get(opts, :k, preset.k),
      model: Keyword.get(opts, :model),
      embed_model: Keyword.get(opts, :embed_model, "nomic-embed-text"),
      temperature: Keyword.get(opts, :temperature, preset.temperature),
      correct: Keyword.get(opts, :correct),
      report: Keyword.get(opts, :report),
      memory: opts |> Keyword.get(:memory, "true") |> parse_bool(),
      memory_window: Keyword.get(opts, :memory_window, 10),
      cli_cmd: Keyword.get(opts, :cli_cmd),
      store: opts |> Keyword.get(:store, "false") |> parse_bool(),
      distill: opts |> Keyword.get(:distill, "false") |> parse_bool(),
      distill_mode: opts |> Keyword.get(:distill_mode, "extractive") |> normalize_distill_mode()
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp load_agent!(
         scenario_path,
         %{
           "id" => id,
           "domain" => domain,
           "desc" => desc,
           "private_doc" => private_doc_file
         } = agent
       ) do
    private_doc_path = Path.join([scenario_path, "private", private_doc_file])
    procedure_file = Map.get(agent, "procedure")
    procedure_path = if procedure_file, do: Path.join(scenario_path, procedure_file)

    %{
      id: to_string(id),
      domain: to_string(domain),
      desc: to_string(desc),
      private_doc_file: private_doc_file,
      private_doc_path: private_doc_path,
      private_doc: File.read!(private_doc_path),
      model: optional_string(Map.get(agent, "model")),
      procedure_file: procedure_file,
      procedure_path: procedure_path,
      procedure: if(procedure_path, do: File.read!(procedure_path), else: nil)
    }
  end

  defp load_agent!(_scenario_path, agent) do
    Mix.raise("invalid agent entry #{inspect(agent)}")
  end

  defp absorb_procedure(reference, procedure_text) do
    absorb_procedure(reference, procedure_text, %{domain: "procedure"})
  end

  defp absorb_procedure(_reference, nil, _meta), do: nil

  defp absorb_procedure(reference, procedure_text, meta) do
    [procedure] =
      Reference.absorb_idempotent(
        reference,
        [
          %{
            type: :procedure,
            text: procedure_text,
            meta: meta
          }
        ],
        "FACILITATOR"
      )

    procedure.id
  end

  defp build_agent_configs(
         agents,
         reference,
         fallback_model,
         shared_procedure_id,
         memory?,
         memory_window,
         memory_dir,
         store_entries
       ) do
    Enum.map(agents, fn agent ->
      {procedure_id, procedure_source} =
        if agent.procedure do
          id = absorb_procedure(reference, agent.procedure, %{owner: agent.id})
          {id, agent.procedure_file}
        else
          {shared_procedure_id, "shared"}
        end

      {entries, stale} =
        if memory? do
          Memory.load(memory_dir, agent.id, memory_window, store_entries: store_entries)
        else
          {[], 0}
        end

      agent
      |> Map.put(:model, agent.model || fallback_model)
      |> Map.put(:procedure_id, procedure_id)
      |> Map.put(:procedure_source, procedure_source)
      |> Map.put(:memory_loaded, length(entries))
      |> Map.put(:memory_stale, stale)
      |> Map.put(:private_memory, format_private_memory_entries(entries))
    end)
  end

  defp format_private_memory_entries([]), do: ""

  defp format_private_memory_entries(entries) do
    entries
    |> Enum.map_join("\n", fn entry -> "- #{entry.text}" end)
  end

  defp append_memory!(_entries, _agent_configs, _mode, _ts, _memory_dir, false), do: :ok

  defp append_memory!(entries, agent_configs, mode, ts, memory_dir, true) do
    File.mkdir_p!(memory_dir)
    by_author = Enum.group_by(entries, & &1.author)

    Enum.each(agent_configs, fn agent ->
      content =
        by_author
        |> Map.get(agent.id, [])
        |> Enum.map_join("", fn entry ->
          Jason.encode!(%{
            ts: ts,
            mode: Atom.to_string(mode),
            text: entry.text,
            citations: entry.citations
          }) <> "\n"
        end)

      if content != "" do
        File.write!(memory_path(memory_dir, agent.id), content, [:append])
      end
    end)
  end

  defp memory_path(memory_dir, agent_id), do: Path.join(memory_dir, "#{agent_id}.jsonl")

  defp run_round(agents, reference, round, opts \\ []) do
    agents
    |> Enum.reduce({[], [], []}, fn agent, {updated_agents, ideas, perception} ->
      {agent, entries, log} =
        Tracefield.Agent.run_turn(agent, reference, round, Keyword.take(opts, [:note]))

      ideas = ideas ++ Enum.reject(entries, &(&1.type in [:chunk, :procedure]))
      {updated_agents ++ [agent], ideas, perception ++ [log]}
    end)
  end

  defp concerns_by_agent(entries) do
    entries
    |> Enum.group_by(& &1.author, & &1.text)
  end

  defp persist(result, adapter_name) do
    File.mkdir_p!("runs")

    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace("Z", "")

    path = "runs/#{timestamp}-ideate-#{adapter_name}.json"
    File.write!(path, Jason.encode!(GroundTruth.to_plain(result), pretty: true))
    path
  end

  defp print_result(result) do
    Mix.shell().info("Tracefield Ideate")
    Mix.shell().info("scenario: #{result.scenario_path}")
    Mix.shell().info("mode: #{result.config.mode}")
    Mix.shell().info("adapter: #{result.config.adapter}")
    print_store(result.config.store)
    print_house_view_injection(result.config)
    Mix.shell().info("agents: #{format_agent_configs(result.config.agents)}")
    Mix.shell().info("")
    print_reference_documents(result.entries)
    Mix.shell().info("Ideas")

    agent_order =
      result.agents
      |> Enum.with_index()
      |> Map.new(fn {agent, index} -> {agent.id, index} end)

    result.ideas
    |> Enum.group_by(&get_in(&1, [:meta, :round]))
    |> Enum.sort_by(fn {round, _ideas} -> round || 0 end)
    |> Enum.each(fn {round, ideas} ->
      Mix.shell().info("-- Round #{round} --")

      ideas
      |> Enum.sort_by(fn idea ->
        {Map.get(agent_order, idea.author, 999), entry_number(idea.id)}
      end)
      |> Enum.each(fn idea ->
        Mix.shell().info("[#{idea.author}] (cites: #{format_citations(idea)}) #{idea.text}")
      end)

      Mix.shell().info("")
    end)

    Mix.shell().info("Health metrics")
    Mix.shell().info("coverage: #{result.metrics.coverage}")
    Mix.shell().info("diversity: #{fmt(result.metrics.diversity)}")
    Mix.shell().info("collapse_rate: #{fmt(result.metrics.collapse_rate)}")
    Mix.shell().info("verification_rate: #{fmt(result.metrics.verification_rate)}")
    Mix.shell().info("")

    print_correction(result.correction)
    print_distillation(result.distillation)

    Mix.shell().info("Cross-author synthesis")
    Mix.shell().info("count: #{result.cross_author_synthesis.count}")

    Enum.each(result.cross_author_synthesis.ideas, fn idea ->
      Mix.shell().info("[#{idea.author}] (cites: #{format_citations(idea)}) #{idea.text}")
    end)

    if result.report_path do
      Mix.shell().info("")
      Mix.shell().info("report: #{result.report_path}")
    end

    if result.path do
      Mix.shell().info("")
      Mix.shell().info("saved: #{result.path}")
    end
  end

  defp plain_entries(entries, verification \\ %{}, procedure_id \\ nil) do
    Enum.map(entries, fn entry ->
      %{
        id: entry.id,
        type: entry.type,
        author: entry.author,
        version: entry.version,
        status: entry.status,
        text: entry.text,
        citations: entry.citations,
        annotated_citations: annotated_citations(entry, verification, procedure_id),
        citation_verification: citation_verification(entry, verification, procedure_id),
        meta: entry.meta
      }
    end)
  end

  defp load_procedure(path, :review) do
    review_path = Path.join(path, "procedure-review.md")

    cond do
      File.exists?(review_path) -> {File.read!(review_path), review_path}
      true -> {@review_procedure, :built_in_review}
    end
  end

  defp load_procedure(path, _mode) do
    procedure_path = Path.join(path, "procedure.md")

    if File.exists?(procedure_path) do
      {File.read!(procedure_path), procedure_path}
    else
      {nil, nil}
    end
  end

  defp maybe_correct(nil, _agents, _reference, _agent_configs, _repair_round), do: nil

  defp maybe_correct(value, agents, reference, agent_configs, repair_round) do
    target_info = correction_target(value, reference, agent_configs)
    target = target_info.entry

    if is_nil(target) do
      %{skipped: true, reason: "訂正対象なし", closure: [], repair_entries: [], perception: []}
    else
      closure = Reference.retract(reference, target.id)
      quarantined = Reference.quarantine(reference, Enum.map(closure, & &1.id))

      note = correction_note(target_info, target)

      {_agents, repair_entries, perception} =
        run_round(agents, reference, repair_round, note: note)

      %{
        skipped: false,
        target: Reference.get(reference, target.id),
        closure: quarantined,
        closure_ids: Enum.map(quarantined, & &1.id),
        repair_entries: repair_entries,
        perception: perception,
        note: note,
        correction_kind: target_info.kind
      }
    end
  end

  defp correction_target("auto", reference, _agent_configs) do
    %{kind: :entry, entry: Reference.most_cited(reference)}
  end

  defp correction_target("chunk:" <> file, reference, _agent_configs) do
    entry =
      reference
      |> Reference.all()
      |> Enum.find(fn entry ->
        entry.type == :chunk and entry.author == "DOCS" and
          Map.get(entry.meta, :file, Map.get(entry.meta, "file")) == file
      end)

    %{kind: :chunk, file: file, entry: entry}
  end

  defp correction_target("procedure:" <> agent_id, reference, agent_configs) do
    procedure_id =
      agent_configs
      |> Enum.find_value(fn agent ->
        if agent.id == agent_id, do: agent.procedure_id
      end)

    %{
      kind: :procedure,
      agent_id: agent_id,
      entry: if(procedure_id, do: Reference.get(reference, procedure_id))
    }
  end

  defp correction_target(id, reference, _agent_configs) do
    %{kind: :entry, entry: Reference.get(reference, id)}
  end

  defp correction_note(%{kind: :chunk, file: file}, _target) do
    "NOTE: 要件 #{file} が変更され撤回された。新しい前提で代替判断を出せ。"
  end

  defp correction_note(%{kind: :procedure, agent_id: agent_id}, _target) do
    "NOTE: #{agent_id} の手続きに欠陥が見つかり撤回された。"
  end

  defp correction_note(_target_info, target) do
    "NOTE: 直前に entry #{target.id} が誤りと判明し撤回された。それに依存しない代替案を出せ。"
  end

  defp plain_correction(nil, _verification, _procedure_id), do: nil

  defp plain_correction(%{skipped: true} = correction, _verification, _procedure_id) do
    Map.take(correction, [:skipped, :reason])
  end

  defp plain_correction(correction, verification, procedure_id) do
    %{
      skipped: false,
      target: hd(plain_entries([correction.target], verification, procedure_id)),
      closure: plain_entries(correction.closure, verification, procedure_id),
      closure_ids: correction.closure_ids,
      repair_entries: plain_entries(correction.repair_entries, verification, procedure_id),
      note: correction.note
    }
  end

  defp entries_for_ids(entries, ids) do
    by_id = Map.new(entries, &{&1.id, &1})
    Enum.flat_map(ids, fn id -> if entry = Map.get(by_id, id), do: [entry], else: [] end)
  end

  defp verification_rate(ideas, verification, procedure_ids) do
    procedure_ids = procedure_id_set(procedure_ids)

    pairs =
      for idea <- ideas,
          cited_id <- idea.citations,
          not MapSet.member?(procedure_ids, cited_id) do
        {idea.id, cited_id}
      end

    if pairs == [] do
      1.0
    else
      verified = Enum.count(pairs, &Map.get(verification, &1, false))
      verified / length(pairs)
    end
  end

  defp plain_verification(verification) do
    Map.new(verification, fn {{citing_id, cited_id}, verified?} ->
      {"#{citing_id}->#{cited_id}", verified?}
    end)
  end

  defp maybe_distill(_reference, false, _mode, _opts), do: nil

  defp maybe_distill(reference, true, mode, opts) do
    case Culture.distill(reference, Keyword.put(opts, :mode, mode)) do
      {:ok, house_view} ->
        %{
          house_view: house_view,
          transmission: Culture.transmission(reference, house_view.text, opts)
        }

      {:error, reason} ->
        %{error: reason}
    end
  end

  defp plain_distillation(nil), do: nil
  defp plain_distillation(%{error: reason}), do: %{error: reason}

  defp plain_distillation(%{house_view: house_view, transmission: transmission}) do
    %{
      house_view: hd(plain_entries([house_view])),
      transmission: transmission
    }
  end

  defp distillation_version(%{house_view: house_view}), do: house_view_version(house_view)
  defp distillation_version(_distillation), do: nil

  defp annotated_citations(entry, verification, procedure_id) do
    Enum.map(entry.citations, &citation_label(&1, entry.id, verification, procedure_id))
  end

  defp citation_verification(entry, verification, procedure_id) do
    Map.new(entry.citations, fn cited_id ->
      {cited_id, citation_verified?(entry.id, cited_id, verification, procedure_id)}
    end)
  end

  defp citation_label(cited_id, citing_id, verification, procedure_id) do
    mark =
      if citation_verified?(citing_id, cited_id, verification, procedure_id), do: "✓", else: "✗"

    "#{cited_id}#{mark}"
  end

  defp citation_verified?(citing_id, cited_id, verification, procedure_ids) do
    if MapSet.member?(procedure_id_set(procedure_ids), cited_id) do
      true
    else
      Map.get(verification, {citing_id, cited_id}, false)
    end
  end

  defp procedure_id_set(nil), do: MapSet.new()
  defp procedure_id_set(%MapSet{} = ids), do: ids

  defp procedure_id_set(ids) when is_list(ids) do
    ids |> Enum.reject(&is_nil/1) |> MapSet.new()
  end

  defp procedure_id_set(id), do: MapSet.new([id])

  defp optional_string(nil), do: nil
  defp optional_string(value), do: to_string(value)

  defp parse_bool(value), do: normalize_bool(value)

  defp store_config(false, _path, _stats),
    do: %{enabled: false, path: nil, restored: 0, skipped_lines: 0}

  defp store_config(true, path, stats) do
    %{
      enabled: true,
      path: path,
      restored: stats.restored,
      skipped_lines: stats.skipped_lines
    }
  end

  defp cli_config(opts) do
    {Keyword.get(opts, :cli_cmd, "claude"), ["-p"]}
  end

  defp normalize_bool(true), do: true
  defp normalize_bool(false), do: false
  defp normalize_bool("true"), do: true
  defp normalize_bool("false"), do: false
  defp normalize_bool(other), do: Mix.raise("invalid boolean #{inspect(other)}")

  defp normalize_distill_mode(:extractive), do: :extractive
  defp normalize_distill_mode(:llm), do: :llm
  defp normalize_distill_mode("extractive"), do: :extractive
  defp normalize_distill_mode("llm"), do: :llm
  defp normalize_distill_mode(other), do: Mix.raise("invalid distill mode #{inspect(other)}")

  defp plain_agent_configs(agent_configs) do
    Enum.map(agent_configs, fn agent ->
      %{
        id: agent.id,
        domain: agent.domain,
        model: agent.model,
        procedure_id: agent.procedure_id,
        procedure_source: agent.procedure_source,
        memory_loaded: agent.memory_loaded,
        memory_stale: agent.memory_stale
      }
    end)
  end

  defp print_store(%{enabled: true, path: path, restored: restored}) do
    Mix.shell().info("store: #{path}（復元 #{restored} entries／新規）")
  end

  defp print_store(_store), do: :ok

  defp print_house_view_injection(%{distill: true, house_view_injected_version: nil}) do
    Mix.shell().info("house view: なし")
  end

  defp print_house_view_injection(%{distill: true, house_view_injected_version: version}) do
    Mix.shell().info("house view: v#{version} 注入")
  end

  defp print_house_view_injection(_config), do: :ok

  defp print_correction(nil), do: :ok

  defp print_correction(%{skipped: true, reason: reason}) do
    Mix.shell().info("訂正")
    Mix.shell().info(reason)
    Mix.shell().info("")
  end

  defp print_correction(correction) do
    target = correction.target
    closure = correction.closure || []
    repair_entries = correction.repair_entries || []

    Mix.shell().info("訂正")
    Mix.shell().info("訂正: #{target.id}「#{excerpt(target.text)}」を撤回 → 依存 #{length(closure)} 件を隔離")

    Enum.each(closure, fn entry ->
      Mix.shell().info("隔離: #{entry.id} [#{entry.author}] #{entry.text}")
    end)

    Mix.shell().info("修復ラウンドの代替案")

    Enum.each(repair_entries, fn entry ->
      Mix.shell().info("[#{entry.author}] (cites: #{format_citations(entry)}) #{entry.text}")
    end)

    Mix.shell().info("")
  end

  defp print_distillation(nil), do: :ok

  defp print_distillation(%{error: :nothing_to_distill}) do
    Mix.shell().info("蒸留: 対象なし")
    Mix.shell().info("")
  end

  defp print_distillation(%{house_view: house_view, transmission: transmission}) do
    source_ids = source_ids(house_view) |> Enum.join(",")

    Mix.shell().info(
      "蒸留: house view v#{house_view_version(house_view)} を生成（元 entries: #{source_ids}）"
    )

    Mix.shell().info(
      "Culture.transmission: alignment=#{fmt(transmission.alignment)} member_diversity=#{fmt(transmission.member_diversity)} n=#{transmission.n}"
    )

    Mix.shell().info("")
  end

  defp print_reference_documents(entries) do
    docs = Enum.filter(entries, &(&1.type == :chunk and &1.author == "DOCS"))

    if docs != [] do
      Mix.shell().info("REFERENCE DOCUMENTS（設計判断はここを引用せよ）:")

      Enum.each(docs, fn doc ->
        file = Map.get(doc.meta, :file, Map.get(doc.meta, "file", ""))
        Mix.shell().info("DOC #{doc.id} file=#{file}")
        Mix.shell().info(String.trim(doc.text))
      end)

      Mix.shell().info("")
    end
  end

  defp write_report!(result, path) do
    dir = Path.dirname(path)
    if dir not in [".", ""], do: File.mkdir_p!(dir)

    File.write!(path, report_markdown(result))
  end

  defp report_markdown(result) do
    scenario_name = result.scenario_path |> Path.expand() |> Path.basename()

    [
      "# アイデア出しレポート — #{scenario_name}",
      "- 日時: #{DateTime.utc_now() |> DateTime.to_iso8601()}",
      "- mode: #{result.config.mode}",
      "- モデル: #{result.config.model}",
      "- rounds: #{result.config.rounds}",
      "- k: #{result.config.k}",
      "- serve: #{result.config.serve}",
      "- aware: #{result.config.aware}",
      "",
      "## エージェント設定",
      report_agent_configs(result.config.agents),
      "",
      "## タスク",
      String.trim(result.task),
      "",
      "## アイデア（Round 別）",
      report_ideas(result),
      report_correction(result.correction),
      "## 健全性",
      "- coverage: #{result.metrics.coverage}",
      "- diversity: #{fmt(result.metrics.diversity)}",
      "- collapse_rate: #{fmt(result.metrics.collapse_rate)}",
      "- verification_rate: #{fmt(result.metrics.verification_rate)}",
      "",
      "## 領域横断の合成（cross-author）",
      "- #{result.cross_author_synthesis.count} 件",
      report_cross_author(result)
    ]
    |> Enum.reject(&(&1 == nil))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp report_ideas(result) do
    result.ideas
    |> Enum.group_by(&get_in(&1, [:meta, :round]))
    |> Enum.sort_by(fn {round, _ideas} -> round || 0 end)
    |> Enum.map_join("\n", fn {round, ideas} ->
      lines =
        ideas
        |> Enum.sort_by(&entry_number(&1.id))
        |> Enum.map_join("\n", fn idea ->
          "- **[#{idea.author}]** #{idea.text}（引用: #{format_citations(idea)}）"
        end)

      "### Round #{round}\n#{lines}"
    end)
  end

  defp report_agent_configs(agent_configs) do
    Enum.map_join(agent_configs, "\n", fn agent ->
      "- #{agent.id}: model=#{agent.model}, procedure=#{agent.procedure_source}, #{format_memory_count(agent)}"
    end)
  end

  defp report_correction(nil), do: nil

  defp report_correction(%{skipped: true, reason: reason}) do
    "\n## 訂正（--correct 時のみ）\n- #{reason}\n"
  end

  defp report_correction(correction) do
    closure =
      correction.closure
      |> Enum.map_join("\n", fn entry -> "- 隔離: #{entry.id} #{entry.text}" end)

    repairs =
      correction.repair_entries
      |> Enum.map_join("\n", fn entry ->
        "- 代替案: [#{entry.author}] #{entry.text}（引用: #{format_citations(entry)}）"
      end)

    [
      "",
      "## 訂正（--correct 時のみ）",
      "- 撤回: #{correction.target.id} #{correction.target.text}",
      closure,
      repairs,
      ""
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp report_cross_author(result) do
    result.cross_author_synthesis.ideas
    |> Enum.map_join("\n", fn idea ->
      "- **[#{idea.author}]** #{idea.text}（引用: #{format_citations(idea)}）"
    end)
  end

  defp excerpt(text) do
    text = String.trim(to_string(text))
    if String.length(text) > 48, do: String.slice(text, 0, 48) <> "...", else: text
  end

  defp house_view_version(nil), do: nil

  defp house_view_version(entry) do
    entry.meta
    |> Map.get(:house_view_version, Map.get(entry.meta, "house_view_version"))
    |> case do
      version when is_integer(version) ->
        version

      version when is_binary(version) ->
        case Integer.parse(version) do
          {value, ""} -> value
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp source_ids(house_view) do
    predecessor = predecessor_id(house_view)
    Enum.reject(house_view.citations, &(&1 == predecessor))
  end

  defp predecessor_id(house_view) do
    previous_version = house_view_version(house_view) && house_view_version(house_view) - 1

    if previous_version && previous_version > 0 do
      List.last(house_view.citations)
    end
  end

  defp entry_number("e" <> number) do
    case Integer.parse(number) do
      {value, ""} -> value
      _ -> 0
    end
  end

  defp entry_number(_id), do: 0

  defp format_citations(%{annotated_citations: []}), do: "-"
  defp format_citations(%{annotated_citations: citations}), do: Enum.join(citations, ",")

  defp format_agent_configs(agent_configs) do
    Enum.map_join(agent_configs, " ", fn agent ->
      "#{agent.id}(model=#{agent.model}, proc=#{agent.procedure_source}, #{format_memory_count(agent)})"
    end)
  end

  defp format_memory_count(%{memory_loaded: loaded, memory_stale: stale}) when stale > 0 do
    "memory=#{loaded}件（失効#{stale}除外）"
  end

  defp format_memory_count(%{memory_loaded: loaded}), do: "memory=#{loaded}件"

  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)

  defp adapter_module("mock"), do: Tracefield.LLM.Mock
  defp adapter_module("ollama"), do: Tracefield.LLM.Ollama
  defp adapter_module("cli"), do: Tracefield.LLM.CLI
  defp adapter_module(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp adapter(opts, adapter_name) do
    cond do
      Keyword.has_key?(opts, :adapter_module) ->
        Keyword.fetch!(opts, :adapter_module)

      Keyword.get(opts, :adapter) in [
        Tracefield.LLM.Mock,
        Tracefield.LLM.Ollama,
        Tracefield.LLM.CLI
      ] ->
        Keyword.fetch!(opts, :adapter)

      true ->
        adapter_module(adapter_name)
    end
  end

  defp adapter_name(name) when is_binary(name), do: name
  defp adapter_name(Tracefield.LLM.Mock), do: "mock"
  defp adapter_name(Tracefield.LLM.Ollama), do: "ollama"
  defp adapter_name(Tracefield.LLM.CLI), do: "cli"
  defp adapter_name(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp default_embed_adapter(Tracefield.LLM.Mock), do: Tracefield.Embed.Mock
  defp default_embed_adapter(Tracefield.LLM.CLI), do: Tracefield.Embed.Mock
  defp default_embed_adapter(_adapter), do: Tracefield.Embed.Ollama

  defp aware?(true), do: true
  defp aware?(1), do: true
  defp aware?(_value), do: false

  defp parse_serve(value), do: normalize_serve(value)

  defp mode_preset(mode), do: Map.fetch!(@mode_presets, normalize_mode(mode))

  defp normalize_mode(:diverge), do: :diverge
  defp normalize_mode(:converge), do: :converge
  defp normalize_mode(:review), do: :review
  defp normalize_mode("diverge"), do: :diverge
  defp normalize_mode("converge"), do: :converge
  defp normalize_mode("review"), do: :review
  defp normalize_mode(other), do: Mix.raise("invalid mode #{inspect(other)}")

  defp normalize_serve(:similar), do: :similar
  defp normalize_serve(:diverse), do: :diverse
  defp normalize_serve("similar"), do: :similar
  defp normalize_serve("diverse"), do: :diverse
  defp normalize_serve(other), do: Mix.raise("invalid serve value #{inspect(other)}")
end
