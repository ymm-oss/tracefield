defmodule Mix.Tasks.Tracefield.Retract do
  @moduledoc """
  Retract an entry in a PERSISTED consult store and report which served
  synthesis findings the retraction reaches.

  This is the controlling half of governable synthesis (brushup③): the synthesis
  layer (`mix tracefield.consult --persist <store>`) absorbs findings into the
  store with citations to layer-0, so they are first-class nodes — not a static
  JSON blob that escapes governance. A retraction applied AFTER serving, on the
  reloaded store, still propagates through citations to the served findings.
  That is the difference from a stateless ensemble (Fusion): synthesize AND
  retract with provenance, across the serving boundary.

      mix tracefield.consult --scenario-dir <dir> --persist run.jsonl ...
      mix tracefield.retract --store run.jsonl --entry e3

  Loads the persisted store, retracts `--entry` (its status flips durably in the
  store), and prints the retraction closure partitioned into layer-0 entries vs.
  SYNTH findings isolated by it. The SYNTH findings appearing here are the proof
  that retraction crossed into the synthesis layer that was served.
  """
  use Mix.Task

  alias Tracefield.Reference

  @shortdoc "Retract an entry in a persisted store; show isolated synth findings"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [store: :string, entry: :string, author: :string])

    result =
      run_retract(
        store: Keyword.fetch!(opts, :store),
        entry: Keyword.fetch!(opts, :entry),
        synth_author: Keyword.get(opts, :author, "SYNTH")
      )

    print(result)
    result
  end

  @doc """
  Load the persisted store at `:store`, retract `:entry`, and return
  `%{retracted, closure_size, isolated_findings, isolated_layer0}` where
  `isolated_findings` are closure entries authored by `:synth_author` (default
  `"SYNTH"`) — the served findings the retraction reached.
  """
  def run_retract(opts) do
    store = Keyword.fetch!(opts, :store)
    id = to_string(Keyword.fetch!(opts, :entry))
    synth_author = Keyword.get(opts, :synth_author, "SYNTH")

    {:ok, ref} = Reference.start_link(persist_path: store)
    closure = Reference.retract(ref, id)
    GenServer.stop(ref)

    {findings, layer0} = Enum.split_with(closure, &(&1.author == synth_author))

    %{
      retracted: id,
      closure_size: length(closure),
      isolated_findings:
        Enum.map(findings, &%{id: &1.id, text: &1.text, citations: &1.citations}),
      isolated_layer0: Enum.map(layer0, &%{id: &1.id, author: &1.author})
    }
  end

  defp print(result) do
    Mix.shell().info("retracted #{result.retracted} → closure #{result.closure_size} entries")

    Mix.shell().info(
      "isolated SYNTH findings (served → now affected by retraction): #{length(result.isolated_findings)}"
    )

    Enum.each(result.isolated_findings, fn f ->
      Mix.shell().info("- [#{f.id}] cites=#{inspect(f.citations)}")
      Mix.shell().info("  #{f.text}")
    end)

    if result.isolated_layer0 != [] do
      Mix.shell().info(
        "also isolated (non-synth): #{Enum.map_join(result.isolated_layer0, ", ", & &1.id)}"
      )
    end
  end
end
