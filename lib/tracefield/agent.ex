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
        seed: [type: :integer, default: 0],
        num_ctx: [type: :integer, default: 8192],
        k_docs: [type: :integer, default: 3],
        procedure_id: [type: :string, default: nil],
        aware: [type: :boolean, default: false],
        serve_policy: [type: :any, default: :similar],
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

      retrieved =
        Tracefield.Reference.serve(reference, query_text,
          k: max(state.k_s, 0),
          exclude_author: state.id,
          exclude_types: [:procedure],
          policy: state.serve_policy
        )

      procedure = procedure_entry(reference, state.procedure_id)
      presented_ids = MapSet.new(Enum.map(retrieved, & &1.id))
      reference_doc_ids = MapSet.new(Enum.map(state.reference_docs, &doc_id/1))
      prompt = build_prompt(reference, state, round, retrieved, procedure, note, query_text)
      perception = perception_log(query_text, retrieved, prompt)

      entries =
        prompt.messages
        |> deliberate(state, round)
        |> Enum.take(2)
        |> Enum.map(
          &sanitize_entry(&1, presented_ids, reference_doc_ids, state, round, procedure)
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
      docs =
        reference
        |> Tracefield.Reference.all()
        |> Enum.filter(&(&1.type == :chunk and &1.author == "DOCS" and &1.status == :active))
        |> Enum.map(fn entry ->
          %{
            id: entry.id,
            file: Map.get(entry.meta, :file, Map.get(entry.meta, "file")),
            text: entry.text
          }
        end)

      if docs == [], do: List.wrap(fallback_docs), else: docs
    end

    defp procedure_entry(_reference, nil), do: nil

    defp procedure_entry(reference, procedure_id) do
      Tracefield.Reference.get(reference, procedure_id)
    end

    defp perception_log(query, retrieved, prompt) do
      %{
        query: query,
        served: Enum.map(retrieved, &%{id: &1.id, author: &1.author}),
        prompt_tokens_est: prompt.prompt_tokens_est,
        doc_mode: prompt.doc_mode,
        docs_full_ids: prompt.docs_full_ids,
        over_budget: prompt.over_budget
      }
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
          cli: state.cli
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      case Tracefield.LLM.complete(messages, opts) do
        {:ok, content} -> parse_entries(content)
        {:error, _reason} -> []
      end
    end

    defp system_prompt(state) do
      "TRACEFIELD_AGENT_TURN\n#{situation_preamble(state)}Return only JSON {\"entries\":[{\"type\":\"belief\",\"text\":\"...\",\"citations\":[\"e1\"]}]}. At most 2 entries. Citations must use presented ids only. If facts in PRIVATE DOCUMENT (yours only) contradict or interact with PRESENTED ENTRIES, point out the contradiction/interaction and cite both facts explicitly."
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
      #{state.private_doc}

      #{format_private_memory(state.private_memory)}

      #{format_house_view(state.house_view)}

      PRESENTED ENTRIES:
      #{format_retrieved(retrieved)}
      #{format_procedure(procedure)}
      #{format_note(note)}
      """
      |> String.trim()
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

    defp sanitize_entry(entry, presented_ids, reference_doc_ids, state, round, procedure) do
      %{
        type: Map.get(entry, "type", Map.get(entry, :type, "belief")),
        text: Map.get(entry, "text", Map.get(entry, :text, "")) |> to_string() |> String.trim(),
        citations:
          entry
          |> Map.get("citations", Map.get(entry, :citations, []))
          |> List.wrap()
          |> Enum.map(&to_string/1)
          |> Enum.filter(&allowed_citation?(&1, presented_ids, reference_doc_ids, procedure))
          |> append_procedure_id(procedure)
          |> Enum.uniq(),
        meta: %{domain: state.domain, round: round}
      }
    end

    defp doc_id(doc), do: Map.get(doc, :id, Map.get(doc, "id"))

    defp allowed_citation?(id, presented_ids, reference_doc_ids, nil) do
      MapSet.member?(presented_ids, id) or MapSet.member?(reference_doc_ids, id)
    end

    defp allowed_citation?(id, presented_ids, reference_doc_ids, procedure) do
      allowed_citation?(id, presented_ids, reference_doc_ids, nil) or id == procedure.id
    end

    defp append_procedure_id(citations, nil), do: citations
    defp append_procedure_id(citations, procedure), do: citations ++ [procedure.id]

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
          seed: Keyword.get(opts, :seed, 0),
          num_ctx: Keyword.get(opts, :num_ctx, 8192),
          k_docs: Keyword.get(opts, :k_docs, 3),
          procedure_id: Keyword.get(opts, :procedure_id),
          aware: Keyword.get(opts, :aware, false),
          serve_policy: Keyword.get(opts, :serve_policy, :similar)
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
end
