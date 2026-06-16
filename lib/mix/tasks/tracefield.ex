defmodule Mix.Tasks.Tracefield do
  @shortdoc "Overview of the tracefield tasks (run with no args)"

  @moduledoc """
  Print a categorized overview of the `mix tracefield.*` tasks.

      mix tracefield

  This is just a map. Run `mix help tracefield.<task>` for the full options of
  any single task, and `mix tracefield.doctor` to check your environment.
  """
  use Mix.Task

  @categories [
    {"Serving — use these to get an answer",
     [
       {"consult", "Consult the team; governed best-of-N synthesis (the main entry point)"},
       {"retract", "Retract an entry in a persisted store and show isolated re-synthesis"}
     ]},
    {"Authoring — make your own input",
     [
       {"new", "Scaffold a new consult scenario (agents.json + task.md + private/)"}
     ]},
    {"Diagnostics",
     [
       {"doctor", "Check toolchain, Ollama reachability, API keys, and CLI adapters"}
     ]},
    {"Experiments — the research harness",
     [
       {"phase0", "Core experiment phase 0"},
       {"phase1", "Core experiment phase 1 (distance / AUC / recall-precision)"},
       {"hetero", "Private-document substrate-heterogeneity experiment"},
       {"governance_vs_fusion", "Provenance-closure governance vs post-hoc fusion containment"},
       {"genesis", "Attractor detection and cluster scaffolding"},
       {"ideate", "Qualitative ideation over a scenario directory"},
       {"dissolution", "Dissolution / semi-soluble dynamics experiment"},
       {"doseresponse", "Contaminant dose-response curve"},
       {"transfer", "Cross-scenario transfer experiment"},
       {"remeasure", "Re-measure a persisted run"},
       {"bridge", "Two-store bridge / linkage experiment"},
       {"evidence", "Evidence-gathering experiment"},
       {"provenance", "Provenance inspection over a scenario"},
       {"field", "Field-level inspection"},
       {"toolprobe", "Probe tool-call behavior of an adapter"}
     ]}
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("tracefield — governable exploration for multi-agent systems\n")

    Enum.each(@categories, fn {heading, tasks} ->
      Mix.shell().info(IO.ANSI.format([:bright, heading, :reset]))

      width = tasks |> Enum.map(fn {name, _} -> String.length(name) end) |> Enum.max()

      Enum.each(tasks, fn {name, desc} ->
        padded = String.pad_trailing(name, width)
        Mix.shell().info("  mix tracefield.#{padded}  #{desc}")
      end)

      Mix.shell().info("")
    end)

    Mix.shell().info("First run (no model needed):")

    Mix.shell().info(
      "  mix tracefield.consult --scenario-dir scenarios/enterprise-hi --adapter mock\n"
    )

    Mix.shell().info("Details for any task:  mix help tracefield.<task>")
    Mix.shell().info("Check your setup:      mix tracefield.doctor")
  end
end
