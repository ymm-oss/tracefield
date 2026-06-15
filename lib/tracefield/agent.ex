defmodule Tracefield.Agent do
  @moduledoc """
  Facade for a Tracefield agent backed by Jido core state.
  """

  defstruct [:core]

  defmodule Core do
    @moduledoc false

    use Jido.Agent,
      name: "tracefield_agent",
      description: "Tracefield shared-state agent",
      default_plugins: false,
      schema: [
        id: [type: :string, required: true],
        domain: [type: :string, required: true],
        desc: [type: :string, required: true],
        anchor: [type: :string, default: ""],
        reference_docs: [type: :any, default: []],
        private_doc: [type: :string, default: ""],
        private_memory: [type: :string, default: ""],
        house_view: [type: :string, default: ""],
        k_s: [type: :integer, default: 2],
        adapter: [type: :any, default: Tracefield.LLM.Mock],
        cli: [type: :any, default: nil],
        model: [type: :string, default: "mock"],
        temperature: [type: :float, default: 0.4],
        human: [type: :any, default: nil],
        seed: [type: :integer, default: 0],
        num_ctx: [type: :integer, default: 8192],
        k_docs: [type: :integer, default: 3],
        procedure_id: [type: :string, default: nil],
        recruit_id: [type: :string, default: nil],
        aware: [type: :boolean, default: false],
        serve_policy: [type: :any, default: :similar],
        entry_limit: [type: :integer, default: 2],
        expected_types: [type: :any, default: nil],
        territory: [type: :any, default: nil],
        exclude_machine_authors: [type: :any, default: nil],
        sharing_stage: [type: :string, default: nil],
        patrol: [type: :any, default: %{enabled: true, token_threshold: 100_000}],
        last_round: [type: :integer, default: 0],
        absorbed_count: [type: :integer, default: 0],
        last_absorbed: [type: :any, default: []],
        last_perception: [type: :any, default: nil],
        perception_log: [type: :any, default: []]
      ]
  end

  defmodule RunTurn do
    @moduledoc false

    use Jido.Action,
      name: "tracefield_agent_run_turn",
      description: "Run one Tracefield agent shared-state turn",
      schema: [
        reference: [type: :any, required: true],
        round: [type: :integer, required: true],
        note: [type: :string, default: ""]
      ]

    @num_predict 1200
    @budget_margin 512

    @impl true
    def run(%{reference: reference, round: round} = params, %{state: state}) do
      state = %{state | reference_docs: active_reference_docs(reference, state.reference_docs)}
      note = Map.get(params, :note, "")
      query_text = query(state)

      served =
        Tracefield.Reference.serve(reference, query_text,
          k: max(state.k_s, 0),
          exclude_author: state.id,
          exclude_types: [:procedure, :territory_contract],
          policy: state.serve_policy
        )

      {retrieved, sharing_meta} = apply_sharing_filter(served, state, round)

      procedure = procedure_entry(reference, state.procedure_id)
      presented_ids = MapSet.new(Enum.map(retrieved, & &1.id))
      reference_doc_ids = MapSet.new(Enum.map(state.reference_docs, &doc_id/1))
      prompt = build_prompt(reference, state, round, retrieved, procedure, note, query_text)
      perception = perception_log(query_text, retrieved, prompt, sharing_meta)

      entries =
        prompt.messages
        |> deliberate(state, round)
        |> Enum.take(state.entry_limit)
        |> Enum.map(
          &sanitize_entry(&1, presented_ids, reference_doc_ids, state, round, procedure,
            territory_contract_id: territory_contract_id(state)
          )
        )
        |> Enum.reject(&(&1.text == ""))

      absorbed = Tracefield.Reference.absorb(reference, entries, state.id)

      {:ok,
       %{
         last_round: round,
         absorbed_count: state.absorbed_count + length(absorbed),
         last_absorbed: absorbed,
         last_perception: perception,
         perception_log: state.perception_log ++ [perception]
       }}
    end

    defp query(state), do: Enum.join([state.anchor, state.domain], "\n")

    defp active_reference_docs(reference, fallback_docs) do
      entries = Tracefield.Reference.all(reference)

      docs =
        entries
        |> Enum.filter(
          &(&1.type == :chunk and &1.author in ["ISSUE", "DOCS"] and &1.status == :active)
        )
        |> Enum.map(fn entry ->
          %{
            id: entry.id,
            file: Map.get(entry.meta, :file, Map.get(entry.meta, "file")),
            text: entry.text
          }
        end)

      by_id = Map.new(entries, &{&1.id, &1})
      chunk_ids = MapSet.new(Enum.map(docs, & &1.id))

      extra =
        fallback_docs
        |> List.wrap()
        |> Enum.reject(&MapSet.member?(chunk_ids, doc_id(&1)))
        |> Enum.filter(fn doc ->
          case Map.get(by_id, doc_id(doc)) do
            nil -> true
            entry -> entry.status == :active
          end
        end)

      case docs ++ extra do
        [] -> List.wrap(fallback_docs)
        combined -> combined
      end
    end

    defp procedure_entry(_reference, nil), do: nil

    defp procedure_entry(reference, procedure_id) do
      Tracefield.Reference.get(reference, procedure_id)
    end

    defp apply_sharing_filter(entries, state, round) do
      authors = author_set(state.exclude_machine_authors)

      if MapSet.size(authors) == 0 do
        {entries, %{}}
      else
        excluded =
          entries
          |> Enum.filter(&MapSet.member?(authors, &1.author))
          |> Enum.map(& &1.author)
          |> Enum.uniq()

        filtered = Enum.reject(entries, &MapSet.member?(authors, &1.author))
        meta = sharing_perception_meta(excluded, state.sharing_stage, round)
        {filtered, meta}
      end
    end

    defp author_set(nil), do: MapSet.new()
    defp author_set(%MapSet{} = set), do: set
    defp author_set(authors) when is_list(authors), do: MapSet.new(authors)
    defp author_set(_other), do: MapSet.new()

    defp sharing_perception_meta([], _stage, _round), do: %{}

    defp sharing_perception_meta(excluded, stage, round) do
      %{
        sharing_excluded_authors: excluded,
        sharing_stage: stage,
        sharing_turn: round,
        sharing_mode: "independent"
      }
    end

    defp perception_log(query, retrieved, prompt, sharing_meta) do
      %{
        query: query,
        served: Enum.map(retrieved, &%{id: &1.id, author: &1.author}),
        prompt_tokens_est: prompt.prompt_tokens_est,
        doc_mode: prompt.doc_mode,
        docs_full_ids: prompt.docs_full_ids,
        over_budget: prompt.over_budget
      }
      |> Map.merge(sharing_meta)
    end

    defp build_prompt(reference, state, round, retrieved, procedure, note, query_text) do
      budget = context_budget(state)
      full_section = format_reference_docs(state.reference_docs)
      full_messages = messages(state, round, retrieved, procedure, note, full_section)
      full_estimate = Tracefield.Tokens.estimate_messages(full_messages)

      if full_estimate <= budget do
        %{
          messages: full_messages,
          prompt_tokens_est: full_estimate,
          doc_mode: :full,
          docs_full_ids: Enum.map(state.reference_docs, &doc_id/1),
          over_budget: false,
          context_budget: budget
        }
      else
        selected_docs =
          Tracefield.Reference.serve(reference, query_text,
            k: max(state.k_docs, 0),
            only_author: "DOCS",
            policy: :similar
          )

        selected_section = format_selected_reference_docs(state.reference_docs, selected_docs)
        selected_messages = messages(state, round, retrieved, procedure, note, selected_section)
        selected_estimate = Tracefield.Tokens.estimate_messages(selected_messages)

        %{
          messages: selected_messages,
          prompt_tokens_est: selected_estimate,
          doc_mode: :selected,
          docs_full_ids: Enum.map(selected_docs, & &1.id),
          over_budget: selected_estimate > budget,
          context_budget: budget
        }
      end
    end

    defp context_budget(state) do
      state.num_ctx - @num_predict - @budget_margin
    end

    defp messages(state, round, retrieved, procedure, note, reference_section) do
      messages = [
        %{
          role: "system",
          content: system_prompt(state)
        },
        %{
          role: "user",
          content: prompt(state, round, retrieved, procedure, note, reference_section)
        }
      ]

      messages
    end

    defp deliberate(messages, state, round) do
      opts =
        [
          adapter: state.adapter,
          model: state.model,
          temperature: state.temperature,
          seed: state.seed + round * 100,
          max_tokens: @num_predict,
          num_ctx: state.num_ctx,
          cli: state.cli,
          human: state.human
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      case Tracefield.LLM.complete(messages, opts) do
        {:ok, content} -> parse_entries(content)
        {:error, _reason} -> []
      end
    end

    @system_json_example ~S({"entries":[{"type":"belief","text":"...","citations":[{"id":"e1","stance":"relies_on"}]}]})

    defp system_prompt(state) do
      json_example = json_example_for(state.expected_types)
      types_hint = expected_types_hint(state.expected_types)

      "TRACEFIELD_AGENT_TURN\n#{situation_preamble(state)}Return only JSON #{json_example}.#{types_hint} At most 2 entries. Citations must use presented ids only. Each citation is an object {\"id\",\"stance\"}; stance is relies_on (your claim depends on that entry being true), refutes (you argue against it), or context (mere reference). If facts in PRIVATE DOCUMENT (yours only) contradict or interact with PRESENTED ENTRIES, point out the contradiction/interaction and cite both facts explicitly."
    end

    defp json_example_for(nil), do: @system_json_example

    defp json_example_for([first | _]) do
      String.replace(@system_json_example, ~S("type":"belief"), "\"type\":\"#{first}\"")
    end

    defp expected_types_hint(nil), do: ""
    defp expected_types_hint([_single]), do: ""

    defp expected_types_hint(types) do
      " Expected entry types this turn: #{Enum.join(types, ", ")}."
    end

    defp situation_preamble(%{aware: true, serve_policy: :contrastive}) do
      """
      SITUATION: あなたは、異なる偏りを持つ複数の AI エージェントが共有ストアで協働する
      「半溶解チーム」の一員である。他のエージェントはそれぞれ、あなたには見えない私的文書を持つ。
      PRESENTED ENTRIES は彼らがその私的知識から外部化した状態であり、あなたがその情報に触れる唯一の窓である。
      ただの文脈ではなく、あなたの知らない事実を含む証拠として扱え。あなたの entries も他のエージェントに読まれる。
      自分の偏り（DOMAIN）を保ったまま、彼らの状態を自分の私的事実と突き合わせて活用せよ。
      PRESENTED ENTRIES は、この課題に関連する「他メンバーの最も特徴的な寄与」の横断サンプルである。
      あなたの価値はそれらの補集合にある。エコー（提示内容の言い換え）を書くな。
      彼らが構造的に見落としている観点を、自分の偏りから提示せよ。
      """
    end

    defp situation_preamble(%{aware: true}) do
      """
      SITUATION: あなたは、異なる偏りを持つ複数の AI エージェントが共有ストアで協働する
      「半溶解チーム」の一員である。他のエージェントはそれぞれ、あなたには見えない私的文書を持つ。
      PRESENTED ENTRIES は彼らがその私的知識から外部化した状態であり、あなたがその情報に触れる唯一の窓である。
      ただの文脈ではなく、あなたの知らない事実を含む証拠として扱え。あなたの entries も他のエージェントに読まれる。
      自分の偏り（DOMAIN）を保ったまま、彼らの状態を自分の私的事実と突き合わせて活用せよ。
      """
    end

    defp situation_preamble(_state), do: ""

    defp prompt(state, round, retrieved, procedure, note, reference_section) do
      """
      TASK:
      #{state.anchor}

      #{reference_section}

      AGENT #{state.id}
      DOMAIN #{state.domain}
      DESC #{state.desc}
      ROUND #{round}

      PRIVATE DOCUMENT (yours only):
      #{format_private_doc(state, round)}

      #{format_private_memory(state.private_memory)}

      #{format_house_view(state.house_view)}

      PRESENTED ENTRIES:
      #{format_retrieved(retrieved)}
      #{format_procedure(procedure)}
      #{format_territory_contract(state.territory)}
      #{format_note(note)}
      """
      |> String.trim()
    end

    defp format_private_doc(state, round) do
      private_doc = state.private_doc

      if patrol_mode?(state, private_doc) do
        private_doc
        |> Tracefield.Patrol.split_sections()
        |> Tracefield.Patrol.select_slice(round)
        |> Tracefield.Patrol.format_patrol_body(round)
      else
        private_doc
      end
    end

    defp patrol_mode?(state, private_doc) do
      patrol = Map.get(state, :patrol, %{})
      enabled = Map.get(patrol, :enabled, Map.get(patrol, "enabled", true))
      threshold = Map.get(patrol, :token_threshold, Map.get(patrol, "token_threshold", 100_000))

      enabled and Tracefield.Tokens.estimate(private_doc) > threshold
    end

    defp format_note(nil), do: ""
    defp format_note(""), do: ""
    defp format_note(note), do: "\n\n#{String.trim(note)}"

    defp format_reference_docs([]), do: "REFERENCE DOCUMENTS（設計判断はここを引用せよ）:\n(none)"

    defp format_reference_docs(docs) do
      body =
        docs
        |> List.wrap()
        |> Enum.map_join("\n\n", fn doc ->
          id = Map.get(doc, :id, Map.get(doc, "id", ""))
          file = Map.get(doc, :file, Map.get(doc, "file", ""))
          text = Map.get(doc, :text, Map.get(doc, "text", ""))

          "DOC #{id} file=#{file}\n#{text}"
        end)

      "REFERENCE DOCUMENTS（設計判断はここを引用せよ）:\n#{body}"
    end

    defp format_selected_reference_docs([], _selected_docs) do
      "REFERENCE DOCUMENTS（予算超過のため関連上位のみ全文・他は目次。引用は目次の id でも可）:\n(none)"
    end

    defp format_selected_reference_docs(docs, selected_docs) do
      selected_ids = MapSet.new(Enum.map(selected_docs, & &1.id))

      index =
        docs
        |> List.wrap()
        |> Enum.map_join("\n", fn doc ->
          id = Map.get(doc, :id, Map.get(doc, "id", ""))
          file = Map.get(doc, :file, Map.get(doc, "file", ""))
          text = Map.get(doc, :text, Map.get(doc, "text", ""))

          "DOC #{id} file=#{file}: #{first_line(text)}"
        end)

      full_text =
        docs
        |> Enum.filter(fn doc -> MapSet.member?(selected_ids, doc_id(doc)) end)
        |> Enum.map_join("\n\n", fn doc ->
          id = Map.get(doc, :id, Map.get(doc, "id", ""))
          file = Map.get(doc, :file, Map.get(doc, "file", ""))
          text = Map.get(doc, :text, Map.get(doc, "text", ""))

          "DOC #{id} file=#{file}\n#{text}"
        end)

      body =
        if full_text == "" do
          "INDEX:\n#{index}\n\nFULL TEXT:\n(none)"
        else
          "INDEX:\n#{index}\n\nFULL TEXT:\n#{full_text}"
        end

      "REFERENCE DOCUMENTS（予算超過のため関連上位のみ全文・他は目次。引用は目次の id でも可）:\n#{body}"
    end

    defp first_line(text) do
      text
      |> to_string()
      |> String.split("\n", parts: 2)
      |> List.first()
      |> to_string()
      |> String.trim()
    end

    defp format_private_memory(memory) do
      body =
        memory
        |> to_string()
        |> String.trim()
        |> case do
          "" -> "(none)"
          text -> text
        end

      "PRIVATE MEMORY (あなた自身の過去の判断。経験として活かせ):\n#{body}"
    end

    defp format_house_view(house_view) do
      house_view =
        house_view
        |> to_string()
        |> String.trim()

      if house_view == "" do
        ""
      else
        "HOUSE VIEW（チームのこれまでの判断方針。踏まえつつ、自分の偏りからの異見も歓迎）:\n#{house_view}"
      end
    end

    defp format_procedure(nil), do: ""

    defp format_procedure(procedure) do
      "\n\nADOPTED PROCEDURE:\n#{procedure.text}"
    end

    defp format_territory_contract(nil), do: ""

    defp format_territory_contract(%{
           self: self,
           others: others,
           territory_contract_id: ledger_id
         }) do
      self_body = format_self_territory(self)

      portfolio =
        others
        |> Enum.sort_by(& &1.id)
        |> Enum.map_join("\n", fn actor ->
          "- #{actor.id} domain=#{actor.domain} desc=#{actor.desc}"
        end)
        |> case do
          "" -> "(none)"
          body -> body
        end

      """
      \n\nTERRITORY CONTRACT:
      Territory ledger entry: #{ledger_id}

      YOUR TERRITORY:
      #{self_body}

      PORTFOLIO MAP:
      #{portfolio}

      ENGAGEMENT NORM:
      境界は分担のためにあり、縄張りの防衛のためにあるのではない。他領土に接続する論点を恐れて避けるな。自領土の本質を出した上で、接続があれば述べよ
      """
      |> String.trim_leading()
    end

    defp format_self_territory(actor) do
      base = "- id: #{actor.id}\n- domain: #{actor.domain}\n- desc: #{actor.desc}"

      case Map.get(actor, :private_doc_file) do
        nil ->
          base

        "" ->
          base

        file ->
          base <>
            "\n- private document: #{file} (あなたの PRIVATE DOCUMENT がこの領土の実体である)"
      end
    end

    defp territory_contract_id(%{territory: %{territory_contract_id: id}}) when is_binary(id),
      do: id

    defp territory_contract_id(_state), do: nil

    defp format_retrieved([]), do: "(none)"

    defp format_retrieved(entries) do
      entries
      |> Enum.sort_by(&entry_number/1)
      |> Enum.map_join("\n", fn entry ->
        domain = Map.get(entry.meta, :domain, Map.get(entry.meta, "domain", ""))
        "ENTRY #{entry.id} author=#{entry.author} domain=#{domain} text=#{entry.text}"
      end)
    end

    defp entry_number(%{id: "e" <> number}) do
      case Integer.parse(number) do
        {value, ""} -> value
        _ -> 0
      end
    end

    defp entry_number(_entry), do: 0

    defp parse_entries(content) when is_binary(content) do
      with {:ok, %{} = decoded} <- decode_json_object(content) do
        decoded
        |> Map.get("entries", Map.get(decoded, :entries, []))
        |> List.wrap()
        |> Enum.filter(&is_map/1)
      else
        _ -> []
      end
    end

    defp parse_entries(_content), do: []

    defp sanitize_entry(entry, presented_ids, reference_doc_ids, state, round, procedure, opts) do
      territory_contract_id = Keyword.get(opts, :territory_contract_id)

      %{
        type: Map.get(entry, "type", Map.get(entry, :type, "belief")),
        text: Map.get(entry, "text", Map.get(entry, :text, "")) |> to_string() |> String.trim(),
        citations:
          entry
          |> Map.get("citations", Map.get(entry, :citations, []))
          |> List.wrap()
          |> Enum.map(&citation_with_stance/1)
          |> Enum.filter(fn c ->
            allowed_citation?(
              c.id,
              presented_ids,
              reference_doc_ids,
              procedure,
              territory_contract_id
            )
          end)
          |> append_procedure_id(procedure, state.adapter)
          |> append_territory_contract_id(territory_contract_id, state.adapter)
          |> append_recruit_id(state.recruit_id, state.adapter)
          |> Enum.uniq_by(& &1.id),
        meta: %{domain: state.domain, round: round}
      }
    end

    defp doc_id(doc), do: Map.get(doc, :id, Map.get(doc, "id"))

    defp allowed_citation?(id, presented_ids, reference_doc_ids, procedure, territory_contract_id) do
      MapSet.member?(presented_ids, id) or MapSet.member?(reference_doc_ids, id) or
        (not is_nil(procedure) and id == procedure.id) or
        (not is_nil(territory_contract_id) and id == territory_contract_id)
    end

    # Normalize a raw model citation (bare id string or %{"id","stance"}) into a
    # %{id, stance} map. Reference splits this back into a flat id + meta.stance.
    defp citation_with_stance(c) when is_binary(c) or is_atom(c) or is_integer(c),
      do: %{id: to_string(c), stance: "relies_on"}

    defp citation_with_stance(%{} = c) do
      id = c |> Map.get("id", Map.get(c, :id, "")) |> to_string()
      stance = c |> Map.get("stance", Map.get(c, :stance, "relies_on")) |> normalize_cite_stance()
      %{id: id, stance: stance}
    end

    defp citation_with_stance(_), do: %{id: "", stance: "relies_on"}

    defp normalize_cite_stance(s) when s in ["relies_on", "refutes", "context"], do: s
    defp normalize_cite_stance(s) when is_atom(s) and not is_nil(s), do: normalize_cite_stance(to_string(s))
    defp normalize_cite_stance(_), do: "relies_on"

    # Auto-appended ids (procedure/territory/recruit) are references, not factual
    # dependencies, so they carry stance "context".
    defp append_procedure_id(citations, _procedure, Tracefield.LLM.Human), do: citations
    defp append_procedure_id(citations, nil, _adapter), do: citations

    defp append_procedure_id(citations, procedure, _adapter),
      do: citations ++ [%{id: procedure.id, stance: "context"}]

    defp append_territory_contract_id(citations, _territory_contract_id, Tracefield.LLM.Human),
      do: citations

    defp append_territory_contract_id(citations, nil, _adapter), do: citations

    defp append_territory_contract_id(citations, territory_contract_id, _adapter) do
      if Enum.any?(citations, &(&1.id == territory_contract_id)),
        do: citations,
        else: citations ++ [%{id: territory_contract_id, stance: "context"}]
    end

    defp append_recruit_id(citations, _recruit_id, Tracefield.LLM.Human), do: citations
    defp append_recruit_id(citations, nil, _adapter), do: citations

    defp append_recruit_id(citations, recruit_id, _adapter) do
      if Enum.any?(citations, &(&1.id == recruit_id)),
        do: citations,
        else: citations ++ [%{id: recruit_id, stance: "context"}]
    end

    defp decode_json_object(content) do
      with {:error, _reason} <- Jason.decode(content),
           {:ok, object_text} <- extract_object_text(content) do
        Jason.decode(object_text)
      end
    end

    defp extract_object_text(content) do
      start = :binary.match(content, "{")
      finish = content |> String.reverse() |> :binary.match("}")

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

  def new(id, domain, desc, opts \\ []) do
    core =
      Core.new(
        id: to_string(id),
        state: %{
          id: to_string(id),
          domain: to_string(domain),
          desc: to_string(desc),
          anchor: Keyword.get(opts, :anchor, ""),
          reference_docs: Keyword.get(opts, :reference_docs, []),
          private_doc: Keyword.get(opts, :private_doc, ""),
          private_memory: Keyword.get(opts, :private_memory, ""),
          house_view: Keyword.get(opts, :house_view, ""),
          k_s: Keyword.get(opts, :k_s, 2),
          adapter: Keyword.get(opts, :adapter, Tracefield.LLM.Mock),
          cli: Keyword.get(opts, :cli),
          model: Keyword.get(opts, :model, "mock"),
          temperature: Keyword.get(opts, :temperature, 0.4) * 1.0,
          human: Keyword.get(opts, :human),
          seed: Keyword.get(opts, :seed, 0),
          num_ctx: Keyword.get(opts, :num_ctx, 8192),
          k_docs: Keyword.get(opts, :k_docs, 3),
          procedure_id: Keyword.get(opts, :procedure_id),
          recruit_id: Keyword.get(opts, :recruit_id),
          aware: Keyword.get(opts, :aware, false),
          serve_policy: Keyword.get(opts, :serve_policy, :similar),
          entry_limit: Keyword.get(opts, :entry_limit, 2),
          expected_types: normalize_expected_types(Keyword.get(opts, :expected_types)),
          territory: Keyword.get(opts, :territory),
          exclude_machine_authors: Keyword.get(opts, :exclude_machine_authors),
          sharing_stage: Keyword.get(opts, :sharing_stage),
          patrol: Keyword.get(opts, :patrol, %{enabled: true, token_threshold: 100_000})
        }
      )

    %__MODULE__{core: core}
  end

  def run_turn(%__MODULE__{core: core} = agent, reference, round, opts \\ []) do
    {updated_core, directives} =
      Core.cmd(
        core,
        {RunTurn, %{reference: reference, round: round, note: Keyword.get(opts, :note, "")}},
        timeout: 0,
        telemetry: :silent
      )

    {absorbed, perception} =
      if directives == [] do
        {
          Map.get(updated_core.state, :last_absorbed, []),
          Map.get(updated_core.state, :last_perception)
        }
      else
        {[], nil}
      end

    {%{agent | core: updated_core}, absorbed, perception}
  end

  defp normalize_expected_types(nil), do: nil

  defp normalize_expected_types(types) when is_list(types) do
    Enum.map(types, &to_string/1)
  end
end
