defmodule Mix.Tasks.Tracefield.RetractTest do
  use ExUnit.Case

  alias Tracefield.Reference

  setup do
    path = Path.join(System.tmp_dir!(), "tf_retract_#{System.unique_integer([:positive])}.jsonl")
    File.rm(path)
    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  test "retraction reaches served synth findings across a store reload (serving boundary)", %{
    path: path
  } do
    # Serving run: persist layer-0 + a served synth finding that cites it.
    {:ok, ref} = Reference.start_link(persist_path: path, embed_adapter: Tracefield.Embed.Mock)
    [l0] = Reference.absorb(ref, [%{type: :belief, text: "layer-0 fact about retention"}], "BIZ")

    Reference.absorb(
      ref,
      [%{type: :belief, text: "served synth finding built on the fact", citations: [l0.id]}],
      "SYNTH"
    )

    # The serving process ends; only the persisted file remains.
    GenServer.stop(ref)

    # Post-serving: a fresh process restores the store and retracts the layer-0 fact.
    result = Mix.Tasks.Tracefield.Retract.run_retract(store: path, entry: l0.id)

    assert result.retracted == l0.id
    # the served finding is isolated by the retraction — across the reload
    assert Enum.any?(result.isolated_findings, &(&1.text =~ "served synth finding"))
    assert Enum.all?(result.isolated_findings, &(l0.id in &1.citations))
  end

  test "retraction durably persists: a second reload sees the entry retracted", %{path: path} do
    {:ok, ref} = Reference.start_link(persist_path: path, embed_adapter: Tracefield.Embed.Mock)
    [l0] = Reference.absorb(ref, [%{type: :belief, text: "fact to retract"}], "BIZ")
    GenServer.stop(ref)

    Mix.Tasks.Tracefield.Retract.run_retract(store: path, entry: l0.id)

    # reload again — the status flip was persisted
    {:ok, ref2} = Reference.start_link(persist_path: path, embed_adapter: Tracefield.Embed.Mock)
    assert Reference.get(ref2, l0.id).status == :retracted
    GenServer.stop(ref2)
  end
end
