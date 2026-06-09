defmodule Tracefield.Explore do
  @moduledoc """
  C4 free-form multi-agent exploration loop.
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
              updated ++ [injection_turn(injection)]
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
            "You are explorer #{agent}. Avoid duplicate points and focus on cross-domain interactions."
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
          turn = %{role: "assistant", actor: "explorer-#{agent}", round: round, content: content}
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
      injection_id: injection.id,
      content: injection.body
    }
  end

  defp format_transcript([]), do: "(empty)"

  defp format_transcript(transcript) do
    Enum.map_join(transcript, "\n\n", fn turn ->
      actor = Map.get(turn, :actor, Map.get(turn, "actor", "unknown"))
      content = Map.get(turn, :content, Map.get(turn, "content", ""))
      "[#{actor}]\n#{content}"
    end)
  end
end
