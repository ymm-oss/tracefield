defmodule Tracefield.Dissolution do
  @moduledoc """
  Dissolution-depth experiment runner and within-run measurement.
  """

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

  @common_instruction_x "自分の偏りを保ちつつ、まだカバーされていない観点・領域をまたぐ相互作用を埋めよ"
  @json_instruction "Return only JSON shaped as {\"notes\":\"思考\",\"concerns\":[\"...\",\"...\"]}. concerns must contain at most 2 items."
  @team_identity "TEAM IDENTITY: あなたはチームそのものである。単一の統合見解として続けよ"
  @dedup_threshold 0.85
  @collapse_threshold 0.9

  def domains, do: @domains
  def default_agents, do: @default_agents
  def common_instruction_x, do: @common_instruction_x

  def run(%Tracefield.Scenario{} = scenario, regime, opts \\ []) do
    regime = normalize_regime!(regime)
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Mock)
    model = Keyword.get(opts, :model, "mock")
    temperature = Keyword.get(opts, :temperature, 0.4)
    seed = Keyword.get(opts, :seed, 0)
    rounds = Keyword.get(opts, :rounds, 2)
    agents = Keyword.get(opts, :agents, @default_agents) |> Enum.map(&normalize_agent/1)

    {turns, _published} =
      Enum.reduce(1..rounds, {[], []}, fn round, acc ->
        Enum.with_index(agents, 1)
        |> Enum.reduce(acc, fn {agent, agent_index}, {history, published} ->
          messages = build_messages(regime, agent, history, published, scenario.task, round)

          llm_opts = [
            adapter: adapter,
            model: model,
            temperature: temperature,
            seed: seed + round * 100 + agent_index
          ]

          {raw_output, notes, concerns} =
            case Tracefield.LLM.complete(messages, llm_opts) do
              {:ok, content} ->
                {notes, concerns} = parse_turn(content)
                {content, notes, concerns}

              {:error, _reason} ->
                {~s({"notes":"","concerns":[]}), "", []}
            end

          concerns = Enum.take(concerns, 2)

          turn = %{
            agent: agent.id,
            domain: agent.domain,
            round: round,
            notes: notes,
            concerns: concerns,
            raw_output: raw_output
          }

          published =
            published ++
              Enum.map(concerns, fn concern ->
                %{agent: agent.id, domain: agent.domain, text: concern}
              end)

          {history ++ [turn], published}
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

  def build_messages(regime, agent, history, published, task, round) do
    regime = normalize_regime!(regime)
    agent = normalize_agent(agent)
    history = List.wrap(history)
    published = List.wrap(published)

    system = %{role: "system", content: system_message(regime, agent)}
    assistants = assistant_history(regime, agent, history)
    user = %{role: "user", content: user_message(regime, agent, published, task, round)}

    [system] ++ assistants ++ [user]
  end

  def build_context(:closed, _workspace, published), do: format_published(published, nil)
  def build_context(:semi, workspace, _published), do: format_context(workspace)
  def build_context(:merged, workspace, _published), do: format_context(workspace)

  def build_context(regime, workspace, published) when is_binary(regime) do
    build_context(normalize_regime!(regime), workspace, published)
  end

  def instruction(regime, agent) do
    agent = normalize_agent(agent)

    case normalize_regime!(regime) do
      regime when regime in [:closed, :semi] ->
        "#{persona(agent)}\n#{@common_instruction_x}"

      :merged ->
        @team_identity
    end
  end

  def measure(%{} = run, opts \\ []) do
    opts = Keyword.put_new(opts, :seed, Map.get(run, :seed, 0))

    run
    |> Map.get(:concerns_by_agent, %{})
    |> measure_concerns(opts)
    |> Map.merge(%{
      regime: Map.get(run, :regime),
      seed: Map.get(run, :seed),
      concerns_by_agent: Map.get(run, :concerns_by_agent, %{})
    })
  end

  def measure_concerns(concerns_by_agent, opts \\ []) when is_map(concerns_by_agent) do
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Mock)
    model = Keyword.get(opts, :model, "mock")
    temperature = Keyword.get(opts, :temperature, 0.4)
    seed = Keyword.get(opts, :seed, 0)
    embed_adapter = Keyword.get(opts, :embed_adapter, default_embed_adapter(adapter))
    embed_model = Keyword.get(opts, :embed_model, "nomic-embed-text")
    judge_adapter = Keyword.get(opts, :judge_adapter, adapter)
    judge_model = Keyword.get(opts, :judge_model, model)

    refs = concern_refs(concerns_by_agent)

    embedded_refs =
      refs
      |> Enum.map(& &1.text)
      |> embed_all(adapter: embed_adapter, model: embed_model)
      |> then(fn vectors ->
        Enum.zip_with(refs, vectors, fn ref, vector -> Map.put(ref, :embedding, vector) end)
      end)

    {representatives, assignments} = dedup(embedded_refs)

    judgments =
      judge_interstitial(representatives,
        adapter: judge_adapter,
        model: judge_model,
        temperature: temperature,
        seed: seed + 60_000
      )

    %{
      coverage: length(representatives),
      diversity: diversity(embedded_refs),
      collapse_rate: collapse_rate(embedded_refs),
      icc: Enum.count(judgments, fn {_ref, judgment} -> judgment.interstitial end),
      representatives: Enum.map(representatives, &Map.take(&1, [:ref, :agent, :text])),
      assignments: assignments,
      interstitial: judgments
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

  def parse_interstitial(content, refs) when is_binary(content) and is_list(refs) do
    indexes_to_refs =
      refs
      |> Enum.with_index(1)
      |> Map.new(fn {%{ref: ref}, index} -> {Integer.to_string(index), ref} end)

    with {:ok, %{} = decoded} <- decode_json_object(content) do
      Map.new(indexes_to_refs, fn {index, ref} ->
        value = Map.get(decoded, index, Map.get(decoded, String.to_integer(index), %{}))
        {ref, normalize_interstitial(value)}
      end)
    else
      _ -> Map.new(refs, &{&1.ref, %{interstitial: false, pair: []}})
    end
  end

  def parse_interstitial(_content, refs),
    do: Map.new(refs, &{&1.ref, %{interstitial: false, pair: []}})

  defp system_message(:closed, agent) do
    Enum.join(
      ["TRACEFIELD_DISSOLUTION", persona(agent), @common_instruction_x, @json_instruction],
      "\n"
    )
  end

  defp system_message(:semi, agent) do
    Enum.join(
      [
        "TRACEFIELD_DISSOLUTION",
        persona(agent),
        @common_instruction_x,
        "BIAS ANCHOR: あなたの優先軸は#{agent.domain}。これを保て",
        @json_instruction
      ],
      "\n"
    )
  end

  defp system_message(:merged, _agent) do
    Enum.join(["TRACEFIELD_DISSOLUTION", @team_identity, @json_instruction], "\n")
  end

  defp persona(agent), do: "あなたは #{agent.id}（#{agent.desc}）。"

  defp assistant_history(:closed, agent, history) do
    history
    |> Enum.filter(&(turn_agent(&1) == agent.id))
    |> Enum.map(fn turn -> %{role: "assistant", content: raw_turn(turn)} end)
  end

  defp assistant_history(regime, _agent, history) when regime in [:semi, :merged] do
    Enum.map(history, fn turn ->
      %{role: "assistant", content: "[#{turn_agent(turn)}] #{raw_turn(turn)}"}
    end)
  end

  defp user_message(:closed, agent, published, task, round) do
    """
    TASK:
    #{task}

    PUBLISHED CONCERNS FROM OTHER AGENTS:
    #{format_published(published, agent.id)}

    ROUND #{round}
    AGENT #{agent.id}
    Add concerns.
    """
    |> String.trim()
  end

  defp user_message(regime, agent, _published, task, round) when regime in [:semi, :merged] do
    """
    TASK:
    #{task}

    ROUND #{round}
    AGENT #{agent.id}
    Add concerns.
    """
    |> String.trim()
  end

  defp raw_turn(%{raw_output: raw_output}) when is_binary(raw_output), do: raw_output
  defp raw_turn(%{"raw_output" => raw_output}) when is_binary(raw_output), do: raw_output

  defp raw_turn(turn) do
    Jason.encode!(%{
      notes: Map.get(turn, :notes, Map.get(turn, "notes", "")),
      concerns: Map.get(turn, :concerns, Map.get(turn, "concerns", []))
    })
  end

  defp turn_agent(turn), do: to_string(Map.get(turn, :agent, Map.get(turn, "agent", "")))

  defp format_published([], _agent_id), do: "(none)"

  defp format_published(published, agent_id) do
    published
    |> Enum.reject(fn item -> agent_id != nil and published_agent(item) == agent_id end)
    |> Enum.map(fn item -> "> [#{published_agent(item)}] #{published_text(item)}" end)
    |> case do
      [] -> "(none)"
      lines -> Enum.join(lines, "\n")
    end
  end

  defp published_agent(%{agent: agent}), do: to_string(agent)
  defp published_agent(%{"agent" => agent}), do: to_string(agent)

  defp published_agent(text) when is_binary(text) do
    case Regex.named_captures(~r/^\[(?<agent>[^\]]+)\]/, text) do
      %{"agent" => agent} -> agent
      _ -> "unknown"
    end
  end

  defp published_agent(_item), do: "unknown"

  defp published_text(%{text: text}) when is_binary(text), do: text
  defp published_text(%{"text" => text}) when is_binary(text), do: text
  defp published_text(text) when is_binary(text), do: text
  defp published_text(item), do: inspect(item)

  defp embed_all([], _opts), do: []

  defp embed_all(texts, opts) do
    case Tracefield.Embed.embed(texts, opts) do
      {:ok, vectors} -> vectors
      {:error, _reason} -> Enum.map(texts, fn _text -> List.duplicate(0.0, 32) end)
    end
  end

  defp dedup(refs) do
    {representatives, assignments} =
      Enum.reduce(refs, {[], %{}}, fn ref, {representatives, assignments} ->
        duplicate =
          Enum.find(representatives, fn representative ->
            Tracefield.Embed.cosine(ref.embedding, representative.embedding) >= @dedup_threshold
          end)

        case duplicate do
          nil ->
            {representatives ++ [ref], Map.put(assignments, ref.ref, ref.ref)}

          representative ->
            {representatives, Map.put(assignments, ref.ref, representative.ref)}
        end
      end)

    {representatives, assignments}
  end

  defp diversity(refs) do
    refs_by_agent = Enum.group_by(refs, & &1.agent)

    distances =
      for {agent_a, refs_a} <- refs_by_agent,
          {agent_b, refs_b} <- refs_by_agent,
          agent_a < agent_b,
          refs_a != [],
          refs_b != [] do
        (1.0 - sym_mean_max_cos(refs_a, refs_b))
        |> zero_near_zero()
      end

    mean(distances)
  end

  defp sym_mean_max_cos(refs_a, refs_b) do
    (mean_max_cos(refs_a, refs_b) + mean_max_cos(refs_b, refs_a)) / 2.0
  end

  defp mean_max_cos(source, target) do
    source
    |> Enum.map(fn ref ->
      target
      |> Enum.map(&Tracefield.Embed.cosine(ref.embedding, &1.embedding))
      |> Enum.max(fn -> 0.0 end)
    end)
    |> mean()
  end

  defp collapse_rate(refs) do
    refs_by_agent = Enum.group_by(refs, & &1.agent)

    collapsed =
      refs_by_agent
      |> Enum.flat_map(fn {agent, agent_refs} ->
        other_refs =
          refs_by_agent
          |> Enum.reject(fn {other_agent, _refs} -> other_agent == agent end)
          |> Enum.flat_map(fn {_other_agent, refs} -> refs end)

        Enum.map(agent_refs, fn ref ->
          other_refs
          |> Enum.map(&Tracefield.Embed.cosine(ref.embedding, &1.embedding))
          |> Enum.max(fn -> 0.0 end)
          |> Kernel.>(@collapse_threshold)
        end)
      end)

    if collapsed == [] do
      0.0
    else
      Enum.count(collapsed, & &1) / length(collapsed)
    end
  end

  defp judge_interstitial([], _opts), do: %{}

  defp judge_interstitial(refs, opts) do
    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_INTERSTITIAL\n各懸念について、taxonomy {security, legal-consent, ux, business-speed, data-quality, ops-org} のうち2領域の相互作用そのものが主題か（両領域を同時に考えて初めて成立する懸念か）を判定。単一領域の懸念が他領域に言及しただけなら false。JSONのみ {\"1\":{\"interstitial\":true,\"pair\":[\"security\",\"legal-consent\"]},...}"
      },
      %{
        role: "user",
        content:
          "CONCERNS:\n" <>
            (refs
             |> Enum.with_index(1)
             |> Enum.map_join("\n", fn {%{text: text}, index} -> "#{index}. #{text}" end))
      }
    ]

    case Tracefield.LLM.complete(messages, opts) do
      {:ok, content} -> parse_interstitial(content, refs)
      {:error, _reason} -> Map.new(refs, &{&1.ref, %{interstitial: false, pair: []}})
    end
  end

  defp normalize_interstitial(%{} = value) do
    interstitial = value["interstitial"] || value[:interstitial] || false
    pair = normalize_pair(value["pair"] || value[:pair] || [])
    %{interstitial: interstitial == true, pair: pair}
  end

  defp normalize_interstitial(_value), do: %{interstitial: false, pair: []}

  defp normalize_pair(pair) when is_list(pair) do
    pair
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @domains))
    |> Enum.uniq()
    |> Enum.take(2)
  end

  defp normalize_pair(_pair), do: []

  defp concern_refs(concerns_by_agent) do
    concerns_by_agent
    |> Enum.flat_map(fn {agent, concerns} ->
      concerns
      |> Enum.with_index(1)
      |> Enum.map(fn {text, index} ->
        %{ref: "#{agent}|#{index}", agent: to_string(agent), text: text}
      end)
    end)
  end

  defp default_embed_adapter(Tracefield.LLM.Mock), do: Tracefield.Embed.Mock
  defp default_embed_adapter(_adapter), do: Tracefield.Embed.Ollama

  defp mean([]), do: 0.0
  defp mean(values), do: Enum.sum(values) / length(values)

  defp zero_near_zero(value) when abs(value) < 1.0e-12, do: 0.0
  defp zero_near_zero(value), do: value

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
