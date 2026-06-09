defmodule Tracefield.Dissolution do
  @moduledoc """
  Dissolution-depth experiment runner and within-run measurement.
  """

  alias Tracefield.Normalize

  @domains [
    "security",
    "legal-consent",
    "ux",
    "business-speed",
    "data-quality",
    "ops-org"
  ]

  @default_agents [
    %{
      id: "SEC",
      domain: "security",
      desc: "セキュリティ・権限・情報漏洩を最優先する"
    },
    %{
      id: "BIZ",
      domain: "business-speed",
      desc: "事業速度・意思決定効率・ROIを最優先する"
    },
    %{
      id: "UX",
      domain: "ux",
      desc: "UX・ユーザーの誤用・説明責任を最優先する"
    }
  ]

  def domains, do: @domains
  def default_agents, do: @default_agents

  def run(%Tracefield.Scenario{} = scenario, regime, opts \\ []) do
    regime = normalize_regime!(regime)
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Mock)
    model = Keyword.get(opts, :model, "mock")
    temperature = Keyword.get(opts, :temperature, 0.4)
    seed = Keyword.get(opts, :seed, 0)
    rounds = Keyword.get(opts, :rounds, 2)
    agents = Keyword.get(opts, :agents, @default_agents) |> Enum.map(&normalize_agent/1)

    {turns, _workspace, _published} =
      Enum.reduce(1..rounds, {[], [], []}, fn round, acc ->
        Enum.with_index(agents, 1)
        |> Enum.reduce(acc, fn {agent, agent_index}, {turns, workspace, published} ->
          context = build_context(regime, workspace, published)

          messages = [
            %{
              role: "system",
              content:
                "TRACEFIELD_DISSOLUTION\n#{instruction(regime, agent)}\nReturn only JSON shaped as {\"notes\":\"思考\",\"concerns\":[\"...\",\"...\"]}. concerns must contain at most 2 items."
            },
            %{
              role: "user",
              content:
                "TASK:\n#{scenario.task}\n\n#{context_header(regime)}:\n#{context}\n\nROUND #{round}\nAGENT #{agent.id}\nAdd concerns."
            }
          ]

          llm_opts = [
            adapter: adapter,
            model: model,
            temperature: temperature,
            seed: seed + round * 100 + agent_index
          ]

          {notes, concerns} =
            case Tracefield.LLM.complete(messages, llm_opts) do
              {:ok, content} -> parse_turn(content)
              {:error, _reason} -> {"", []}
            end

          concerns = Enum.take(concerns, 2)

          turn = %{
            agent: agent.id,
            domain: agent.domain,
            round: round,
            notes: notes,
            concerns: concerns
          }

          workspace =
            workspace ++
              ["[#{agent.id} notes] #{notes}"] ++
              Enum.map(concerns, &"[#{agent.id} concern] #{&1}")

          published = published ++ Enum.map(concerns, &"[#{agent.id}] #{&1}")

          {turns ++ [turn], workspace, published}
        end)
      end)

    concerns_by_agent =
      agents
      |> Map.new(fn agent ->
        concerns =
          turns
          |> Enum.filter(&(&1.agent == agent.id))
          |> Enum.flat_map(& &1.concerns)

        {agent.id, concerns}
      end)

    %{
      regime: regime,
      seed: seed,
      turns: turns,
      concerns_by_agent: concerns_by_agent,
      agents: agents
    }
  end

  def build_context(:closed, _workspace, published), do: format_context(published)
  def build_context(:semi, workspace, _published), do: format_context(workspace)
  def build_context(:merged, workspace, _published), do: format_context(workspace)

  def build_context(regime, workspace, published) when is_binary(regime) do
    build_context(normalize_regime!(regime), workspace, published)
  end

  def instruction(regime, agent) do
    agent = normalize_agent(agent)

    case normalize_regime!(regime) do
      regime when regime in [:closed, :semi] ->
        "あなたは #{agent.id}（#{agent.desc}）。自分の偏りを保ちつつ、まだカバーされていない観点・領域をまたぐ相互作用を埋めよ"

      :merged ->
        "あなたは #{agent.id}（#{agent.desc}）。自分の専門の偏りに固執せず、チームの単一の統合見解に収束せよ"
    end
  end

  def measure(%{} = run, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Mock)
    model = Keyword.get(opts, :model, "mock")
    temperature = Keyword.get(opts, :temperature, 0.4)
    seed = Keyword.get(opts, :seed, Map.get(run, :seed, 0))

    concern_refs = concern_refs(run)

    clusters =
      Normalize.cluster(concern_refs,
        adapter: adapter,
        model: model,
        temperature: temperature,
        seed: seed + 50_000
      )

    tags =
      concern_refs
      |> domain_tags(
        adapter: adapter,
        model: model,
        temperature: temperature,
        seed: seed + 60_000
      )

    concerns_by_agent = Map.get(run, :concerns_by_agent, %{})
    agent_domains = agent_domains(run)
    clusters_by_agent = clusters_by_agent(concerns_by_agent, clusters)

    %{
      regime: Map.get(run, :regime),
      seed: Map.get(run, :seed),
      coverage: clusters |> Map.values() |> MapSet.new() |> MapSet.size(),
      diversity: diversity(clusters_by_agent),
      icc: icc(clusters, tags),
      bias_retention: bias_retention(concerns_by_agent, agent_domains, tags),
      clusters: clusters,
      tags: tags,
      concerns_by_agent: concerns_by_agent
    }
  end

  def parse_turn(content) when is_binary(content) do
    with {:ok, %{} = decoded} <- decode_json_object(content) do
      notes = decoded["notes"] || decoded[:notes] || ""
      raw_concerns = decoded["concerns"] || decoded[:concerns] || []

      concerns =
        raw_concerns
        |> List.wrap()
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {normalize_notes(notes), concerns}
    else
      _ -> {"", []}
    end
  end

  def parse_turn(_content), do: {"", []}

  def parse_domain_tags(content, refs) when is_binary(content) and is_list(refs) do
    indexes_to_refs =
      refs
      |> Enum.with_index(1)
      |> Map.new(fn {%{ref: ref}, index} -> {Integer.to_string(index), ref} end)

    with {:ok, %{} = decoded} <- decode_json_object(content) do
      Map.new(indexes_to_refs, fn {index, ref} ->
        domains =
          decoded
          |> Map.get(index, Map.get(decoded, String.to_integer(index), []))
          |> normalize_domains()

        {ref, domains}
      end)
    else
      _ -> Map.new(refs, &{&1.ref, []})
    end
  end

  def parse_domain_tags(_content, refs), do: Map.new(refs, &{&1.ref, []})

  defp domain_tags([], _opts), do: %{}

  defp domain_tags(refs, opts) do
    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_DOMAINS. Tag each numbered concern with 1 to 3 domains from this fixed taxonomy: #{Enum.join(@domains, ", ")}. Return only JSON shaped as {\"1\":[\"security\",\"legal-consent\"]}."
      },
      %{
        role: "user",
        content:
          "CONCERNS:\n" <>
            (refs
             |> Enum.with_index(1)
             |> Enum.map_join("\n", fn {%{text: text}, index} ->
               "#{index}. #{text}"
             end))
      }
    ]

    case Tracefield.LLM.complete(messages, opts) do
      {:ok, content} -> parse_domain_tags(content, refs)
      {:error, _reason} -> Map.new(refs, &{&1.ref, []})
    end
  end

  defp concern_refs(run) do
    run
    |> Map.get(:concerns_by_agent, %{})
    |> Enum.flat_map(fn {agent, concerns} ->
      concerns
      |> Enum.with_index(1)
      |> Enum.map(fn {text, index} -> %{ref: "#{agent}|#{index}", text: text} end)
    end)
  end

  defp clusters_by_agent(concerns_by_agent, clusters) do
    Map.new(concerns_by_agent, fn {agent, concerns} ->
      cluster_set =
        concerns
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {_text, index} ->
          case Map.fetch(clusters, "#{agent}|#{index}") do
            {:ok, cluster} -> [cluster]
            :error -> []
          end
        end)
        |> MapSet.new()

      {agent, cluster_set}
    end)
  end

  defp diversity(clusters_by_agent) when map_size(clusters_by_agent) <= 1, do: 0.0

  defp diversity(clusters_by_agent) do
    sets = Map.values(clusters_by_agent)

    pairs =
      for {a, index_a} <- Enum.with_index(sets),
          {b, index_b} <- Enum.with_index(sets),
          index_a < index_b,
          do: Normalize.diff(a, b)

    if pairs == [], do: 0.0, else: Enum.sum(pairs) / length(pairs)
  end

  defp icc(clusters, tags) do
    clusters
    |> Enum.group_by(fn {_ref, cluster} -> cluster end, fn {ref, _cluster} -> ref end)
    |> Enum.count(fn {_cluster, refs} ->
      interstitial = Enum.count(refs, fn ref -> length(Map.get(tags, ref, [])) >= 2 end)
      interstitial > length(refs) / 2
    end)
  end

  defp bias_retention(concerns_by_agent, agent_domains, tags) do
    retentions =
      concerns_by_agent
      |> Enum.map(fn {agent, concerns} ->
        domain = Map.get(agent_domains, agent)

        if domain == nil or concerns == [] do
          0.0
        else
          retained =
            concerns
            |> Enum.with_index(1)
            |> Enum.count(fn {_text, index} ->
              tags
              |> Map.get("#{agent}|#{index}", [])
              |> Enum.member?(domain)
            end)

          retained / length(concerns)
        end
      end)

    if retentions == [], do: 0.0, else: Enum.sum(retentions) / length(retentions)
  end

  defp agent_domains(run) do
    run
    |> Map.get(:agents, @default_agents)
    |> Map.new(fn agent ->
      agent = normalize_agent(agent)
      {agent.id, agent.domain}
    end)
  end

  defp normalize_domains(domains) when is_list(domains) do
    domains
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @domains))
    |> Enum.uniq()
    |> Enum.take(3)
  end

  defp normalize_domains(_domains), do: []

  defp normalize_notes(notes) when is_binary(notes), do: notes
  defp normalize_notes(notes) when is_number(notes) or is_boolean(notes), do: to_string(notes)
  defp normalize_notes(_notes), do: ""

  defp normalize_agent(%{id: id, domain: domain, desc: desc}) do
    %{id: to_string(id), domain: to_string(domain), desc: to_string(desc)}
  end

  defp normalize_agent(%{"id" => id, "domain" => domain, "desc" => desc}) do
    %{id: to_string(id), domain: to_string(domain), desc: to_string(desc)}
  end

  defp normalize_regime!(regime) when regime in [:closed, :semi, :merged], do: regime
  defp normalize_regime!("closed"), do: :closed
  defp normalize_regime!("semi"), do: :semi
  defp normalize_regime!("merged"), do: :merged

  defp normalize_regime!(regime) do
    raise ArgumentError, "unknown dissolution regime #{inspect(regime)}"
  end

  defp context_header(:closed), do: "PUBLISHED CONCERNS"
  defp context_header(_regime), do: "WORKSPACE NOTES AND CONCERNS"

  defp format_context([]), do: "(empty)"
  defp format_context(context) when is_list(context), do: Enum.join(context, "\n")
  defp format_context(context) when is_binary(context), do: context

  defp decode_json_object(content) do
    with {:error, _reason} <- Jason.decode(content),
         {:ok, object_text} <- extract_object_text(content) do
      Jason.decode(object_text)
    end
  end

  defp extract_object_text(content) do
    start = :binary.match(content, "{")

    finish =
      content
      |> String.reverse()
      |> :binary.match("}")

    case {start, finish} do
      {{start_index, 1}, {reverse_index, 1}} ->
        end_index = byte_size(content) - reverse_index - 1

        if end_index >= start_index do
          {:ok, binary_part(content, start_index, end_index - start_index + 1)}
        else
          :error
        end

      _ ->
        :error
    end
  end
end
