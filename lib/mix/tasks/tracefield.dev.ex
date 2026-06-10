defmodule Mix.Tasks.Tracefield.Dev do
  @moduledoc "Run the Tracefield development pipeline over an issue directory."
  use Mix.Task

  alias Tracefield.{Agent, Reference}

  @shortdoc "Run Tracefield dev pipeline"
  @refine_procedure """
                    REFINE手続き: ISSUE と REFERENCE DOCUMENTS から、(a) 受入基準を含む要件を type "requirement" で、
                    (b) 人間に確認すべき不明点を type "question" で書け。各 entry は根拠チャンクを引用。日本語。
                    """
                    |> String.trim()

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    args
    |> parse_args()
    |> run_dev()
  end

  def run_dev(opts) do
    issue_dir = Keyword.fetch!(opts, :issue)
    status? = Keyword.get(opts, :status, false)
    state = load_state(issue_dir)

    {:ok, reference} =
      Reference.start_link(
        persist_path: Path.join(issue_dir, "store.jsonl"),
        embed_adapter: Tracefield.Embed.Mock
      )

    actors = load_actors!(issue_dir)
    procedure_id = seed_reference!(reference, issue_dir)

    cond do
      status? ->
        print_status(issue_dir, state, reference)
        %{state: state, entries: Reference.all(reference)}

      state["status"] == "done" ->
        print_done(reference)
        %{state: state, entries: Reference.all(reference)}

      state["status"] == "awaiting_human" ->
        resume_refine(reference, actors, issue_dir, procedure_id, state, opts)

      true ->
        start_refine(reference, actors, issue_dir, procedure_id, opts)
    end
  end

  def load_actors!(issue_dir) do
    issue_dir
    |> actors_path()
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(&load_actor!(issue_dir, &1))
  end

  defp parse_args(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          issue: :string,
          status: :boolean,
          rounds: :integer,
          adapter: :string,
          model: :string,
          temperature: :float,
          cli_cmd: :string
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    [
      issue: Keyword.get(opts, :issue) || Mix.raise("--issue is required"),
      status: Keyword.get(opts, :status, false),
      rounds: Keyword.get(opts, :rounds, 2),
      adapter: Keyword.get(opts, :adapter, "mock"),
      model: Keyword.get(opts, :model),
      temperature: Keyword.get(opts, :temperature, 0.4),
      cli_cmd: Keyword.get(opts, :cli_cmd)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp actors_path(issue_dir) do
    actors = Path.join(issue_dir, "actors.json")

    if File.exists?(actors) do
      actors
    else
      Path.join(issue_dir, "agents.json")
    end
  end

  defp load_actor!(
         issue_dir,
         %{"id" => id, "domain" => domain, "desc" => desc} = actor
       ) do
    private_doc_file = Map.get(actor, "private_doc")

    %{
      id: to_string(id),
      domain: to_string(domain),
      desc: to_string(desc),
      kind: normalize_kind(Map.get(actor, "kind", "llm")),
      turn: normalize_turn(Map.get(actor, "turn", "blocking")),
      private_doc_file: private_doc_file,
      private_doc_path: private_doc_path(issue_dir, private_doc_file),
      private_doc: read_private_doc(issue_dir, private_doc_file),
      model: optional_string(Map.get(actor, "model"))
    }
  end

  defp load_actor!(_issue_dir, actor), do: Mix.raise("invalid actor entry #{inspect(actor)}")

  defp normalize_kind(kind) when kind in ["llm", "cli", "human"], do: String.to_atom(kind)
  defp normalize_kind(other), do: Mix.raise("invalid actor kind #{inspect(other)}")

  defp normalize_turn(turn) when turn in ["blocking", "async"], do: String.to_atom(turn)
  defp normalize_turn(other), do: Mix.raise("invalid actor turn #{inspect(other)}")

  defp private_doc_path(_issue_dir, nil), do: nil
  defp private_doc_path(issue_dir, file), do: Path.join([issue_dir, "private", file])

  defp read_private_doc(_issue_dir, nil), do: ""
  defp read_private_doc(issue_dir, file), do: File.read!(private_doc_path(issue_dir, file))

  defp optional_string(nil), do: nil
  defp optional_string(""), do: nil
  defp optional_string(value), do: to_string(value)

  defp load_state(issue_dir) do
    path = state_path(issue_dir)

    if File.exists?(path) do
      Jason.decode!(File.read!(path))
    else
      %{"stage" => "refine", "status" => "new", "round" => 0, "iteration" => 0}
    end
  end

  defp write_state!(issue_dir, state) do
    File.write!(state_path(issue_dir), Jason.encode!(state, pretty: true))
  end

  defp state_path(issue_dir), do: Path.join(issue_dir, "state.json")

  defp seed_reference!(reference, issue_dir) do
    issue_path = Path.join(issue_dir, "issue.md")

    seed_entries =
      [
        %{
          type: :chunk,
          author: "ISSUE",
          text: File.read!(issue_path),
          meta: %{file: "issue.md"}
        }
      ] ++ doc_seed_entries(issue_dir)

    Reference.absorb_idempotent(reference, seed_entries, "ISSUE")

    [procedure] =
      Reference.absorb_idempotent(
        reference,
        [%{type: :procedure, text: @refine_procedure, meta: %{stage: "refine"}}],
        "FACILITATOR"
      )

    procedure.id
  end

  defp doc_seed_entries(issue_dir) do
    docs_dir = Path.join(issue_dir, "docs")

    if File.dir?(docs_dir) do
      docs_dir
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(fn path ->
        %{
          type: :chunk,
          author: "DOCS",
          text: File.read!(path),
          meta: %{file: Path.basename(path)}
        }
      end)
    else
      []
    end
  end

  defp start_refine(reference, actors, issue_dir, procedure_id, opts) do
    rounds = Keyword.get(opts, :rounds, 2)
    run_llm_rounds(reference, actors, issue_dir, procedure_id, 1..rounds, opts)
    state = await_human(reference, actors, issue_dir, procedure_id, rounds, 0, opts)
    %{state: state, entries: Reference.all(reference)}
  end

  defp resume_refine(reference, actors, issue_dir, procedure_id, state, opts) do
    round = Map.get(state, "round", 2)
    iteration = Map.get(state, "iteration", 0)
    human = blocking_human!(actors)
    before_ids = entry_ids(reference)

    {_agent, _absorbed, _perception} =
      run_human_turn(reference, human, issue_dir, procedure_id, round)

    new_human_entries = new_entries(reference, before_ids, human.id)

    cond do
      human_decision?(reference, actors) ->
        done = %{
          "stage" => "refine",
          "status" => "done",
          "round" => round,
          "iteration" => iteration
        }

        write_state!(issue_dir, done)
        print_done(reference)
        %{state: done, entries: Reference.all(reference)}

      new_human_entries == [] ->
        state = awaiting_state(issue_dir, human, round, iteration)
        print_awaiting(issue_dir, human)
        %{state: state, entries: Reference.all(reference)}

      true ->
        next_round = round + 1
        run_llm_rounds(reference, actors, issue_dir, procedure_id, [next_round], opts)

        state =
          await_human(reference, actors, issue_dir, procedure_id, next_round, iteration + 1, opts)

        %{state: state, entries: Reference.all(reference)}
    end
  end

  defp run_llm_rounds(reference, actors, issue_dir, procedure_id, rounds, opts) do
    actors
    |> Enum.filter(&(&1.kind in [:llm, :cli]))
    |> then(fn actors ->
      Enum.each(rounds, fn round ->
        Enum.each(actors, fn actor ->
          actor
          |> build_agent(reference, issue_dir, procedure_id, opts)
          |> Agent.run_turn(reference, round)
        end)
      end)
    end)
  end

  defp await_human(reference, actors, issue_dir, procedure_id, round, iteration, _opts) do
    human = blocking_human!(actors)

    {_agent, _absorbed, _perception} =
      run_human_turn(reference, human, issue_dir, procedure_id, round)

    cond do
      human_decision?(reference, actors) ->
        state = %{
          "stage" => "refine",
          "status" => "done",
          "round" => round,
          "iteration" => iteration
        }

        write_state!(issue_dir, state)
        print_done(reference)
        state

      true ->
        state = awaiting_state(issue_dir, human, round, iteration)
        print_awaiting(issue_dir, human)
        state
    end
  end

  defp run_human_turn(reference, human, issue_dir, procedure_id, round) do
    human
    |> build_human_agent(reference, issue_dir, procedure_id)
    |> Agent.run_turn(reference, round)
  end

  defp build_agent(actor, reference, issue_dir, procedure_id, opts) do
    Agent.new(actor.id, actor.domain, actor.desc,
      anchor: File.read!(Path.join(issue_dir, "issue.md")),
      reference_docs: reference_docs(reference),
      private_doc: actor.private_doc,
      k_s: 10,
      adapter: adapter(actor, opts),
      cli: cli_config(opts),
      model: actor.model || Keyword.get(opts, :model, default_model(actor, opts)),
      temperature: Keyword.get(opts, :temperature, 0.4),
      seed: :erlang.phash2(actor.id),
      procedure_id: procedure_id,
      serve_policy: :diverse
    )
  end

  defp build_human_agent(actor, reference, issue_dir, procedure_id) do
    Agent.new(actor.id, actor.domain, actor.desc,
      anchor: File.read!(Path.join(issue_dir, "issue.md")),
      reference_docs: reference_docs(reference),
      private_doc: actor.private_doc,
      k_s: 200,
      adapter: Tracefield.LLM.Human,
      model: "human",
      temperature: 0.0,
      procedure_id: procedure_id,
      serve_policy: :diverse,
      entry_limit: 50,
      human: %{
        pending_dir: Path.join(issue_dir, "pending"),
        actor_id: actor.id,
        stage: "refine",
        approve_targets: active_ids(reference, :requirement),
        question_ids: active_ids(reference, :question)
      }
    )
  end

  defp reference_docs(reference) do
    reference
    |> Reference.all()
    |> Enum.filter(
      &(&1.type == :chunk and &1.author in ["ISSUE", "DOCS"] and &1.status == :active)
    )
    |> Enum.map(fn entry ->
      %{
        id: entry.id,
        file: Map.get(entry.meta, :file, Map.get(entry.meta, "file")),
        text: entry.text
      }
    end)
  end

  defp adapter(%{kind: :cli}, _opts), do: Tracefield.LLM.CLI
  defp adapter(_actor, opts), do: adapter_module(Keyword.get(opts, :adapter, "mock"))

  defp adapter_module("mock"), do: Tracefield.LLM.Mock
  defp adapter_module("cli"), do: Tracefield.LLM.CLI
  defp adapter_module(other), do: Mix.raise("unknown adapter #{inspect(other)}")

  defp default_model(%{kind: :cli}, _opts), do: nil
  defp default_model(_actor, _opts), do: "mock"

  defp cli_config(opts) do
    case Keyword.get(opts, :cli_cmd) do
      nil -> {"claude", ["-p"]}
      cmd -> {cmd, []}
    end
  end

  defp blocking_human!(actors) do
    Enum.find(actors, &(&1.kind == :human and &1.turn == :blocking)) ||
      Mix.raise("refine stage requires a blocking human actor")
  end

  defp human_decision?(reference, actors) do
    human_ids =
      actors
      |> Enum.filter(&(&1.kind == :human))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    reference
    |> Reference.all()
    |> Enum.any?(
      &(&1.type == :decision and &1.status == :active and MapSet.member?(human_ids, &1.author))
    )
  end

  defp active_ids(reference, type) do
    reference
    |> Reference.all()
    |> Enum.filter(&(&1.type == type and &1.status == :active))
    |> Enum.map(& &1.id)
  end

  defp entry_ids(reference) do
    reference |> Reference.all() |> Enum.map(& &1.id) |> MapSet.new()
  end

  defp new_entries(reference, before_ids, author) do
    reference
    |> Reference.all()
    |> Enum.reject(&MapSet.member?(before_ids, &1.id))
    |> Enum.filter(&(&1.author == author))
  end

  defp awaiting_state(issue_dir, human, round, iteration) do
    state = %{
      "stage" => "refine",
      "status" => "awaiting_human",
      "round" => round,
      "iteration" => iteration,
      "pending" => pending_relative(issue_dir, human)
    }

    write_state!(issue_dir, state)
    state
  end

  defp print_status(issue_dir, state, reference) do
    stats = Reference.stats(reference)
    Mix.shell().info("Tracefield Dev status")
    Mix.shell().info("issue: #{issue_dir}")
    Mix.shell().info("stage: #{state["stage"]}")
    Mix.shell().info("status: #{state["status"]}")

    Mix.shell().info(
      "store: #{Path.join(issue_dir, "store.jsonl")} entries=#{stats.entries} restored=#{stats.restored}"
    )
  end

  defp print_awaiting(issue_dir, human) do
    Mix.shell().info("⏸ 人間の回答待ち: #{pending_relative(issue_dir, human)}")
  end

  defp print_done(reference) do
    entries = Reference.all(reference)
    requirements = Enum.filter(entries, &(&1.type == :requirement and &1.status == :active))
    decisions = Enum.filter(entries, &(&1.type == :decision and &1.status == :active))

    Mix.shell().info("Tracefield Dev refine done")
    Mix.shell().info("requirements: #{length(requirements)}")
    Mix.shell().info("human decisions: #{length(decisions)}")
    Mix.shell().info("provenance: #{provenance_chain(entries)}")
  end

  defp provenance_chain(entries) do
    issue_ids =
      entries
      |> Enum.filter(&(&1.type == :chunk and &1.author == "ISSUE"))
      |> Map.new(&{&1.id, &1})

    entries
    |> Enum.find(fn entry ->
      entry.type == :requirement and Enum.any?(entry.citations, &Map.has_key?(issue_ids, &1))
    end)
    |> case do
      nil ->
        "requirement -> issue chunk: unavailable"

      requirement ->
        issue_id = Enum.find(requirement.citations, &Map.has_key?(issue_ids, &1))
        issue = Map.fetch!(issue_ids, issue_id)

        "#{requirement.id} requirement -> #{issue.id} issue chunk (#{Map.get(issue.meta, :file, "issue.md")})"
    end
  end

  defp pending_relative(issue_dir, human) do
    issue_dir
    |> Path.join("pending")
    |> then(&Path.join(&1, "#{human.id}-refine.md"))
    |> Path.relative_to(issue_dir)
  end
end
