defmodule Tracefield.Agent.Tools.Absorb do
  @moduledoc false

  @entry_types ~w(
    belief
    hypothesis
    observation
    stance
    decision
    question
    requirement
    answer
    change
    verdict
    claim
    synthesis
    audit
  )

  use Jido.Action,
    name: "absorb",
    description: "Prepare a new entry for the shared store, citing source entries with a stance.",
    schema:
      Zoi.object(%{
        content: Zoi.string(description: "Entry text to write into the shared store."),
        type:
          Zoi.enum(@entry_types, description: "Tracefield entry type.")
          |> Zoi.default("belief"),
        citations:
          Zoi.array(
            Zoi.object(%{
              id: Zoi.string(description: "Cited entry id."),
              stance:
                Zoi.enum(["relies_on", "refutes", "context"],
                  description: "How the new entry uses the cited entry."
                )
            }),
            description: "Structured citations with stance."
          )
          |> Zoi.default([])
      })

  @impl true
  def run(params, _context) do
    {:ok,
     %{
       entry: %{
         type: normalize_value(Map.get(params, :type, "belief")),
         text: normalize_value(Map.get(params, :content, "")),
         citations: Enum.map(Map.get(params, :citations, []), &normalize_citation/1)
       }
     }}
  end

  defp normalize_citation(%{} = citation) do
    %{
      id: normalize_value(Map.get(citation, :id, Map.get(citation, "id", ""))),
      stance:
        normalize_value(Map.get(citation, :stance, Map.get(citation, "stance", "relies_on")))
    }
  end

  defp normalize_citation(citation), do: %{id: normalize_value(citation), stance: "relies_on"}

  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: to_string(value)
end
