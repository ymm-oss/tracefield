defmodule Tracefield.Explore do
  @moduledoc """
  C4 free-form multi-agent exploration loop with C5 point provenance capture.
  """

  def run(%Tracefield.Scenario{} = scenario, opts \\ []) do
    state = Keyword.get(opts, :state, :a)
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Mock)
    model = Keyword.get(opts, :model, "mock")
    temperature = Keyword.get(opts, :temperature, 0.2)
    seed = Keyword.get(opts, :seed, 0)
    n_agents = Keyword.get(opts, :n_agents, 4)
    rounds = Keyword.get(opts, :rounds, 3)
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    injection = injection_for(scenario, state)

    with {:ok, transcript} <-
           run_rounds(scenario, injection, n_agents, rounds, adapter, model, temperature, seed),
         {:ok, final_output} <-
           synthesize(scenario, transcript, adapter, model, temperature, seed) do
      {:ok,
       %{
         condition: :c4,
         state: state,
         seed: seed,
         model: model,
         temperature: temperature,
         timestamp: timestamp,
         raw_output: final_output,
         transcript: transcript
       }}
    end
  end

  defp run_rounds(scenario, injection, n_agents, rounds, adapter, model, temperature, seed) do
    Enum.reduce_while(1..rounds, {:ok, []}, fn round, {:ok, transcript} ->
      case run_agent_round(
             scenario,
             transcript,
             n_agents,
             round,
             adapter,
             model,
             temperature,
             seed
           ) do
        {:ok, updated} ->
          updated =
            if round == 1 and injection.inject_after == "initial-framing" do
              updated ++ [assign_turn_id(injection_turn(injection), updated)]
            else
              updated
            end

          {:cont, {:ok, updated}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp run_agent_round(scenario, transcript, n_agents, round, adapter, model, temperature, seed) do
    Enum.reduce_while(1..n_agents, {:ok, transcript}, fn agent, {:ok, acc} ->
      messages = [
        %{
          role: "system",
          content:
            "TRACEFIELD_EXPLORER_POINTS. You are explorer #{agent}. Avoid duplicate points and focus on cross-domain interactions. Return only JSON shaped as {\"points\":[{\"text\":\"...\",\"depends_on_turns\":[previous_turn_id],\"uses_injection\":false}]}. depends_on_turns must contain only prior TURN ids from the transcript. uses_injection is true only when the point relies on the injected stakeholder note."
        },
        %{
          role: "user",
          content:
            "TASK:\n#{scenario.task}\n\nTRANSCRIPT SO FAR:\n#{format_transcript(acc)}\n\nROUND #{round}, AGENT #{agent}: add non-duplicative concerns."
        }
      ]

      llm_opts = [
        adapter: adapter,
        model: model,
        temperature: temperature,
        seed: seed + round * 100 + agent
      ]

      case Tracefield.LLM.complete(messages, llm_opts) do
        {:ok, content} ->
          turn_id = next_turn_id(acc)
          {contribution, points} = parse_contribution(content, turn_id)

          turn = %{
            role: "assistant",
            actor: "explorer-#{agent}",
            round: round,
            turn_id: turn_id,
            content: contribution,
            raw_content: content,
            points: points
          }

          {:cont, {:ok, acc ++ [turn]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp synthesize(scenario, transcript, adapter, model, temperature, seed) do
    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_SYNTHESIS. Produce a structured review using CLAIM[id] kind: text lines for atomic concerns, recommendations, and final recommendation."
      },
      %{
        role: "user",
        content: "TASK:\n#{scenario.task}\n\nTRANSCRIPT:\n#{format_transcript(transcript)}"
      }
    ]

    Tracefield.LLM.complete(messages,
      adapter: adapter,
      model: model,
      temperature: temperature,
      seed: seed + 9_001
    )
  end

  defp injection_for(scenario, :a), do: scenario.contaminant
  defp injection_for(scenario, "a"), do: scenario.contaminant
  defp injection_for(scenario, :b), do: scenario.correction
  defp injection_for(scenario, "b"), do: scenario.correction

  defp injection_turn(injection) do
    %{
      role: "user",
      actor: injection.source_actor,
      round: 1,
      turn_id: nil,
      injection_id: injection.id,
      content: injection.body
    }
  end

  defp next_turn_id(transcript), do: length(transcript) + 1

  defp assign_turn_id(turn, transcript) do
    case Map.get(turn, :turn_id) do
      id when is_integer(id) -> turn
      _ -> Map.put(turn, :turn_id, next_turn_id(transcript))
    end
  end

  defp parse_contribution(content, turn_id) do
    case decode_points_json(content) do
      {:ok, %{"points" => raw_points}} when is_list(raw_points) ->
        points =
          raw_points
          |> Enum.with_index(1)
          |> Enum.map(fn {point, index} -> normalize_point(point, turn_id, index) end)
          |> Enum.reject(&is_nil/1)

        if points == [] do
          {content, []}
        else
          {Enum.map_join(points, "\n", & &1.text), points}
        end

      _ ->
        {content, []}
    end
  end

  defp decode_points_json(content) do
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

  defp normalize_point(%{} = point, turn_id, index) do
    text = point_value(point, "text", "")

    if is_binary(text) and String.trim(text) != "" do
      %{
        point_id: "t#{turn_id}.p#{index}",
        text: String.trim(text),
        depends_on_turns: normalize_depends(point_value(point, "depends_on_turns", [])),
        uses_injection: point_value(point, "uses_injection", false) == true
      }
    end
  end

  defp normalize_point(_point, _turn_id, _index), do: nil

  defp point_value(map, key, default) do
    atom_key =
      case key do
        "text" -> :text
        "depends_on_turns" -> :depends_on_turns
        "uses_injection" -> :uses_injection
      end

    Map.get(map, key, Map.get(map, atom_key, default))
  end

  defp normalize_depends(depends) when is_list(depends) do
    depends
    |> Enum.map(&parse_turn_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_depends(_depends), do: []

  defp parse_turn_id(turn_id) when is_integer(turn_id), do: turn_id

  defp parse_turn_id(turn_id) when is_binary(turn_id) do
    case Integer.parse(turn_id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_turn_id(_turn_id), do: nil

  defp format_transcript([]), do: "(empty)"

  defp format_transcript(transcript) do
    Enum.map_join(transcript, "\n\n", fn turn ->
      actor = Map.get(turn, :actor, Map.get(turn, "actor", "unknown"))
      content = Map.get(turn, :content, Map.get(turn, "content", ""))
      turn_id = Map.get(turn, :turn_id, Map.get(turn, "turn_id"))
      header = "TURN #{turn_id || "?"} [#{actor}]"

      points =
        turn
        |> Map.get(:points, Map.get(turn, "points", []))
        |> format_points()

      if points == "" do
        "#{header}\n#{content}"
      else
        "#{header}\n#{points}"
      end
    end)
  end

  defp format_points(points) when is_list(points) do
    Enum.map_join(points, "\n", fn point ->
      id = Map.get(point, :point_id, Map.get(point, "point_id", "point"))
      text = Map.get(point, :text, Map.get(point, "text", ""))
      depends = Map.get(point, :depends_on_turns, Map.get(point, "depends_on_turns", []))
      uses = Map.get(point, :uses_injection, Map.get(point, "uses_injection", false))
      "POINT #{id} depends_on_turns=#{inspect(depends)} uses_injection=#{uses}: #{text}"
    end)
  end

  defp format_points(_points), do: ""
end
