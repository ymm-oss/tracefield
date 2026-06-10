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
        private_doc: [type: :string, default: ""],
        k_s: [type: :integer, default: 2],
        adapter: [type: :any, default: Tracefield.LLM.Mock],
        model: [type: :string, default: "mock"],
        temperature: [type: :float, default: 0.4],
        seed: [type: :integer, default: 0],
        procedure_id: [type: :string, default: nil],
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
        round: [type: :integer, required: true]
      ]

    @impl true
    def run(%{reference: reference, round: round}, %{state: state}) do
      retrieved =
        Tracefield.Reference.serve(reference, query(state),
          k: max(state.k_s, 0),
          exclude_author: state.id,
          exclude_types: [:procedure]
        )

      procedure = procedure_entry(reference, state.procedure_id)
      presented_ids = MapSet.new(Enum.map(retrieved, & &1.id))
      perception = perception_log(query(state), retrieved)

      entries =
        state
        |> deliberate(round, retrieved, procedure)
        |> Enum.take(2)
        |> Enum.map(&sanitize_entry(&1, presented_ids, state, round, procedure))
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

    defp procedure_entry(_reference, nil), do: nil

    defp procedure_entry(reference, procedure_id) do
      Tracefield.Reference.get(reference, procedure_id)
    end

    defp perception_log(query, retrieved) do
      %{
        query: query,
        served: Enum.map(retrieved, &%{id: &1.id, author: &1.author})
      }
    end

    defp deliberate(state, round, retrieved, procedure) do
      messages = [
        %{
          role: "system",
          content:
            "TRACEFIELD_AGENT_TURN\nReturn only JSON {\"entries\":[{\"type\":\"belief\",\"text\":\"...\",\"citations\":[\"e1\"]}]}. At most 2 entries. Citations must use presented ids only. If facts in PRIVATE DOCUMENT (yours only) contradict or interact with PRESENTED ENTRIES, point out the contradiction/interaction and cite both facts explicitly."
        },
        %{
          role: "user",
          content: prompt(state, round, retrieved, procedure)
        }
      ]

      opts = [
        adapter: state.adapter,
        model: state.model,
        temperature: state.temperature,
        seed: state.seed + round * 100
      ]

      case Tracefield.LLM.complete(messages, opts) do
        {:ok, content} -> parse_entries(content)
        {:error, _reason} -> []
      end
    end

    defp prompt(state, round, retrieved, procedure) do
      """
      TASK:
      #{state.anchor}

      AGENT #{state.id}
      DOMAIN #{state.domain}
      DESC #{state.desc}
      ROUND #{round}

      PRIVATE DOCUMENT (yours only):
      #{state.private_doc}

      PRESENTED ENTRIES:
      #{format_retrieved(retrieved)}
      #{format_procedure(procedure)}
      """
      |> String.trim()
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

    defp sanitize_entry(entry, presented_ids, state, round, procedure) do
      %{
        type: Map.get(entry, "type", Map.get(entry, :type, "belief")),
        text: Map.get(entry, "text", Map.get(entry, :text, "")) |> to_string() |> String.trim(),
        citations:
          entry
          |> Map.get("citations", Map.get(entry, :citations, []))
          |> List.wrap()
          |> Enum.map(&to_string/1)
          |> Enum.filter(&allowed_citation?(&1, presented_ids, procedure))
          |> append_procedure_id(procedure)
          |> Enum.uniq(),
        meta: %{domain: state.domain, round: round}
      }
    end

    defp allowed_citation?(id, presented_ids, nil), do: MapSet.member?(presented_ids, id)

    defp allowed_citation?(id, presented_ids, procedure) do
      MapSet.member?(presented_ids, id) or id == procedure.id
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
          private_doc: Keyword.get(opts, :private_doc, ""),
          k_s: Keyword.get(opts, :k_s, 2),
          adapter: Keyword.get(opts, :adapter, Tracefield.LLM.Mock),
          model: Keyword.get(opts, :model, "mock"),
          temperature: Keyword.get(opts, :temperature, 0.4) * 1.0,
          seed: Keyword.get(opts, :seed, 0),
          procedure_id: Keyword.get(opts, :procedure_id)
        }
      )

    %__MODULE__{core: core}
  end

  def run_turn(%__MODULE__{core: core} = agent, reference, round) do
    {updated_core, directives} =
      Core.cmd(core, {RunTurn, %{reference: reference, round: round}},
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
