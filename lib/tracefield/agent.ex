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
        k_s: [type: :integer, default: 2],
        adapter: [type: :any, default: Tracefield.LLM.Mock],
        model: [type: :string, default: "mock"],
        temperature: [type: :float, default: 0.4],
        seed: [type: :integer, default: 0],
        last_round: [type: :integer, default: 0],
        absorbed_count: [type: :integer, default: 0],
        last_absorbed: [type: :any, default: []]
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
          exclude_author: state.id
        )

      presented_ids = MapSet.new(Enum.map(retrieved, & &1.id))

      entries =
        state
        |> deliberate(round, retrieved)
        |> Enum.take(2)
        |> Enum.map(&sanitize_entry(&1, presented_ids, state, round))
        |> Enum.reject(&(&1.text == ""))

      absorbed = Tracefield.Reference.absorb(reference, entries, state.id)

      {:ok,
       %{
         last_round: round,
         absorbed_count: state.absorbed_count + length(absorbed),
         last_absorbed: absorbed
       }}
    end

    defp query(state), do: Enum.join([state.anchor, state.domain], "\n")

    defp deliberate(state, round, retrieved) do
      messages = [
        %{
          role: "system",
          content:
            "TRACEFIELD_AGENT_TURN\nReturn only JSON {\"entries\":[{\"type\":\"belief\",\"text\":\"...\",\"citations\":[\"e1\"]}]}. At most 2 entries. Citations must use presented ids only."
        },
        %{
          role: "user",
          content: prompt(state, round, retrieved)
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

    defp prompt(state, round, retrieved) do
      """
      TASK:
      #{state.anchor}

      AGENT #{state.id}
      DOMAIN #{state.domain}
      DESC #{state.desc}
      ROUND #{round}

      PRESENTED ENTRIES:
      #{format_retrieved(retrieved)}
      """
      |> String.trim()
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

    defp sanitize_entry(entry, presented_ids, state, round) do
      %{
        type: Map.get(entry, "type", Map.get(entry, :type, "belief")),
        text: Map.get(entry, "text", Map.get(entry, :text, "")) |> to_string() |> String.trim(),
        citations:
          entry
          |> Map.get("citations", Map.get(entry, :citations, []))
          |> List.wrap()
          |> Enum.map(&to_string/1)
          |> Enum.filter(&MapSet.member?(presented_ids, &1))
          |> Enum.uniq(),
        meta: %{domain: state.domain, round: round}
      }
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
          k_s: Keyword.get(opts, :k_s, 2),
          adapter: Keyword.get(opts, :adapter, Tracefield.LLM.Mock),
          model: Keyword.get(opts, :model, "mock"),
          temperature: Keyword.get(opts, :temperature, 0.4) * 1.0,
          seed: Keyword.get(opts, :seed, 0)
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

    absorbed = Map.get(updated_core.state, :last_absorbed, [])
    absorbed = if directives == [], do: absorbed, else: []

    {%{agent | core: updated_core}, absorbed}
  end
end
