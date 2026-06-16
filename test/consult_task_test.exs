defmodule Mix.Tasks.Tracefield.ConsultTest do
  use ExUnit.Case

  alias Mix.Tasks.Tracefield.Consult

  @scenario_dir "scenarios/enterprise-hi"

  defmodule BeliefMock do
    @behaviour Tracefield.LLM
    @impl true
    def complete(_messages, _opts) do
      {:ok,
       Jason.encode!(%{
         entries: [%{type: "belief", text: "generic improvement concern", citations: []}]
       })}
    end
  end

  defp base_opts(extra) do
    [
      scenario_dir: @scenario_dir,
      adapter: Tracefield.LLM.Mock,
      embed_adapter: Tracefield.Embed.Mock,
      model: "mock",
      rounds: 1,
      verify_adapter: Tracefield.LLM.Mock,
      verify_model: "mock"
    ] ++ extra
  end

  test "synth is on by default and returns findings with provenance" do
    # synth_complete cites the first deliberation entry; verify (Mock) grounds it
    # because the synth text echoes a token from that entry.
    synth_complete = fn prompt ->
      first_id =
        case Regex.run(~r/\[(e\d+)\]\s+(.+)/, prompt) do
          [_, id, _text] -> id
          _ -> "e1"
        end

      body =
        Jason.encode!(%{
          entries: [
            %{type: "belief", text: "synthesis セキュリティ business 横断の懸念", citations: [first_id]}
          ]
        })

      {:ok, body}
    end

    result =
      Consult.run_consult(base_opts(synth: true, synth_complete: synth_complete, synth_n: 1))

    assert result.synthesis != nil
    assert result.synthesis.sample_count == 1
    assert is_list(result.synthesis.findings)
    assert map_size(result.layer0_index) >= 1
  end

  test "--no-synth returns deliberation only" do
    result = Consult.run_consult(base_opts(synth: false))

    assert result.synthesis == nil
    assert is_list(result.deliberation)
  end

  test "generic agents.json scenario runs without contaminant files (clean input API)" do
    # scenarios/generic-smoke has task.md + agents.json (2 arbitrary agents) +
    # private/{a,b}.md and NO contaminant/correction files. The legacy
    # Scenario.load! path would raise on the missing files; the generic loader
    # must drive it from the manifest instead.
    result =
      Consult.run_consult(
        scenario_dir: "scenarios/generic-smoke",
        adapter: BeliefMock,
        embed_adapter: Tracefield.Embed.Mock,
        model: "mock",
        rounds: 1,
        synth: false
      )

    assert result.task =~ "改善案"
    # both manifest agents (A1, A2), not the hardcoded SEC/BIZ/UX, externalized
    authors = result.deliberation |> Enum.map(& &1.author) |> Enum.uniq() |> Enum.sort()
    assert authors == ["A1", "A2"]
  end
end
