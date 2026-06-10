defmodule Mix.Tasks.Tracefield.Ideate do
  @moduledoc "Run Tracefield qualitative ideation over a scenario directory."
  use Mix.Task

  alias Tracefield.{Dissolution, GroundTruth, Reference}

  @shortdoc "Run Tracefield ideation"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    args
    |> parse_args()
    |> run_ideation()
    |> print_result()
  end

  def run_ideation(opts) do
    adapter_name =
      Keyword.get(opts, :adapter_name, adapter_name(Keyword.get(opts, :adapter, "mock")))

    adapter = adapter(opts, adapter_name)
    embed_adapter = Keyword.get(opts, :embed_adapter, default_embed_adapter(adapter))
    scenario_path = Keyword.fetch!(opts, :scenario)
    scenario = Keyword.get_lazy(opts, :loaded_scenario, fn -> load_scenario!(scenario_path) end)
    rounds = Keyword.get(opts, :rounds, 3)

    serve =
      Keyword.get(opts, :serve_policy, Keyword.get(opts, :serve, :diverse)) |> normalize_serve()

    aware = Keyword.get(opts, :aware, 1)
    k_s = Keyword.get(opts, :k_s, Keyword.get(opts, :k, 3))
    temperature = Keyword.get(opts, :temperature, 0.6)

    model =
      Keyword.get(
        opts,
        :model,
        if(adapter == Tracefield.LLM.Mock, do: "mock", else: "gemma4:12b")
      )

    embed_model = Keyword.get(opts, :embed_model, "nomic-embed-text")

    {:ok, reference} =
      Reference.start_link(
        embed_adapter: embed_adapter,
        embed_model: embed_model,
        entries: [
          %{
            type: :chunk,
            author: "TASK",
            text: scenario.task,
            meta: %{domain: "task"}
          }
        ]
      )

    procedure_id = absorb_procedure(reference, scenario.procedure)

    agents =
      scenario.agents
      |> Enum.with_index()
      |> Enum.map(fn {agent, index} ->
        Tracefield.Agent.new(agent.id, agent.domain, agent.desc,
          anchor: scenario.task,
          private_doc: agent.private_doc,
          k_s: k_s,
          adapter: adapter,
          model: model,
          temperature: temperature,
          seed: 1_000 + index,
          procedure_id: procedure_id,
          serve_policy: serve,
          aware: aware?(aware)
        )
      end)

    {_agents, ideas, perception} =
      Enum.reduce(1..rounds, {agents, [], []}, fn round, {agents, ideas, perception} ->
        {agents, round_ideas, round_perception} = run_round(agents, reference, round)
        {agents, ideas ++ round_ideas, perception ++ round_perception}
      end)

    all_entries = Reference.all(reference)
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

    metrics = Map.take(raw_metrics, [:coverage, :diversity, :collapse_rate])
    synthesis = cross_author_synthesis(ideas, all_entries, procedure_id)

    result = %{
      task: scenario.task,
      scenario_path: scenario.path,
      config: %{
        adapter: adapter_name,
        rounds: rounds,
        serve: serve,
        aware: aware,
        k: k_s,
        model: model,
        embed_model: embed_model,
        temperature: temperature,
        procedure_id: procedure_id
      },
      agents: scenario.agents,
      entries: plain_entries(all_entries),
      ideas: plain_entries(ideas),
      metrics: metrics,
      cross_author_synthesis: synthesis,
      perception: perception
    }

    path =
      if Keyword.get(opts, :persist?, true) do
        persist(result, adapter_name)
      end

    Map.put(result, :path, path)
  end

  def load_scenario!(path) do
    task = File.read!(Path.join(path, "task.md"))

    agents =
      path
      |> Path.join("agents.json")
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&load_agent!(path, &1))

    procedure_path = Path.join(path, "procedure.md")
    procedure = if File.exists?(procedure_path), do: File.read!(procedure_path), else: nil

    %{
      path: path,
      task: task,
      agents: agents,
      procedure: procedure
    }
  end

  def cross_author_synthesis(ideas, all_entries, procedure_id) do
    by_id = Map.new(all_entries, &{&1.id, &1})

    items =
      ideas
      |> Enum.filter(fn idea ->
        idea.citations
        |> Enum.reject(&(&1 == procedure_id))
        |> Enum.any?(fn citation ->
          case Map.get(by_id, citation) do
            nil -> false
            %{type: type} when type in [:chunk, :procedure] -> false
            cited -> cited.author != idea.author
          end
        end)
      end)
      |> plain_entries()

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
          temperature: :float
        ],
        aliases: [a: :adapter, m: :model, t: :temperature]
      )

    adapter_name = Keyword.get(opts, :adapter, "mock")

    [
      scenario: Keyword.get(opts, :scenario, "scenarios/housing-service"),
      adapter_name: adapter_name,
      adapter_module: adapter_module(adapter_name),
      rounds: Keyword.get(opts, :rounds, 3),
      serve_policy: parse_serve(Keyword.get(opts, :serve, "diverse")),
      aware: Keyword.get(opts, :aware, 1),
      k_s: Keyword.get(opts, :k, 3),
      model: Keyword.get(opts, :model),
      embed_model: Keyword.get(opts, :embed_model, "nomic-embed-text"),
      temperature: Keyword.get(opts, :temperature, 0.6)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp load_agent!(scenario_path, %{
         "id" => id,
         "domain" => domain,
         "desc" => desc,
         "private_doc" => private_doc_file
       }) do
    private_doc_path = Path.join([scenario_path, "private", private_doc_file])

    %{
      id: to_string(id),
      domain: to_string(domain),
      desc: to_string(desc),
      private_doc_file: private_doc_file,
      private_doc_path: private_doc_path,
      private_doc: File.read!(private_doc_path)
    }
  end

  defp load_agent!(_scenario_path, agent) do
    Mix.raise("invalid agent entry #{inspect(agent)}")
  end

  defp absorb_procedure(_reference, nil), do: nil

  defp absorb_procedure(reference, procedure_text) do
    [procedure] =
      Reference.absorb(
        reference,
        [
          %{
            type: :procedure,
            text: procedure_text,
            meta: %{domain: "procedure"}
          }
        ],
        "FACILITATOR"
      )

    procedure.id
  end

  defp run_round(agents, reference, round) do
    agents
    |> Enum.reduce({[], [], []}, fn agent, {updated_agents, ideas, perception} ->
      {agent, entries, log} = Tracefield.Agent.run_turn(agent, reference, round)
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
    Mix.shell().info("adapter: #{result.config.adapter}")
    Mix.shell().info("")
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
        Mix.shell().info(
          "[#{idea.author}] (cites: #{format_citations(idea.citations)}) #{idea.text}"
        )
      end)

      Mix.shell().info("")
    end)

    Mix.shell().info("Health metrics")
    Mix.shell().info("coverage: #{result.metrics.coverage}")
    Mix.shell().info("diversity: #{fmt(result.metrics.diversity)}")
    Mix.shell().info("collapse_rate: #{fmt(result.metrics.collapse_rate)}")
    Mix.shell().info("")
    Mix.shell().info("Cross-author synthesis")
    Mix.shell().info("count: #{result.cross_author_synthesis.count}")

    Enum.each(result.cross_author_synthesis.ideas, fn idea ->
      Mix.shell().info(
        "[#{idea.author}] (cites: #{format_citations(idea.citations)}) #{idea.text}"
      )
    end)

    if result.path do
      Mix.shell().info("")
      Mix.shell().info("saved: #{result.path}")
    end
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

  defp entry_number("e" <> number) do
    case Integer.parse(number) do
      {value, ""} -> value
      _ -> 0
    end
  end

  defp entry_number(_id), do: 0

  defp format_citations([]), do: "-"
  defp format_citations(citations), do: Enum.join(citations, ",")

  defp fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 4)

  defp adapter_module("mock"), do: Tracefield.LLM.Mock
  defp adapter_module("ollama"), do: Tracefield.LLM.Ollama
  defp adapter_module(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp adapter(opts, adapter_name) do
    cond do
      Keyword.has_key?(opts, :adapter_module) ->
        Keyword.fetch!(opts, :adapter_module)

      Keyword.get(opts, :adapter) in [Tracefield.LLM.Mock, Tracefield.LLM.Ollama] ->
        Keyword.fetch!(opts, :adapter)

      true ->
        adapter_module(adapter_name)
    end
  end

  defp adapter_name(name) when is_binary(name), do: name
  defp adapter_name(Tracefield.LLM.Mock), do: "mock"
  defp adapter_name(Tracefield.LLM.Ollama), do: "ollama"
  defp adapter_name(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp default_embed_adapter(Tracefield.LLM.Mock), do: Tracefield.Embed.Mock
  defp default_embed_adapter(_adapter), do: Tracefield.Embed.Ollama

  defp aware?(true), do: true
  defp aware?(1), do: true
  defp aware?(_value), do: false

  defp parse_serve(value), do: normalize_serve(value)

  defp normalize_serve(:similar), do: :similar
  defp normalize_serve(:diverse), do: :diverse
  defp normalize_serve("similar"), do: :similar
  defp normalize_serve("diverse"), do: :diverse
  defp normalize_serve(other), do: Mix.raise("invalid serve value #{inspect(other)}")
end
