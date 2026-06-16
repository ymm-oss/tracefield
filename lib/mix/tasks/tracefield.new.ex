defmodule Mix.Tasks.Tracefield.New do
  @shortdoc "Scaffold a new consult scenario (agents.json + task.md + private/)"

  @moduledoc """
  Create a new scenario directory in the generic consult format, ready to run.

      mix tracefield.new my-review
      mix tracefield.new my-review --dir scenarios   # base dir (default: scenarios)
      mix tracefield.new my-review --force           # overwrite if it exists

  It copies `scenarios/_template` when available, otherwise writes a minimal
  three-lens scaffold. The result runs immediately with the mock adapter, so you
  can see the shape before filling in the placeholders:

      mix tracefield.consult --scenario-dir scenarios/my-review --adapter mock

  Then edit `task.md` (the shared task) and each `private/<doc>.md` (one private
  lens per agent), and run again with a real `--adapter`.
  """
  use Mix.Task

  @template "scenarios/_template"

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} =
      OptionParser.parse(args, strict: [dir: :string, force: :boolean])

    name =
      case argv do
        [name | _] -> name
        [] -> Mix.raise("usage: mix tracefield.new <name> [--dir scenarios] [--force]")
      end

    base = Keyword.get(opts, :dir, "scenarios")
    target = Path.join(base, name)

    if File.exists?(target) and not Keyword.get(opts, :force, false) do
      Mix.raise("#{target} already exists — pass --force to overwrite")
    end

    File.rm_rf!(target)

    if File.dir?(@template) do
      File.cp_r!(@template, target)
      Mix.shell().info("scaffolded #{target} (from #{@template})")
    else
      generate_minimal(target)
      Mix.shell().info("scaffolded #{target} (minimal template)")
    end

    print_tree(target)

    Mix.shell().info("")
    Mix.shell().info("Next:")
    Mix.shell().info("  mix tracefield.consult --scenario-dir #{target} --adapter mock")
    Mix.shell().info("  # then edit task.md + private/*.md and rerun with a real --adapter")
  end

  defp generate_minimal(target) do
    File.mkdir_p!(Path.join(target, "private"))

    File.write!(Path.join(target, "agents.json"), agents_json())
    File.write!(Path.join(target, "task.md"), task_md())

    for {id, file} <- [{"LENS1", "lens1.md"}, {"LENS2", "lens2.md"}, {"LENS3", "lens3.md"}] do
      File.write!(Path.join([target, "private", file]), private_md(id))
    end
  end

  defp agents_json do
    """
    [
      {"id": "LENS1", "domain": "perspective-one", "desc": "<what this lens cares about most>", "doc": "lens1.md"},
      {"id": "LENS2", "domain": "perspective-two", "desc": "<what this lens cares about most>", "doc": "lens2.md"},
      {"id": "LENS3", "domain": "perspective-three", "desc": "<what this lens cares about most>", "doc": "lens3.md"}
    ]
    """
  end

  defp task_md do
    """
    # Task — <title here>

    <Describe the subject and the goal. For example:>
    - Subject = <whose / what decision is under review>
    - Goal = <what counts as success>
    - Output = <the shape you want, e.g. a risk list, concrete proposals, a design call>
    """
  end

  defp private_md(id) do
    """
    # Private lens: #{id}

    <Facts, constraints, or priorities only this lens knows. One claim per line
    works well — these are the private inputs whose downstream influence stays
    traceable and retractable.>
    """
  end

  defp print_tree(target) do
    Mix.shell().info("")

    target
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.each(fn path ->
      rel = Path.relative_to(path, target)
      marker = if File.dir?(path), do: "/", else: ""
      Mix.shell().info("  #{rel}#{marker}")
    end)
  end
end
