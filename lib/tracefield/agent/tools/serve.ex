defmodule Tracefield.Agent.Tools.Serve do
  @moduledoc false

  use Jido.Action,
    name: "serve",
    description: "Retrieve entries from the shared knowledge store matching a query.",
    schema: [
      query: [
        type: :string,
        required: true,
        doc: "Search query for entries in the shared knowledge store."
      ]
    ]

  @impl true
  def run(%{query: query}, context) do
    reference = Map.fetch!(context, :reference)
    state = Map.fetch!(context, :state)

    served =
      Tracefield.Reference.serve(reference, query,
        k: max(Map.get(context, :k, state.k_s), 0),
        exclude_author: state.id,
        exclude_types: [:procedure, :territory_contract, :corpus_chunk],
        policy: state.serve_policy
      )

    {:ok,
     %{
       query: query,
       entries: Enum.map(served, &%{id: &1.id, author: &1.author, text: &1.text})
     }}
  end
end
