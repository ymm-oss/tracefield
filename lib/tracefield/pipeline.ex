defmodule Tracefield.Pipeline do
  @moduledoc """
  C1 fixed-role pipeline runner with the same run shape as C4 exploration.
  """

  @roles ["PM", "Engineer", "UX", "Risk", "Legal", "Security", "FinalIntegrator"]

  def run(%Tracefield.Scenario{} = scenario, opts \\ []) do
    state = Keyword.get(opts, :state, :a)
    adapter = Keyword.get(opts, :adapter, Tracefield.LLM.Mock)
    model = Keyword.get(opts, :model, "mock")
    temperature = Keyword.get(opts, :temperature, 0.2)
    seed = Keyword.get(opts, :seed, 0)
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    injection = Tracefield.Explore.injection_for(scenario, state)

    with {:ok, transcript} <-
           run_roles(scenario, injection, adapter, model, temperature, seed),
         {:ok, final_output} <-
           synthesize(scenario, transcript, adapter, model, temperature, seed) do
      {:ok,
       %{
         condition: :c1,
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

  defp run_roles(scenario, injection, adapter, model, temperature, seed) do
    Enum.reduce_while(@roles, {:ok, []}, fn role, {:ok, transcript} ->
      case run_role(scenario, transcript, role, adapter, model, temperature, seed) do
        {:ok, updated} ->
          updated =
            if role == "PM" and injection.inject_after == "initial-framing" do
              updated ++
                [
                  Tracefield.Explore.assign_turn_id(
                    Tracefield.Explore.injection_turn(injection),
                    updated
                  )
                ]
            else
              updated
            end

          {:cont, {:ok, updated}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp run_role(scenario, transcript, role, adapter, model, temperature, seed) do
    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_EXPLORER_POINTS. You are the #{role} role in a fixed C1 review pipeline. Avoid duplicate points and focus on your role's responsibilities. Return only JSON shaped as {\"points\":[{\"text\":\"...\",\"depends_on_turns\":[previous_turn_id],\"uses_injection\":false}]}. depends_on_turns must contain only prior TURN ids from the transcript. uses_injection is true only when the point relies on the injected stakeholder note."
      },
      %{
        role: "user",
        content:
          "TASK:\n#{scenario.task}\n\nTRANSCRIPT SO FAR:\n#{Tracefield.Explore.format_transcript(transcript)}\n\nROLE #{role}: add non-duplicative concerns from your perspective."
      }
    ]

    llm_opts = [
      adapter: adapter,
      model: model,
      temperature: temperature,
      seed: seed + role_seed(role)
    ]

    case Tracefield.LLM.complete(messages, llm_opts) do
      {:ok, content} ->
        turn_id = Tracefield.Explore.next_turn_id(transcript)
        {contribution, points} = Tracefield.Explore.parse_contribution(content, turn_id)

        turn = %{
          role: "assistant",
          actor: role,
          round: 1,
          turn_id: turn_id,
          content: contribution,
          raw_content: content,
          points: points
        }

        {:ok, transcript ++ [turn]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp synthesize(scenario, transcript, adapter, model, temperature, seed) do
    messages = [
      %{
        role: "system",
        content:
          "TRACEFIELD_SYNTHESIS. You are FinalIntegrator. Produce a structured review using CLAIM[id] kind: text lines for atomic concerns, recommendations, and final recommendation."
      },
      %{
        role: "user",
        content:
          "TASK:\n#{scenario.task}\n\nTRANSCRIPT:\n#{Tracefield.Explore.format_transcript(transcript)}"
      }
    ]

    Tracefield.LLM.complete(messages,
      adapter: adapter,
      model: model,
      temperature: temperature,
      seed: seed + 9_001
    )
  end

  defp role_seed(role) do
    Enum.find_index(@roles, &(&1 == role)) + 1
  end
end
