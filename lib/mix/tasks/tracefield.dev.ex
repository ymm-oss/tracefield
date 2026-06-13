defmodule Mix.Tasks.Tracefield.Dev do
  @moduledoc "Run the Tracefield development pipeline over an issue directory."
  use Mix.Task

  require Logger

  alias Tracefield.{Agent, Coverage, Policy, QA, Reference, Workspace}
  alias Tracefield.LLM.Human

  @response_heading "## RESPONSE（この下に回答を書いてください）"
  @gate_entry_types ~w(requirement question decision observation)a

  @shortdoc "Run Tracefield dev pipeline"
  @refine_procedure """
                    REFINE手続き: ISSUE と REFERENCE DOCUMENTS から、(a) 受入基準を含む要件を type "requirement" で、
                    (b) 人間に確認すべき不明点を type "question" で書け。各 entry は根拠チャンクを引用。日本語。
                    """
                    |> String.trim()

  @design_procedure """
                    DESIGN手続き: 承認済みの要件を実現する設計判断を type "decision" で書け。各判断は
                    (a) 対応する requirement entry と (b) 根拠となる REFERENCE DOCUMENTS チャンクを必ず引用。
                    採用案と退けた代替案・その理由を含め、実装可能な粒度（変更するモジュール/関数/データが特定できる）で。日本語。
                    """
                    |> String.trim()

  @combine_instruction """
                         PRESENTED ENTRIES の中に自分の専門と接続する entry があれば、帰結を述べてその entry と根拠 DOC の両方を引用せよ
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
    cli_policy = Keyword.get(opts, :cli_policy, cli_policy_from_opts(opts))
    {policy, policy_sources} = Policy.load_layers!(issue_dir, cli_policy) |> Policy.resolve()
    opts = put_effective_policy!(opts, policy, policy_sources)
    embed_mod = embed_module!(Keyword.fetch!(opts, :embed))
    opts = Keyword.put(opts, :embed_adapter, embed_mod)
    status? = Keyword.get(opts, :status, false)
    state = load_state(issue_dir)

    {:ok, reference} =
      Reference.start_link(
        persist_path: Path.join(issue_dir, "store.jsonl"),
        embed_adapter: embed_mod
      )

    actors = load_actors!(issue_dir)
    procedure_id = seed_reference!(reference, issue_dir, opts)
    territory_contract_id = seed_territory_contract!(reference, actors)
    policy_id = seed_policy!(reference, policy, policy_sources, actors)
    opts =
      opts
      |> Keyword.put(:policy_id, policy_id)
      |> Keyword.put(:territory_contract_id, territory_contract_id)

    cond do
      adopt_recruit = Keyword.get(opts, :adopt_recruit) ->
        adopt_recruit!(reference, issue_dir, adopt_recruit)
        %{state: state, entries: Reference.all(reference)}

      status? ->
        print_status(issue_dir, state, reference, actors, policy, policy_sources)
        %{state: state, entries: Reference.all(reference)}

      state["stage"] == "refine" and state["status"] == "done" ->
        start_design(reference, actors, issue_dir, state, opts)

      state["stage"] == "refine" and state["status"] == "awaiting_human" ->
        resume_refine(reference, actors, issue_dir, procedure_id, state, opts)

      state["stage"] == "design" and state["status"] == "done" ->
        if Workspace.configured?(issue_dir) do
          start_implement(reference, actors, issue_dir, state, opts)
        else
          Mix.shell().info("design 完了。implement を開始するには workspace.json を置いてください")
          print_design_done(reference, actors, issue_dir)
          %{state: state, entries: Reference.all(reference)}
        end

      state["stage"] == "design" ->
        resume_design(reference, actors, issue_dir, state, opts)

      state["stage"] == "implement" and state["status"] == "done" ->
        start_qa(reference, actors, issue_dir, state, opts)

      state["stage"] == "qa" and state["status"] == "done" ->
        Mix.shell().info("qa 完了。Issue 完遂（refine→design→implement→qa）")
        print_qa_done_from_issue(reference, issue_dir, state, opts)
        %{state: state, entries: Reference.all(reference)}

      state["stage"] == "implement" ->
        resume_implement(reference, actors, issue_dir, state, opts)

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
          recruit: :boolean,
          adopt_recruit: :string,
          rounds: :integer,
          adapter: :string,
          embed: :string,
          model: :string,
          temperature: :float,
          cli_cmd: :string,
          coverage_threshold: :float,
          coverage_mode: :string
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    [
      issue: Keyword.get(opts, :issue) || Mix.raise("--issue is required"),
      status: Keyword.get(opts, :status, false),
      adopt_recruit: Keyword.get(opts, :adopt_recruit),
      adapter: Keyword.get(opts, :adapter, "mock"),
      model: Keyword.get(opts, :model),
      temperature: Keyword.get(opts, :temperature, 0.4),
      cli_cmd: Keyword.get(opts, :cli_cmd),
      cli_policy: cli_policy_from_opts(opts)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp cli_policy_from_opts(opts) do
    %{}
    |> maybe_put_policy(["coverage", "threshold"], opts, :coverage_threshold)
    |> maybe_put_policy(["coverage", "mode"], opts, :coverage_mode, &coverage_mode_string!/1)
    |> maybe_put_policy(["embed"], opts, :embed)
    |> maybe_put_policy(["recruit"], opts, :recruit)
    |> maybe_put_policy(["rounds"], opts, :rounds)
  end

  defp maybe_put_policy(policy, path, opts, opt_key, mapper \\ & &1) do
    if Keyword.has_key?(opts, opt_key) do
      put_in_policy(policy, path, mapper.(Keyword.fetch!(opts, opt_key)))
    else
      policy
    end
  end

  defp put_in_policy(_policy, [], value), do: value

  defp put_in_policy(policy, [key | rest], value) do
    existing = Map.get(policy, key, %{})
    Map.put(policy, key, put_in_policy(existing, rest, value))
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
      kind: normalize_kind!(Map.get(actor, "kind"), id),
      turn: normalize_turn(Map.get(actor, "turn", "blocking")),
      private_doc_file: private_doc_file,
      private_doc_path: private_doc_path(issue_dir, private_doc_file),
      private_doc: read_private_doc(issue_dir, private_doc_file),
      model: optional_string(Map.get(actor, "model")),
      recruit_entry: optional_string(Map.get(actor, "recruit_entry"))
    }
  end

  defp load_actor!(_issue_dir, actor), do: Mix.raise("invalid actor entry #{inspect(actor)}")

  defp normalize_kind!(kind, _id) when kind in ["llm", "cli", "human"], do: String.to_atom(kind)
  defp normalize_kind!(nil, id), do: Mix.raise("missing actor kind for #{id}")
  defp normalize_kind!(other, id), do: Mix.raise("invalid actor kind #{inspect(other)} for #{id}")

  defp normalize_turn(turn) when turn in ["blocking", "async"], do: String.to_atom(turn)
  defp normalize_turn(other), do: Mix.raise("invalid actor turn #{inspect(other)}")

  defp private_doc_path(_issue_dir, nil), do: nil
  defp private_doc_path(issue_dir, file), do: Path.join([issue_dir, "private", file])

  defp read_private_doc(_issue_dir, nil), do: ""
  defp read_private_doc(issue_dir, file), do: File.read!(private_doc_path(issue_dir, file))

  defp optional_string(nil), do: nil
  defp optional_string(""), do: nil
  defp optional_string(value), do: to_string(value)

  @doc false
  def embed_module!("mock"), do: Tracefield.Embed.Mock
  def embed_module!("ollama"), do: Tracefield.Embed.Ollama
  def embed_module!(other), do: Mix.raise("invalid embed #{inspect(other)}")

  @doc false
  def coverage_mode!("absolute"), do: :absolute
  def coverage_mode!("relative"), do: :relative
  def coverage_mode!(mode) when is_atom(mode), do: coverage_mode!(Atom.to_string(mode))
  def coverage_mode!(other), do: Mix.raise("invalid coverage_mode #{inspect(other)}")

  defp coverage_mode_string!(mode) do
    mode
    |> coverage_mode!()
    |> Atom.to_string()
  end

  defp put_effective_policy!(opts, policy, sources) do
    coverage = Map.fetch!(policy, "coverage")

    opts
    |> Keyword.put(:policy, policy)
    |> Keyword.put(:policy_sources, sources)
    |> Keyword.put(:embed, Map.fetch!(policy, "embed"))
    |> Keyword.put(:recruit, Map.fetch!(policy, "recruit"))
    |> Keyword.put(:rounds, Map.fetch!(policy, "rounds"))
    |> Keyword.put(:coverage_threshold, Map.fetch!(coverage, "threshold"))
    |> Keyword.put(:coverage_mode, coverage |> Map.fetch!("mode") |> coverage_mode!())
    |> validate_effective_policy_opts!()
  end

  defp validate_effective_policy_opts!(opts) do
    embed_module!(Keyword.fetch!(opts, :embed))

    unless is_boolean(Keyword.fetch!(opts, :recruit)) do
      Mix.raise("invalid recruit policy #{inspect(Keyword.fetch!(opts, :recruit))}")
    end

    rounds = Keyword.fetch!(opts, :rounds)

    unless is_integer(rounds) and rounds >= 1 do
      Mix.raise("invalid rounds policy #{inspect(rounds)}")
    end

    threshold = Keyword.fetch!(opts, :coverage_threshold)

    unless is_number(threshold) do
      Mix.raise("invalid coverage threshold policy #{inspect(threshold)}")
    end

    opts
  end

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

  defp seed_reference!(reference, issue_dir, opts) do
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
        [
          %{
            type: :procedure,
            text: refine_procedure_text(opts),
            meta: %{stage: "refine"}
          }
        ],
        "FACILITATOR"
      )

    procedure.id
  end

  @doc false
  def seed_territory_contract!(reference, actors) do
    text = territory_contract_text(actors)

    [entry] =
      Reference.absorb_idempotent(
        reference,
        [
          %{
            type: :territory_contract,
            text: text,
            meta: %{kind: "territory_ledger"}
          }
        ],
        "FACILITATOR"
      )

    supersede_stale_territory_contracts!(reference, entry.id)
    entry.id
  end

  defp supersede_stale_territory_contracts!(reference, current_id) do
    stale_ids =
      reference
      |> Reference.all()
      |> Enum.filter(
        &(&1.type == :territory_contract and &1.status == :active and &1.id != current_id)
      )
      |> Enum.map(& &1.id)

    if stale_ids != [] do
      Reference.quarantine(reference, stale_ids)
    end
  end

  defp territory_contract_text(actors) do
    portfolio =
      actors
      |> Enum.filter(&(&1.kind in [:llm, :cli]))
      |> Enum.sort_by(& &1.id)
      |> Enum.map_join("\n", fn actor ->
        private =
          case actor.private_doc_file do
            nil -> ""
            "" -> ""
            file -> " private_doc=#{file}"
          end

        "- #{actor.id} domain=#{actor.domain} desc=#{actor.desc}#{private}"
      end)

    """
    領土台帳（TERRITORY CONTRACT LEDGER）

    #{portfolio}
    """
    |> String.trim()
  end

  defp refine_procedure_text(opts) do
    case sharing_mode(opts, "refine") do
      "combine" -> @refine_procedure <> "\n" <> @combine_instruction
      _other -> @refine_procedure
    end
  end

  defp design_procedure_text(opts) do
    case sharing_mode(opts, "design") do
      "combine" -> @design_procedure <> "\n" <> @combine_instruction
      _other -> @design_procedure
    end
  end

  defp sharing_mode(opts, stage) do
    opts
    |> Keyword.fetch!(:policy)
    |> Policy.sharing_mode(stage)
  end

  defp seed_policy!(reference, policy, sources, actors) do
    machine_ids =
      actors
      |> machine_actor_ids()
      |> MapSet.to_list()
      |> Enum.sort()

    sharing =
      for stage <- ["refine", "design"], into: %{} do
        mode = Policy.sharing_mode(policy, stage)

        meta =
          if mode == "independent" do
            %{"mode" => mode, "sharing_excluded_authors" => machine_ids}
          else
            %{"mode" => mode}
          end

        {stage, meta}
      end

    [entry] =
      Reference.absorb_idempotent(
        reference,
        [
          %{
            type: :policy,
            author: "POLICY",
            text: Policy.summary(policy, sources),
            meta: %{
              kind: "effective_policy",
              policy: policy,
              sources: sources,
              sharing: sharing
            }
          }
        ],
        "POLICY"
      )

    entry.id
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
    warn_uncovered_chunks!(reference, actors, opts)
    rounds = Keyword.get(opts, :rounds, 2)

    run_llm_rounds(
      reference,
      actors,
      issue_dir,
      procedure_id,
      1..rounds,
      opts,
      nil,
      ["requirement", "question"],
      "refine"
    )

    state = await_human(reference, actors, issue_dir, procedure_id, rounds, 0, opts)
    %{state: state, entries: Reference.all(reference)}
  end

  defp resume_refine(reference, actors, issue_dir, procedure_id, state, opts) do
    round = Map.get(state, "round", 2)
    iteration = Map.get(state, "iteration", 0)
    human = blocking_human!(actors)
    before_ids = entry_ids(reference)

    pending_path = human_pending_path(issue_dir, human, "refine")
    apply_amend_pre_pass(reference, pending_path, human.id)

    {_agent, _absorbed, _perception} =
      run_human_turn(
        reference,
        human,
        issue_dir,
        procedure_id,
        round,
        refine_human_opts(reference)
      )

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
        state = awaiting_state(issue_dir, human, round, iteration, "refine")
        print_awaiting(issue_dir, human, "refine")
        %{state: state, entries: Reference.all(reference)}

      true ->
        next_round = round + 1

        run_llm_rounds(
          reference,
          actors,
          issue_dir,
          procedure_id,
          [next_round],
          opts,
          nil,
          ["requirement", "question"],
          "refine"
        )

        state =
          await_human(reference, actors, issue_dir, procedure_id, next_round, iteration + 1, opts)

        %{state: state, entries: Reference.all(reference)}
    end
  end

  defp start_design(reference, actors, issue_dir, state, opts) do
    procedure_id = seed_design_procedure!(reference, opts)
    base_round = Map.get(state, "round", 2)
    rounds = Keyword.get(opts, :rounds, 2)
    ref_docs = design_reference_docs(reference)

    run_llm_rounds(
      reference,
      actors,
      issue_dir,
      procedure_id,
      (base_round + 1)..(base_round + rounds),
      opts,
      ref_docs,
      ["decision"],
      "design"
    )

    state = await_design(reference, actors, issue_dir, procedure_id, base_round + rounds, 0, opts)
    %{state: state, entries: Reference.all(reference)}
  end

  defp resume_design(reference, actors, issue_dir, state, opts) do
    procedure_id = seed_design_procedure!(reference, opts)
    round = Map.get(state, "round", 4)
    iteration = Map.get(state, "iteration", 0)
    human = blocking_human!(actors)
    before_ids = entry_ids(reference)

    warn_uncited_decisions(reference, actors)

    pending_path = human_pending_path(issue_dir, human, "design")
    apply_amend_pre_pass(reference, pending_path, human.id)
    apply_reject_lines(reference, pending_path, human.id, actors)

    {_agent, _absorbed, _perception} =
      run_human_turn(
        reference,
        human,
        issue_dir,
        procedure_id,
        round,
        design_human_opts(reference, actors)
      )

    new_human_entries = new_entries(reference, before_ids, human.id)

    cond do
      design_complete?(reference, actors) ->
        done = %{
          "stage" => "design",
          "status" => "done",
          "round" => round,
          "iteration" => iteration
        }

        write_state!(issue_dir, done)
        write_design_md!(issue_dir, reference, actors)
        print_design_done(reference, actors, issue_dir)
        %{state: done, entries: Reference.all(reference)}

      new_human_entries == [] ->
        state = awaiting_state(issue_dir, human, round, iteration, "design")
        print_awaiting(issue_dir, human, "design")
        %{state: state, entries: Reference.all(reference)}

      true ->
        next_round = round + 1

        run_llm_rounds(
          reference,
          actors,
          issue_dir,
          procedure_id,
          [next_round],
          opts,
          design_reference_docs(reference),
          ["decision"],
          "design"
        )

        state =
          await_design(reference, actors, issue_dir, procedure_id, next_round, iteration + 1, opts)

        %{state: state, entries: Reference.all(reference)}
    end
  end

  defp start_implement(reference, actors, issue_dir, state, opts) do
    ws = load_workspace!(issue_dir, opts)
    ws = Workspace.ensure_flow!(ws, issue_slug(issue_dir))
    print_git_flow(ws, issue_dir)

    unless Workspace.clean?(ws) do
      Mix.raise("workspace が clean ではありません")
    end

    approved = approved_design_decisions(reference, actors)

    if approved == [] do
      Mix.raise("承認済み設計判断がありません")
    end

    round = Map.get(state, "round", 0) + 1
    run_organ_round(reference, actors, issue_dir, ws, round, approved, opts, nil, nil)
    state = await_implement(reference, actors, issue_dir, ws, round, 0, %{}, opts)
    %{state: state, entries: Reference.all(reference)}
  end

  defp resume_implement(reference, actors, issue_dir, state, opts) do
    ws = load_workspace!(issue_dir, opts)
    ws = Workspace.ensure_flow!(ws, issue_slug(issue_dir))
    round = Map.get(state, "round", 1)
    iteration = Map.get(state, "iteration", 0)
    human = blocking_human!(actors)
    before_ids = entry_ids(reference)
    pending_path = human_pending_path(issue_dir, human, "implement")
    apply_amend_pre_pass(reference, pending_path, human.id)
    apply_reject_lines(reference, pending_path, human.id, actors)

    {_agent, _absorbed, _perception} =
      run_human_turn(reference, human, issue_dir, nil, round, implement_human_opts(reference, ws))

    new_human_entries = new_entries(reference, before_ids, human.id)

    cond do
      implement_complete?(reference, actors) ->
        change_ids = organ_change_ids(reference, ws.organ_author)
        issue_line = issue_first_line(issue_dir)

        commit_message =
          "tracefield implement: #{issue_line} [#{Enum.join(change_ids, " ")}]"

        pr_state =
          case Workspace.apply!(ws, commit_message) do
            {:ok, _sha} ->
              push_pr_after_apply!(reference, actors, issue_dir, state, ws)

            {:error, :empty} ->
              Mix.shell().error("warning: workspace にコミットする変更がありませんでした")
              state
          end

        done =
          %{
            "stage" => "implement",
            "status" => "done",
            "round" => round,
            "iteration" => iteration
          }
          |> preserve_pr_url(pr_state)

        write_state!(issue_dir, done)
        print_implement_done(reference, actors, issue_dir, done, ws)
        %{state: done, entries: Reference.all(reference)}

      new_human_entries == [] ->
        state =
          issue_dir
          |> awaiting_state(human, round, iteration, "implement")
          |> preserve_pr_url(state)

        write_state!(issue_dir, state)
        print_awaiting(issue_dir, human, "implement")
        %{state: state, entries: Reference.all(reference)}

      true ->
        next_round = round + 1
        comments = Enum.map_join(new_human_entries, "\n", & &1.text)
        last_stat = latest_change_stat(reference, ws.organ_author)
        approved_decisions = approved_design_decisions(reference, actors)

        run_organ_round(
          reference,
          actors,
          issue_dir,
          ws,
          next_round,
          approved_decisions,
          opts,
          comments,
          last_stat
        )

        state =
          await_implement(reference, actors, issue_dir, ws, next_round, iteration + 1, state, opts)

        %{state: state, entries: Reference.all(reference)}
    end
  end

  defp run_organ_round(
         reference,
         _actors,
         issue_dir,
         ws,
         round,
         approved,
         opts,
         comments,
         last_stat
       ) do
    prompt = build_implement_prompt(issue_dir, reference, approved, comments, last_stat)
    adapter = adapter_module(Keyword.get(opts, :adapter, "mock"))

    {:ok, organ_output} = Workspace.implement!(ws, prompt, adapter)
    diff = Workspace.capture_diff!(ws)
    test_result = Workspace.run_tests!(ws)

    patch_path = issue_dir |> Path.join("pending") |> Path.join("implement-r#{round}.patch")
    File.mkdir_p!(Path.dirname(patch_path))
    File.write!(patch_path, diff.diff)

    test_label = if test_result.exit == 0, do: "green", else: "red"

    citations =
      approved |> Enum.map(& &1.id) |> maybe_append_policy(Keyword.get(opts, :policy_id))

    [change] =
      Reference.absorb(
        reference,
        %{
          type: :change,
          text:
            "実装変更 r#{round}: #{diff.stat} / テスト: #{test_label} (exit #{test_result.exit}) / diff: pending/implement-r#{round}.patch",
          citations: citations,
          meta: %{
            files: diff.files,
            diff_sha: diff.sha,
            test_exit: test_result.exit,
            round: round,
            organ_summary: String.slice(organ_output, 0, 400)
          }
        },
        ws.organ_author
      )

    change
  end

  defp await_implement(reference, actors, issue_dir, ws, round, iteration, prior_state, opts) do
    human = blocking_human!(actors)
    pending_path = human_pending_path(issue_dir, human, "implement")

    display_gate_warnings(compute_gate_warnings(reference, actors, opts, round, pending_path))
    apply_amend_pre_pass(reference, pending_path, human.id)
    apply_reject_lines(reference, pending_path, human.id, actors)

    {_agent, _absorbed, _perception} =
      run_human_turn(reference, human, issue_dir, nil, round, implement_human_opts(reference, ws))

    cond do
      implement_complete?(reference, actors) ->
        change_ids = organ_change_ids(reference, ws.organ_author)
        issue_line = issue_first_line(issue_dir)

        commit_message =
          "tracefield implement: #{issue_line} [#{Enum.join(change_ids, " ")}]"

        pr_state =
          case Workspace.apply!(ws, commit_message) do
            {:ok, _sha} ->
              push_pr_after_apply!(reference, actors, issue_dir, prior_state, ws)

            {:error, :empty} ->
              Mix.shell().error("warning: workspace にコミットする変更がありませんでした")
              prior_state
          end

        state =
          %{
            "stage" => "implement",
            "status" => "done",
            "round" => round,
            "iteration" => iteration
          }
          |> preserve_pr_url(pr_state)

        write_state!(issue_dir, state)
        print_implement_done(reference, actors, issue_dir, state, ws)
        state

      true ->
        state =
          issue_dir
          |> awaiting_state(human, round, iteration, "implement")
          |> preserve_pr_url(prior_state)

        write_state!(issue_dir, state)
        print_awaiting(issue_dir, human, "implement")
        state
    end
  end

  defp build_implement_prompt(issue_dir, reference, approved, comments, last_stat) do
    issue = File.read!(Path.join(issue_dir, "issue.md"))

    requirements =
      reference
      |> Reference.all()
      |> Enum.filter(&(&1.type == :requirement and &1.status == :active))
      |> Enum.map_join("\n", &"#{&1.id}: #{&1.text}")

    decisions =
      approved
      |> Enum.map_join("\n", &"#{&1.id}: #{&1.text}")

    resume_section =
      cond do
        comments && comments != "" && last_stat && last_stat != "" ->
          "\n\n前回のレビューコメント:\n#{comments}\n\n直前の diff stat:\n#{last_stat}\n"

        comments && comments != "" ->
          "\n\n前回のレビューコメント:\n#{comments}\n"

        last_stat && last_stat != "" ->
          "\n\n直前の diff stat:\n#{last_stat}\n"

        true ->
          ""
      end

    """
    TRACEFIELD_IMPLEMENT

    ISSUE:
    #{issue}

    承認済み要件:
    #{requirements}

    承認済み設計判断:
    #{decisions}
    #{resume_section}
    あなたは実装器官。カレントディレクトリの対象リポジトリを設計判断どおりに変更せよ。git commit は行うな。変更の概要のみ出力せよ。
    """
    |> String.trim()
  end

  defp implement_human_opts(reference, ws) do
    %{
      stage: "implement",
      approve_targets: organ_change_ids(reference, ws.organ_author),
      ref_docs: design_reference_docs(reference)
    }
  end

  defp approved_design_decisions(reference, actors) do
    machine_authors =
      actors
      |> Enum.filter(&(&1.kind in [:llm, :cli]))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    human_ids =
      actors
      |> Enum.filter(&(&1.kind == :human))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    human_cited_ids =
      reference
      |> Reference.all()
      |> Enum.filter(
        &(&1.type == :decision and &1.status == :active and MapSet.member?(human_ids, &1.author))
      )
      |> Enum.flat_map(& &1.citations)
      |> MapSet.new()

    reference
    |> Reference.all()
    |> Enum.filter(
      &(&1.type == :decision and &1.status == :active and
          MapSet.member?(machine_authors, &1.author) and
          MapSet.member?(human_cited_ids, &1.id))
    )
  end

  defp organ_change_ids(reference, organ_author) do
    reference
    |> Reference.all()
    |> Enum.filter(&(&1.type == :change and &1.status == :active and &1.author == organ_author))
    |> Enum.map(& &1.id)
  end

  defp implement_complete?(reference, actors) do
    human_ids =
      actors
      |> Enum.filter(&(&1.kind == :human))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    latest_change_id = latest_active_change_id(reference)

    latest_change_id &&
      reference
      |> Reference.all()
      |> Enum.any?(fn entry ->
        entry.type == :decision and entry.status == :active and
          MapSet.member?(human_ids, entry.author) and
          latest_change_id in entry.citations
      end)
  end

  defp latest_active_change_id(reference) do
    reference
    |> Reference.all()
    |> Enum.filter(&(&1.type == :change and &1.status == :active))
    |> Enum.max_by(&entry_number(&1.id), fn -> nil end)
    |> case do
      nil -> nil
      change -> change.id
    end
  end

  defp latest_organ_change!(reference, organ_author) do
    reference
    |> Reference.all()
    |> Enum.filter(&(&1.type == :change and &1.status == :active and &1.author == organ_author))
    |> Enum.max_by(&entry_number(&1.id), fn -> nil end)
    |> case do
      nil -> Mix.raise("active organ change がありません")
      change -> change
    end
  end

  defp start_qa(reference, actors, issue_dir, state, opts) do
    ws = load_workspace!(issue_dir, opts)
    ws = Workspace.ensure_flow!(ws, issue_slug(issue_dir))
    round = Map.get(state, "round", 0) + 1
    adapter = adapter_module(Keyword.get(opts, :adapter, "mock"))

    llm_opts = [
      model: Keyword.get(opts, :model, "mock"),
      temperature: Keyword.get(opts, :temperature, 0.4),
      cli: cli_config(opts)
    ]

    test_result = Workspace.run_tests!(ws)
    latest_change = latest_organ_change!(reference, ws.organ_author)

    requirements =
      reference
      |> Reference.all()
      |> Enum.filter(&(&1.type == :requirement and &1.status == :active))

    verdicts =
      Enum.map(requirements, fn requirement ->
        judgment = QA.judge(adapter, llm_opts, requirement, latest_change, test_result)
        pass = test_result.exit == 0 and judgment.matched
        matched_label = if judgment.matched, do: "matched", else: "unmatched"
        pass_label = if pass, do: "pass", else: "fail"

        text =
          "QA判定 r#{round}: #{pass_label} — テスト exit #{test_result.exit} / 突合: #{matched_label} #{judgment.note}"

        [verdict] =
          Reference.absorb(
            reference,
            %{
              type: :verdict,
              text: text,
              citations: [requirement.id, latest_change.id],
              meta: %{
                test_exit: test_result.exit,
                matched: judgment.matched,
                pass: pass,
                round: round
              }
            },
            "QA"
          )

        verdict
      end)

    if Enum.all?(verdicts, &verdict_pass?/1) do
      done =
        %{
          "stage" => "qa",
          "status" => "done",
          "round" => round,
          "iteration" => Map.get(state, "iteration", 0)
        }
        |> preserve_pr_url(state)

      write_state!(issue_dir, done)
      print_qa_done(reference, issue_dir, ws, done)
      %{state: done, entries: Reference.all(reference)}
    else
      fail_feedback =
        verdicts
        |> Enum.reject(&verdict_pass?/1)
        |> Enum.map_join("\n", & &1.text)

      feedback = "QA差し戻し:\n#{fail_feedback}"
      approved = approved_design_decisions(reference, actors)
      next_round = round + 1

      run_organ_round(
        reference,
        actors,
        issue_dir,
        ws,
        next_round,
        approved,
        opts,
        feedback,
        latest_change_stat(reference, ws.organ_author)
      )

      state = await_implement(reference, actors, issue_dir, ws, next_round, 0, state, opts)
      %{state: state, entries: Reference.all(reference)}
    end
  end

  defp verdict_pass?(verdict) do
    Map.get(verdict.meta, :pass, Map.get(verdict.meta, "pass", false))
  end

  defp latest_change_stat(reference, organ_author) do
    reference
    |> Reference.all()
    |> Enum.filter(&(&1.type == :change and &1.status == :active and &1.author == organ_author))
    |> Enum.sort_by(&entry_number(&1.id), :desc)
    |> case do
      [%{text: text} | _] ->
        case Regex.run(~r/^実装変更 r\d+: (.+?) \/ テスト:/u, text, capture: :all_but_first) do
          [stat] -> stat
          _ -> ""
        end

      [] ->
        ""
    end
  end

  defp entry_number(id) do
    case Integer.parse(String.trim_leading(id, "e")) do
      {number, _rest} -> number
      :error -> 0
    end
  end

  defp issue_first_line(issue_dir) do
    issue_dir
    |> Path.join("issue.md")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> List.first()
    |> Kernel.||("")
    |> String.slice(0, 60)
  end

  defp issue_slug(issue_dir), do: issue_dir |> Path.expand() |> Path.basename()

  defp maybe_append_policy(citations, nil), do: citations
  defp maybe_append_policy(citations, policy_id), do: citations ++ [policy_id]

  defp push_pr_after_apply!(reference, actors, issue_dir, state, %Workspace{git_mode: :pr} = ws) do
    branch = Workspace.branch_name(ws, issue_slug(issue_dir))
    create_pr? = not Map.has_key?(state, "pr_url")
    title = "tracefield: #{issue_first_line(issue_dir)}"
    body = pr_body(reference, actors, issue_dir, ws)

    {:ok, url} = Workspace.push_and_create_pr!(ws, branch, title, body, create_pr?)

    cond do
      is_binary(url) and url != "" ->
        Mix.shell().info("PR: #{url}")
        Map.put(state, "pr_url", url)

      pr_url = Map.get(state, "pr_url") ->
        Mix.shell().info("PR 更新: push 済み（#{pr_url}）")
        state

      true ->
        state
    end
  end

  defp push_pr_after_apply!(_reference, _actors, _issue_dir, state, _ws), do: state

  defp pr_body(reference, actors, issue_dir, ws) do
    change_ids = organ_change_ids(reference, ws.organ_author)

    decision_ids =
      reference
      |> approved_design_decisions(actors)
      |> Enum.map(& &1.id)

    policy_text =
      reference
      |> Reference.all()
      |> Enum.filter(&(&1.type == :policy and &1.author == "POLICY" and &1.status == :active))
      |> Enum.find_value(fn entry ->
        if Map.get(entry.meta, :kind, Map.get(entry.meta, "kind")) == "effective_policy" do
          entry.text
        end
      end)
      |> Kernel.||("-")

    [
      "issue: #{Path.basename(issue_dir)}",
      "changes: #{Enum.join(change_ids, " ")}",
      "decisions: #{Enum.join(decision_ids, " ")}",
      "policy: #{policy_text}",
      "",
      "Generated by tracefield pipeline"
    ]
    |> Enum.join("\n")
  end

  defp preserve_pr_url(target, source) do
    case Map.get(source, "pr_url") do
      url when is_binary(url) and url != "" -> Map.put(target, "pr_url", url)
      _other -> target
    end
  end

  defp print_git_flow(ws, issue_dir) do
    policy = Workspace.git_policy(ws, issue_slug(issue_dir))
    Mix.shell().info("git flow: #{ws.git_mode} (branch=#{policy.branch})")
  end

  defp load_workspace!(issue_dir, opts) do
    Workspace.load!(issue_dir, git_policy(opts))
  end

  defp git_policy(opts) do
    opts
    |> Keyword.fetch!(:policy)
    |> Map.fetch!("git")
  end

  defp print_qa_done_from_issue(reference, issue_dir, state, opts) do
    ws =
      issue_dir
      |> Workspace.load!(git_policy(opts))
      |> Workspace.resolve_flow_path!(issue_slug(issue_dir))

    print_qa_done(reference, issue_dir, ws, state)
  end

  defp print_qa_done(reference, _issue_dir, ws, state) do
    entries = Reference.all(reference)
    verdicts = Enum.filter(entries, &(&1.type == :verdict and &1.status == :active))

    {head_sha, _} =
      System.cmd("git", ["rev-parse", "--short", "HEAD"], cd: ws.path, stderr_to_stdout: true)

    Mix.shell().info("Tracefield Dev qa done")
    Mix.shell().info("verdicts: #{length(verdicts)}")
    Mix.shell().info("workspace HEAD: #{String.trim(head_sha)}")
    print_pr_url(state)
    Mix.shell().info("provenance: #{qa_provenance_chain(entries, ws.organ_author)}")
  end

  defp qa_provenance_chain(entries, organ_author) do
    by_id = Map.new(entries, &{&1.id, &1})

    verdict_hop =
      entries
      |> Enum.filter(&(&1.type == :verdict and &1.status == :active and &1.author == "QA"))
      |> Enum.find_value(fn verdict ->
        requirement_id =
          Enum.find(verdict.citations, fn id ->
            case Map.get(by_id, id) do
              %{type: :requirement} -> true
              _other -> false
            end
          end)

        change_id =
          Enum.find(verdict.citations, fn id ->
            case Map.get(by_id, id) do
              %{type: :change, author: ^organ_author} -> true
              _other -> false
            end
          end)

        if requirement_id && change_id do
          {verdict, Map.fetch!(by_id, change_id), Map.fetch!(by_id, requirement_id)}
        end
      end)

    with {verdict, change, requirement} <- verdict_hop,
         decision_id when not is_nil(decision_id) <-
           Enum.find(change.citations, fn id ->
             case Map.get(by_id, id) do
               %{type: :decision} -> true
               _other -> false
             end
           end),
         decision <- Map.fetch!(by_id, decision_id),
         issue_id when not is_nil(issue_id) <-
           Enum.find(requirement.citations, fn id ->
             case Map.get(by_id, id) do
               %{type: :chunk, author: "ISSUE"} -> true
               _other -> false
             end
           end),
         issue <- Map.fetch!(by_id, issue_id) do
      "#{verdict.id} verdict -> #{change.id} change -> #{decision.id} decision -> #{requirement.id} requirement -> #{issue.id} issue chunk (#{Map.get(issue.meta, :file, "issue.md")})"
    else
      _missing -> "verdict -> change -> decision -> requirement -> issue chunk: unavailable"
    end
  end

  defp print_implement_done(reference, _actors, _issue_dir, state, ws) do
    entries = Reference.all(reference)
    changes = Enum.filter(entries, &(&1.type == :change and &1.status == :active))

    {head_sha, _} =
      System.cmd("git", ["rev-parse", "--short", "HEAD"], cd: ws.path, stderr_to_stdout: true)

    Mix.shell().info("Tracefield Dev implement done")
    Mix.shell().info("changes: #{length(changes)}")
    Mix.shell().info("workspace HEAD: #{String.trim(head_sha)}")
    print_pr_url(state)
    Mix.shell().info("provenance: #{implement_provenance_chain(entries, ws.organ_author)}")
  end

  defp print_pr_url(%{"pr_url" => url}) when is_binary(url) and url != "" do
    Mix.shell().info("PR: #{url}")
  end

  defp print_pr_url(_state), do: :ok

  defp implement_provenance_chain(entries, organ_author) do
    by_id = Map.new(entries, &{&1.id, &1})

    change_hop =
      entries
      |> Enum.filter(&(&1.type == :change and &1.status == :active and &1.author == organ_author))
      |> Enum.find_value(fn change ->
        change.citations
        |> Enum.find(fn id ->
          case Map.get(by_id, id) do
            %{type: :decision} -> true
            _other -> false
          end
        end)
        |> case do
          nil -> nil
          decision_id -> {change, Map.fetch!(by_id, decision_id)}
        end
      end)

    with {change, decision} <- change_hop,
         requirement_id when not is_nil(requirement_id) <-
           Enum.find(decision.citations, fn id ->
             case Map.get(by_id, id) do
               %{type: :requirement} -> true
               _other -> false
             end
           end),
         requirement <- Map.fetch!(by_id, requirement_id),
         issue_id when not is_nil(issue_id) <-
           Enum.find(requirement.citations, fn id ->
             case Map.get(by_id, id) do
               %{type: :chunk, author: "ISSUE"} -> true
               _other -> false
             end
           end) do
      issue = Map.fetch!(by_id, issue_id)

      "#{change.id} change -> #{decision.id} decision -> #{requirement.id} requirement -> #{issue.id} issue chunk (#{Map.get(issue.meta, :file, "issue.md")})"
    else
      _missing -> "change -> decision -> requirement -> issue chunk: unavailable"
    end
  end

  defp run_llm_rounds(
         reference,
         actors,
         issue_dir,
         procedure_id,
         rounds,
         opts,
         ref_docs,
         expected_types,
         stage
       ) do
    actors
    |> Enum.filter(&(&1.kind in [:llm, :cli]))
    |> then(fn machine_actors ->
      Enum.each(rounds, fn round ->
        Enum.each(machine_actors, fn actor ->
          {_agent, _absorbed, _perception} =
            actor
            |> build_agent(
              reference,
              issue_dir,
              procedure_id,
              opts,
              ref_docs,
              expected_types,
              actors,
              stage
            )
            |> Agent.run_turn(reference, round)
        end)
      end)
    end)
  end

  defp await_human(reference, actors, issue_dir, procedure_id, round, iteration, opts) do
    human = blocking_human!(actors)
    pending_path = human_pending_path(issue_dir, human, "refine")

    display_gate_warnings(compute_gate_warnings(reference, actors, opts, round, pending_path))
    apply_amend_pre_pass(reference, pending_path, human.id)

    {_agent, _absorbed, _perception} =
      run_human_turn(
        reference,
        human,
        issue_dir,
        procedure_id,
        round,
        refine_human_opts(reference)
      )

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
        state = awaiting_state(issue_dir, human, round, iteration, "refine")
        print_awaiting(issue_dir, human, "refine")
        state
    end
  end

  defp await_design(reference, actors, issue_dir, procedure_id, round, iteration, opts) do
    human = blocking_human!(actors)
    pending_path = human_pending_path(issue_dir, human, "design")

    warn_uncited_decisions(reference, actors)
    display_gate_warnings(compute_gate_warnings(reference, actors, opts, round, pending_path))
    apply_amend_pre_pass(reference, pending_path, human.id)
    apply_reject_lines(reference, pending_path, human.id, actors)

    {_agent, _absorbed, _perception} =
      run_human_turn(
        reference,
        human,
        issue_dir,
        procedure_id,
        round,
        design_human_opts(reference, actors)
      )

    cond do
      design_complete?(reference, actors) ->
        state = %{
          "stage" => "design",
          "status" => "done",
          "round" => round,
          "iteration" => iteration
        }

        write_state!(issue_dir, state)
        write_design_md!(issue_dir, reference, actors)
        print_design_done(reference, actors, issue_dir)
        state

      true ->
        state = awaiting_state(issue_dir, human, round, iteration, "design")
        print_awaiting(issue_dir, human, "design")
        state
    end
  end

  defp refine_human_opts(reference) do
    %{
      stage: "refine",
      approve_targets: active_ids(reference, :requirement),
      ref_docs: requirement_reference_docs(reference)
    }
  end

  defp design_human_opts(reference, actors) do
    %{
      stage: "design",
      approve_targets: gate_d_decision_ids(reference, actors),
      ref_docs: design_reference_docs(reference)
    }
  end

  defp run_human_turn(reference, human, issue_dir, procedure_id, round, human_opts) do
    human
    |> build_human_agent(reference, issue_dir, procedure_id, human_opts)
    |> Agent.run_turn(reference, round)
  end

  defp build_agent(
         actor,
         reference,
         issue_dir,
         procedure_id,
         opts,
         ref_docs,
         expected_types,
         actors,
         stage
       ) do
    Agent.new(
      actor.id,
      actor.domain,
      actor.desc,
      agent_build_opts(
        actor,
        reference,
        issue_dir,
        procedure_id,
        opts,
        ref_docs,
        expected_types,
        stage,
        actors
      )
    )
  end

  @doc false
  def agent_build_opts(
        actor,
        reference,
        issue_dir,
        procedure_id,
        opts,
        ref_docs,
        expected_types,
        stage \\ nil,
        actors \\ []
      ) do
    [
      anchor: File.read!(Path.join(issue_dir, "issue.md")),
      reference_docs: ref_docs || reference_docs(reference),
      private_doc: actor.private_doc,
      k_s: 10,
      adapter: adapter(actor, opts),
      cli: cli_config(opts),
      model: actor.model || Keyword.get(opts, :model, default_model(actor, opts)),
      temperature: Keyword.get(opts, :temperature, 0.4),
      seed: :erlang.phash2(actor.id),
      procedure_id: procedure_id,
      recruit_id: actor.recruit_entry,
      serve_policy: :diverse,
      expected_types: expected_types
    ]
    |> Kernel.++(sharing_agent_opts(opts, actor, stage, actors))
    |> Kernel.++(territory_agent_opts(actor, actors, opts))
    |> Kernel.++(patrol_agent_opts(actor, opts))
  end

  @doc false
  def machine_actor_ids(actors) do
    actors
    |> Enum.filter(&(&1.kind in [:llm, :cli]))
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp territory_agent_opts(actor, actors, opts) do
    case Keyword.get(opts, :territory_contract_id) do
      nil ->
        []

      territory_contract_id when actor.kind in [:llm, :cli] ->
        machine_actors = Enum.filter(actors, &(&1.kind in [:llm, :cli]))
        others = Enum.reject(machine_actors, &(&1.id == actor.id))

        [
          territory: %{
            self: actor,
            others: others,
            territory_contract_id: territory_contract_id
          }
        ]

      _other ->
        []
    end
  end

  defp patrol_agent_opts(actor, opts) do
    with policy when is_map(policy) <- Keyword.get(opts, :policy),
         true <- actor.kind in [:llm, :cli] do
      mobilization = Map.get(policy, "mobilization", %{})
      patrol = Map.get(mobilization, "patrol", %{})

      [
        patrol: %{
          enabled: Map.get(patrol, "enabled", true),
          token_threshold: Map.get(patrol, "token_threshold", 100_000)
        }
      ]
    else
      _ -> []
    end
  end

  defp sharing_agent_opts(opts, actor, stage, actors) do
    with policy when is_map(policy) <- Keyword.get(opts, :policy),
         stage when is_binary(stage) <- stage,
         true <- actor.kind in [:llm, :cli],
         "independent" <- Policy.sharing_mode(policy, stage) do
      [
        exclude_machine_authors: machine_actor_ids(actors),
        sharing_stage: stage
      ]
    else
      _ -> []
    end
  end

  defp build_human_agent(actor, reference, issue_dir, procedure_id, human_opts) do
    Agent.new(actor.id, actor.domain, actor.desc,
      anchor: File.read!(Path.join(issue_dir, "issue.md")),
      reference_docs: human_opts.ref_docs,
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
        stage: human_opts.stage,
        approve_targets: human_opts.approve_targets,
        question_ids: active_ids(reference, :question)
      }
    )
  end

  defp seed_design_procedure!(reference, opts) do
    [procedure] =
      Reference.absorb_idempotent(
        reference,
        [
          %{
            type: :procedure,
            text: design_procedure_text(opts),
            meta: %{stage: "design"}
          }
        ],
        "FACILITATOR"
      )

    procedure.id
  end

  defp design_reference_docs(reference) do
    reference_docs(reference) ++ active_requirement_docs(reference)
  end

  defp requirement_reference_docs(reference) do
    reference_docs(reference) ++ active_requirement_docs(reference)
  end

  defp active_requirement_docs(reference) do
    reference
    |> Reference.all()
    |> Enum.filter(&(&1.type == :requirement and &1.status == :active))
    |> Enum.map(&%{id: &1.id, file: "requirement", text: &1.text})
  end

  defp machine_decision_ids(reference, actors) do
    machine_authors =
      actors
      |> Enum.filter(&(&1.kind in [:llm, :cli]))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    reference
    |> Reference.all()
    |> Enum.filter(
      &(&1.type == :decision and &1.status == :active and
          MapSet.member?(machine_authors, &1.author))
    )
    |> Enum.map(& &1.id)
  end

  @doc false
  def gate_d_decision_ids(reference, actors) do
    requirement_ids = active_ids(reference, :requirement) |> MapSet.new()
    by_id = reference |> Reference.all() |> Map.new(&{&1.id, &1})

    reference
    |> machine_decision_ids(actors)
    |> Enum.filter(fn id ->
      case Map.get(by_id, id) do
        %{citations: citations} ->
          Enum.any?(citations, &MapSet.member?(requirement_ids, &1))

        _ ->
          false
      end
    end)
  end

  @doc false
  def warn_uncited_decisions(reference, actors) do
    gate_ids = MapSet.new(gate_d_decision_ids(reference, actors))
    by_id = reference |> Reference.all() |> Map.new(&{&1.id, &1})

    reference
    |> machine_decision_ids(actors)
    |> Enum.reject(&MapSet.member?(gate_ids, &1))
    |> Enum.each(fn id ->
      %{id: entry_id, author: author} = Map.fetch!(by_id, id)
      Mix.shell().info("⚠ requirement未引用のdecision: #{entry_id} (#{author})")
    end)
  end

  defp design_complete?(reference, actors) do
    machine_ids = MapSet.new(gate_d_decision_ids(reference, actors))

    human_ids =
      actors
      |> Enum.filter(&(&1.kind == :human))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    reference
    |> Reference.all()
    |> Enum.any?(fn entry ->
      entry.type == :decision and entry.status == :active and
        MapSet.member?(human_ids, entry.author) and
        Enum.any?(entry.citations, &MapSet.member?(machine_ids, &1))
    end)
  end

  defp write_design_md!(issue_dir, reference, actors) do
    machine_ids = MapSet.new(gate_d_decision_ids(reference, actors))

    decisions =
      reference
      |> Reference.all()
      |> Enum.filter(&MapSet.member?(machine_ids, &1.id))

    body =
      decisions
      |> Enum.map_join("\n\n", fn decision ->
        "### #{decision.id}（#{decision.author}）\n#{decision.text}\n\n根拠: #{format_citations(decision.citations)}"
      end)

    File.write!(Path.join(issue_dir, "design.md"), "# 設計判断\n\n#{body}\n")
  end

  defp format_citations([]), do: "-"
  defp format_citations(citations), do: Enum.map_join(citations, " ", &"[#{&1}]")

  defp warn_uncovered_chunks!(reference, actors, opts) do
    threshold = Keyword.get(opts, :coverage_threshold, 0.2)
    coverage_mode = Keyword.get(opts, :coverage_mode, :absolute)

    coverage_opts = [
      embed_adapter: Keyword.fetch!(opts, :embed_adapter),
      threshold: threshold,
      coverage_mode: coverage_mode
    ]

    {uncovered, detection_meta} =
      reference
      |> reference_docs()
      |> Coverage.analyze(actors, coverage_opts)

    display_warning? =
      uncovered != [] or Map.get(detection_meta, :insufficient_samples, false)

    if display_warning? do
      Mix.shell().info(Coverage.detection_warning(detection_meta))
    end

    if uncovered != [] do
      Enum.each(uncovered, fn item ->
        Mix.shell().info(
          "⚠ uncovered chunk #{item.id} (#{item.file}) — nearest: #{item.nearest_actor} (#{format_sim(item.sim)})"
        )
      end)

      if Keyword.get(opts, :recruit, false) do
        maybe_absorb_recruit_proposal!(reference, uncovered)
      end
    end
  end

  defp maybe_absorb_recruit_proposal!(reference, uncovered) do
    entry = build_recruit_entry(uncovered)
    before_ids = entry_ids(reference)

    [recruit] = Reference.absorb_idempotent(reference, [entry], "RECRUITER")

    unless MapSet.member?(before_ids, recruit.id) do
      Mix.shell().info("⚠ recruit 提案 #{recruit.id}: #{recruit.text}")
    end
  end

  defp build_recruit_entry(uncovered) do
    files = uncovered |> Enum.map(& &1.file) |> Enum.sort()
    basenames = Enum.map(files, &Path.basename/1)
    actor_id = derive_lens_id(files)
    domain = "territory"
    file_names = Enum.join(basenames, ", ")

    %{
      type: :recruit,
      text: "投入提案: 無人領土 #{file_names} を担当するレンズ。id候補 #{actor_id}、domain候補 #{domain}",
      citations: uncovered |> Enum.map(& &1.id) |> Enum.sort(),
      meta: %{
        actor_id: actor_id,
        domain: domain,
        desc: "無人領土 #{file_names} を担当するレンズ",
        territory_files: files
      }
    }
  end

  defp derive_lens_id(files) do
    files
    |> Enum.map(&Path.basename/1)
    |> Enum.map(&String.replace_suffix(&1, ".md", ""))
    |> Enum.map(&lens_segment/1)
    |> Enum.join("-")
    |> then(&"LENS-#{&1}")
  end

  defp lens_segment(name) do
    name
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]+/, "-")
    |> String.trim("-")
  end

  defp adopt_recruit!(reference, issue_dir, entry_id) do
    entry = Reference.get(reference, entry_id)

    cond do
      is_nil(entry) ->
        Mix.raise("recruit entry not found: #{entry_id}")

      entry.type != :recruit ->
        Mix.raise("entry #{entry_id} is not a recruit proposal")

      entry.status != :active ->
        Mix.raise("recruit entry #{entry_id} is not active")

      true ->
        actor_id = meta_string(entry.meta, :actor_id)
        domain = meta_string(entry.meta, :domain)
        desc = meta_string(entry.meta, :desc)
        path = actors_path(issue_dir)
        actors = Jason.decode!(File.read!(path))

        if Enum.any?(actors, &(&1["id"] == actor_id)) do
          Mix.raise("actor #{actor_id} already exists in actors.json")
        end

        new_actor = %{
          "id" => actor_id,
          "domain" => domain,
          "desc" => desc,
          "kind" => "llm",
          "recruit_entry" => entry_id
        }

        File.write!(path, Jason.encode!(actors ++ [new_actor], pretty: true))
        Mix.shell().info("採用: #{actor_id}（recruit #{entry_id}）を名簿に追加")
    end
  end

  defp meta_string(meta, key) when is_map(meta) do
    meta |> Map.get(key, Map.get(meta, Atom.to_string(key))) |> to_string()
  end

  defp format_sim(sim) do
    sim
    |> Float.round(3)
    |> :erlang.float_to_binary(decimals: 3)
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
      Mix.raise("dev pipeline requires a blocking human actor")
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

  defp awaiting_state(issue_dir, human, round, iteration, stage) do
    state = %{
      "stage" => stage,
      "status" => "awaiting_human",
      "round" => round,
      "iteration" => iteration,
      "pending" => pending_relative(issue_dir, human, stage)
    }

    write_state!(issue_dir, state)
    state
  end

  defp print_status(issue_dir, state, reference, actors, policy, policy_sources) do
    stats = Reference.stats(reference)
    Mix.shell().info("Tracefield Dev status")
    Mix.shell().info("issue: #{issue_dir}")
    Mix.shell().info("stage: #{state["stage"]}")
    Mix.shell().info("status: #{state["status"]}")
    print_pr_url(state)
    Mix.shell().info("effective policy:")

    policy
    |> flattened_policy_lines(policy_sources)
    |> Enum.each(fn line -> Mix.shell().info(line) end)

    Mix.shell().info(
      "store: #{Path.join(issue_dir, "store.jsonl")} entries=#{stats.entries} restored=#{stats.restored}"
    )

    print_retire_advice(reference, actors)
  end

  defp flattened_policy_lines(policy, sources) do
    policy
    |> flatten_policy()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} ->
      "  #{key}: #{format_policy_value(value)} (#{Map.fetch!(sources, key)})"
    end)
  end

  defp flatten_policy(map), do: flatten_policy(map, [])

  defp flatten_policy(map, prefix) when is_map(map) do
    Enum.flat_map(map, fn {key, value} ->
      flatten_policy(value, prefix ++ [to_string(key)])
    end)
  end

  defp flatten_policy(value, prefix), do: [{Enum.join(prefix, "."), value}]

  defp format_policy_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_policy_value(value) when is_binary(value), do: value
  defp format_policy_value(value), do: to_string(value)

  defp print_retire_advice(reference, actors) do
    entries = Reference.all(reference)
    active = Enum.filter(entries, &(&1.status == :active))

    actors
    |> Enum.filter(&(&1.kind in [:llm, :cli]))
    |> Enum.each(fn actor ->
      authored_ids =
        active
        |> Enum.filter(&(&1.author == actor.id))
        |> Enum.map(& &1.id)
        |> MapSet.new()

      if MapSet.size(authored_ids) > 0 do
        cited_count =
          active
          |> Enum.reject(&(&1.author == actor.id))
          |> Enum.count(fn entry ->
            Enum.any?(entry.citations, &MapSet.member?(authored_ids, &1))
          end)

        if cited_count == 0 do
          Mix.shell().info("⚠ retire候補: #{actor.id}（被引用 0）")
        end
      end
    end)
  end

  defp print_awaiting(issue_dir, human, stage) do
    Mix.shell().info("⏸ 人間の回答待ち: #{pending_relative(issue_dir, human, stage)}")
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

  defp print_design_done(reference, actors, issue_dir) do
    entries = Reference.all(reference)
    machine_ids = machine_decision_ids(reference, actors)

    Mix.shell().info("Tracefield Dev design done")
    Mix.shell().info("design decisions: #{length(machine_ids)}")
    Mix.shell().info("design.md: #{Path.join(issue_dir, "design.md")}")
    Mix.shell().info("provenance: #{design_provenance_chain(entries, machine_ids)}")
  end

  defp design_provenance_chain(entries, machine_ids) do
    by_id = Map.new(entries, &{&1.id, &1})
    machine_set = MapSet.new(machine_ids)

    requirement_hop =
      entries
      |> Enum.filter(&MapSet.member?(machine_set, &1.id))
      |> Enum.find_value(fn decision ->
        decision.citations
        |> Enum.find(fn id ->
          case Map.get(by_id, id) do
            %{type: :requirement} -> true
            _other -> false
          end
        end)
        |> case do
          nil -> nil
          requirement_id -> {decision, Map.fetch!(by_id, requirement_id)}
        end
      end)

    with {decision, requirement} <- requirement_hop,
         issue_id when not is_nil(issue_id) <-
           Enum.find(requirement.citations, fn id ->
             case Map.get(by_id, id) do
               %{type: :chunk, author: "ISSUE"} -> true
               _other -> false
             end
           end) do
      issue = Map.fetch!(by_id, issue_id)

      "#{decision.id} decision -> #{requirement.id} requirement -> #{issue.id} issue chunk (#{Map.get(issue.meta, :file, "issue.md")})"
    else
      _missing -> "decision -> requirement -> issue chunk: unavailable"
    end
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

  defp pending_relative(issue_dir, human, stage) do
    issue_dir
    |> Path.join("pending")
    |> then(&Path.join(&1, "#{human.id}-#{stage}.md"))
    |> Path.relative_to(issue_dir)
  end

  defp human_pending_path(issue_dir, human, stage) do
    Human.pending_path(%{
      pending_dir: Path.join(issue_dir, "pending"),
      actor_id: human.id,
      stage: stage
    })
  end

  @doc false
  def compute_gate_warnings(reference, actors, opts, round, pending_path) do
    if File.exists?(pending_path) do
      {[], 0}
    else
      policy = Keyword.fetch!(opts, :policy)
      warnings_cfg = Map.get(policy, "warnings", %{})
      entries = Reference.all(reference)
      unowned_cfg = Map.get(warnings_cfg, "unowned", %{})
      stale_cfg = Map.get(warnings_cfg, "stale", %{})
      mobilization_cfg = Map.get(warnings_cfg, "mobilization", %{})

      unowned_warnings =
        if warnings_enabled?(unowned_cfg) do
          gate_entries = machine_gate_entries(entries, actors)
          territories = actor_territories(actors)

          coverage_opts = [
            embed_adapter: Keyword.fetch!(opts, :embed_adapter),
            coverage_k: Map.get(unowned_cfg, "threshold", 1.0)
          ]

          Coverage.detect_unowned_entries(gate_entries, territories, coverage_opts)
        else
          []
        end

      {stale_warnings, skipped} =
        if warnings_enabled?(stale_cfg) do
          stale_rounds = Map.get(stale_cfg, "rounds", 2)
          Coverage.detect_stale_questions(entries, round, stale_rounds)
        else
          {[], 0}
        end

      mobilization_warnings =
        if warnings_enabled?(mobilization_cfg) do
          detect_mobilization_warnings(entries, actors, policy, opts)
        else
          []
        end

      {unowned_warnings ++ stale_warnings ++ mobilization_warnings, skipped}
    end
  end

  defp display_gate_warnings({warnings, skipped}) do
    Enum.each(warnings, fn warning -> Mix.shell().info(warning) end)

    if skipped > 0 do
      Mix.shell().info(
        "ℹ #{skipped} 件の質問は round メタデータ欠損のため老化判定を省略しました"
      )
    end
  end

  defp warnings_enabled?(cfg) do
    case Map.get(cfg, "enabled", true) do
      enabled when enabled in [true, false] -> enabled
      other -> Mix.raise("invalid warnings enabled policy #{inspect(other)}")
    end
  end

  defp machine_gate_entries(entries, actors) do
    machine_authors =
      actors
      |> Enum.filter(&(&1.kind in [:llm, :cli]))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    Enum.filter(entries, fn entry ->
      entry.status == :active and entry.type in @gate_entry_types and
        MapSet.member?(machine_authors, entry.author)
    end)
  end

  defp actor_territories(actors) do
    actors
    |> Enum.filter(&(&1.kind in [:llm, :cli]))
    |> Enum.map(fn actor ->
      {actor.id, Coverage.territory_text(actor.domain, actor.desc, actor.private_doc)}
    end)
  end

  defp detect_mobilization_warnings(entries, actors, policy, opts) do
    mobilization = Map.get(policy, "mobilization", %{})
    threshold = Map.get(mobilization, "similarity_threshold", 0.5)
    embed_adapter = Keyword.fetch!(opts, :embed_adapter)
    gate_entries = machine_gate_entries(entries, actors)

    coverage_opts = [
      embed_adapter: embed_adapter,
      threshold: threshold
    ]

    actors
    |> Enum.filter(&(&1.kind in [:llm, :cli]))
    |> Enum.flat_map(fn actor ->
      sections = Tracefield.Patrol.split_sections(actor.private_doc)

      actor_entries =
        Enum.filter(gate_entries, fn entry -> entry.author == actor.id end)

      result = Coverage.mobilization_rate(actor_entries, sections, coverage_opts)

      Logger.debug(mobilization_details: %{actor: actor.id, details: result.details})

      case Coverage.mobilization_warning(actor.id, result) do
        nil -> []
        warning -> [warning]
      end
    end)
  end

  @doc false
  def apply_amend_pre_pass(reference, pending_path, human_actor) do
    apply_amend_lines(reference, pending_path, human_actor)
  end

  @doc false
  def apply_amend_lines(reference, pending_path, human_actor) do
    if File.exists?(pending_path) do
      pending_path
      |> File.read!()
      |> amend_response_body()
      |> Enum.each(fn [_line, old_id, new_text] ->
        case Reference.get(reference, old_id) do
          nil ->
            Mix.shell().info("AMEND 警告: #{old_id} - entry が存在しません")

          %{type: :requirement, status: :active} = _entry ->
            inline_refs =
              ~r/\[(e\d+)\]/
              |> Regex.scan(new_text, capture: :all_but_first)
              |> List.flatten()
              |> Enum.uniq()

            citations = Enum.uniq([old_id | inline_refs])

            [new_entry] =
              Reference.absorb(
                reference,
                %{
                  type: :requirement,
                  text: new_text,
                  citations: citations,
                  meta: %{amends: old_id}
                },
                human_actor
              )

            Reference.quarantine(reference, [old_id])
            Mix.shell().info("要件修正: #{old_id} → #{new_entry.id}")

          %{type: type} when type != :requirement ->
            Mix.shell().info("AMEND 警告: #{old_id} - requirement 以外の entry です (#{type})")

          %{status: status} ->
            Mix.shell().info("AMEND 警告: #{old_id} - active ではありません (#{status})")
        end
      end)
    end

    reference
  end

  @doc false
  def apply_reject_lines(reference, pending_path, human_actor, actors) do
    if File.exists?(pending_path) do
      pending_path
      |> File.read!()
      |> reject_response_body()
      |> Enum.each(fn [_line, target_id, reason] ->
        case Reference.get(reference, target_id) do
          nil ->
            Mix.shell().info("REJECT 警告: #{target_id} - entry が存在しません")

          entry ->
            cond do
              entry.type != :decision ->
                Mix.shell().info(
                  "REJECT 警告: #{target_id} - decision 以外の entry です (#{entry.type})"
                )

              entry.status != :active ->
                Mix.shell().info(
                  "REJECT 警告: #{target_id} - active ではありません (#{entry.status})"
                )

              not rejectable_machine_decision?(reference, actors, target_id) ->
                Mix.shell().info(
                  "REJECT 警告: #{target_id} - 機械判断ではありません (#{entry.author})"
                )

              true ->
                Reference.quarantine(reference, [target_id])

                Reference.absorb(
                  reference,
                  %{
                    type: :observation,
                    text: "却下: #{reason}",
                    citations: [target_id],
                    meta: %{rejects: target_id}
                  },
                  human_actor
                )

                Mix.shell().info("判断却下: #{target_id}（#{reason}）")
            end
        end
      end)
    end

    reference
  end

  defp rejectable_machine_decision?(reference, actors, id) do
    id in machine_decision_ids(reference, actors)
  end

  defp reject_response_body(content) do
    content
    |> pending_response_body()
    |> then(&Regex.scan(~r/^REJECT (e\d+): (.+)$/m, &1))
  end

  defp amend_response_body(content) do
    content
    |> pending_response_body()
    |> then(&Regex.scan(~r/^AMEND (e\d+): (.+)$/m, &1))
  end

  defp pending_response_body(content) do
    case String.split(content, @response_heading, parts: 2) do
      [_before, after_heading] -> after_heading
      [_all] -> ""
    end
  end
end
