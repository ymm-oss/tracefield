defmodule Tracefield.RecruitTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Tracefield.Dev
  alias Tracefield.{Agent, Reference}

  defmodule RecruitCitationMock do
    @behaviour Tracefield.LLM

    @impl true
    def complete(messages, _opts) do
      prompt = Enum.map_join(messages, "\n", &Map.get(&1, :content, Map.get(&1, "content", "")))

      entries =
        if String.contains?(prompt, "PRESENTED ENTRIES:") do
          foreign_id =
            case Regex.run(~r/^ENTRY\s+(e\d+)\s+author=/m, prompt, capture: :all_but_first) do
              [id] -> id
              _ -> "e1"
            end

          [%{type: "requirement", text: "recruited lens requirement", citations: [foreign_id]}]
        else
          []
        end

      {:ok, Jason.encode!(%{entries: entries})}
    end
  end

  test "recruit proposal is generated when uncovered chunks exist and recruit flag is set" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)

    output =
      capture_io(fn ->
        result = Dev.run_dev(issue: dir, adapter: "mock", recruit: true)

        recruit =
          Enum.find(result.entries, fn entry ->
            entry.type == :recruit and entry.author == "RECRUITER"
          end)

        assert recruit
        assert recruit.status == :active
        assert recruit.text =~ "投入提案: 無人領土 unrelated.md"
        assert recruit.text =~ "id候補 LENS-UNRELATED"
        assert recruit.text =~ "domain候補 territory"

        assert recruit.meta[:actor_id] == "LENS-UNRELATED"
        assert recruit.meta[:domain] == "territory"
        assert recruit.meta[:desc] =~ "unrelated.md"
        assert recruit.meta[:territory_files] == ["unrelated.md"]

        chunk_ids =
          result.entries
          |> Enum.filter(&(&1.type == :chunk and &1.author == "DOCS"))
          |> Enum.map(& &1.id)

        assert Enum.sort(recruit.citations) == Enum.sort(chunk_ids)
      end)

    assert output =~ ~r/⚠ recruit 提案 e\d+:/
  end

  test "recruit proposal is not generated without recruit flag" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)

    capture_io(fn ->
      result = Dev.run_dev(issue: dir, adapter: "mock")

      refute Enum.any?(result.entries, &(&1.type == :recruit))
    end)
  end

  test "recruit proposal is not generated when all chunks are covered" do
    dir = tmp_issue_dir()
    write_covered_issue_files!(dir)

    capture_io(fn ->
      result = Dev.run_dev(issue: dir, adapter: "mock", recruit: true)

      refute Enum.any?(result.entries, &(&1.type == :recruit))
    end)
  end

  test "recruit proposal absorb is idempotent on rerun" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)

    first =
      capture_io(fn ->
        Dev.run_dev(issue: dir, adapter: "mock", recruit: true)
      end)

    File.write!(
      Path.join(dir, "state.json"),
      Jason.encode!(%{"stage" => "refine", "status" => "new"})
    )

    second =
      capture_io(fn ->
        result = Dev.run_dev(issue: dir, adapter: "mock", recruit: true)

        recruits = Enum.filter(result.entries, &(&1.type == :recruit))
        assert length(recruits) == 1
      end)

    assert first =~ ~r/⚠ recruit 提案 e\d+:/
    refute second =~ ~r/⚠ recruit 提案 e\d+:/
  end

  test "adopt-recruit appends actor to actors.json and load_actors! reads recruit_entry" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)

    capture_io(fn ->
      Dev.run_dev(issue: dir, adapter: "mock", recruit: true)
    end)

    recruit = recruit_entry_from_dir(dir)

    output =
      capture_io(fn ->
        Dev.run_dev(issue: dir, adopt_recruit: recruit.id)
      end)

    assert output =~ "採用: LENS-UNRELATED（recruit #{recruit.id}）を名簿に追加"

    actors = Jason.decode!(File.read!(Path.join(dir, "actors.json")))
    adopted = Enum.find(actors, &(&1["id"] == "LENS-UNRELATED"))

    assert adopted["domain"] == "territory"
    assert adopted["desc"] =~ "unrelated.md"
    assert adopted["kind"] == "llm"
    assert adopted["recruit_entry"] == recruit.id

    [loaded] = Enum.filter(Dev.load_actors!(dir), &(&1.id == "LENS-UNRELATED"))
    assert loaded.recruit_entry == recruit.id
  end

  test "adopt-recruit raises for inactive recruit proposal" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)

    capture_io(fn ->
      Dev.run_dev(issue: dir, adapter: "mock", recruit: true)
    end)

    recruit = recruit_entry_from_dir(dir)

    {:ok, reference} =
      Reference.start_link(
        persist_path: Path.join(dir, "store.jsonl"),
        embed_adapter: Tracefield.Embed.Mock
      )

    Reference.retract(reference, recruit.id)

    assert_raise Mix.Error, ~r/not active/, fn ->
      Dev.run_dev(issue: dir, adopt_recruit: recruit.id)
    end
  end

  test "adopt-recruit raises when actor id already exists" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)

    capture_io(fn ->
      Dev.run_dev(issue: dir, adapter: "mock", recruit: true)
    end)

    recruit = recruit_entry_from_dir(dir)

    capture_io(fn ->
      Dev.run_dev(issue: dir, adopt_recruit: recruit.id)
    end)

    assert_raise Mix.Error, ~r/already exists/, fn ->
      Dev.run_dev(issue: dir, adopt_recruit: recruit.id)
    end
  end

  test "recruit_id agent entries cite recruit proposal and retract quarantines closure" do
    {:ok, ref} = Reference.start_link()

    [foreign] =
      Reference.absorb(ref, [%{text: "foreign context", meta: %{domain: "territory"}}], "ARCH")

    [recruit] =
      Reference.absorb(
        ref,
        [
          %{
            type: :recruit,
            text: "投入提案",
            citations: [foreign.id],
            meta: %{actor_id: "LENS-TEST", domain: "territory", desc: "test lens"}
          }
        ],
        "RECRUITER"
      )

    agent =
      Agent.new("LENS-TEST", "territory", "test lens",
        anchor: "issue",
        k_s: 2,
        adapter: RecruitCitationMock,
        model: "mock",
        recruit_id: recruit.id
      )

    {_agent, absorbed, _perception} = Agent.run_turn(agent, ref, 1)

    assert [%{citations: citations}] = absorbed
    assert recruit.id in citations

    closure = Reference.retract(ref, recruit.id)
    assert Enum.any?(closure, &(&1.author == "LENS-TEST"))

    Reference.quarantine(ref, Enum.map(closure, & &1.id))

    assert Enum.all?(closure, fn entry ->
      Reference.get(ref, entry.id).status == :superseded
    end)

    assert Reference.get(ref, recruit.id).status == :retracted
  end

  test "status shows retire advice for uncited actors with own entries" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    capture_io(fn ->
      Dev.run_dev(issue: dir, adapter: "mock")
    end)

    output =
      capture_io(fn ->
        Dev.run_dev(issue: dir, status: true)
      end)

    assert output =~ "⚠ retire候補: ARCH（被引用 0）"
  end

  test "status omits retire advice when actor entries are cited" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    capture_io(fn ->
      Dev.run_dev(issue: dir, adapter: "mock")
    end)

    {:ok, reference} =
      Reference.start_link(
        persist_path: Path.join(dir, "store.jsonl"),
        embed_adapter: Tracefield.Embed.Mock
      )

    arch_entry =
      reference
      |> Reference.all()
      |> Enum.find(&(&1.author == "ARCH" and &1.status == :active))

    Reference.absorb(
      reference,
      [%{type: :decision, text: "cites arch", citations: [arch_entry.id]}],
      "HUMAN"
    )

    output =
      capture_io(fn ->
        Dev.run_dev(issue: dir, status: true)
      end)

    refute output =~ "⚠ retire候補: ARCH"
  end

  test "e2e recruit adopt participate retract and quarantine recruited actor entries" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)

    capture_io(fn ->
      Dev.run_dev(issue: dir, adapter: "mock", recruit: true, rounds: 1)
    end)

    recruit = recruit_entry_from_dir(dir)

    capture_io(fn ->
      Dev.run_dev(issue: dir, adopt_recruit: recruit.id)
    end)

    File.write!(
      Path.join(dir, "state.json"),
      Jason.encode!(%{"stage" => "refine", "status" => "new"})
    )

    capture_io(fn ->
      Dev.run_dev(issue: dir, adapter: "mock", rounds: 1)
    end)

    {:ok, reference} =
      Reference.start_link(
        persist_path: Path.join(dir, "store.jsonl"),
        embed_adapter: Tracefield.Embed.Mock
      )

    lens_entries =
      reference
      |> Reference.all()
      |> Enum.filter(&(&1.author == "LENS-UNRELATED" and &1.status == :active))

    assert lens_entries != []
    assert Enum.all?(lens_entries, &(recruit.id in &1.citations))

    closure = Reference.retract(reference, recruit.id)
    Reference.quarantine(reference, Enum.map(closure, & &1.id))

    assert Enum.any?(closure, &(&1.author == "LENS-UNRELATED"))

    assert Enum.all?(closure, fn entry ->
      Reference.get(reference, entry.id).status == :superseded
    end)
  end

  defp recruit_entry_from_dir(dir) do
    {:ok, reference} =
      Reference.start_link(
        persist_path: Path.join(dir, "store.jsonl"),
        embed_adapter: Tracefield.Embed.Mock
      )

    reference
    |> Reference.all()
    |> Enum.find(&(&1.type == :recruit and &1.author == "RECRUITER"))
  end

  defp tmp_issue_dir do
    dir = Path.join(System.tmp_dir!(), "tracefield-recruit-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp write_issue_files!(dir) do
    File.mkdir_p!(Path.join(dir, "docs"))
    File.write!(Path.join(dir, "issue.md"), "CLI駆動の詳細化パイプラインを実装する")
    File.write!(Path.join([dir, "docs", "reference.md"]), "受入基準はテストがgreenであること")
    File.write!(Path.join(dir, "actors.json"), Jason.encode!([llm_actor(), human_actor()]))
  end

  defp write_uncovered_issue_files!(dir) do
    File.mkdir_p!(Path.join(dir, "docs"))
    File.mkdir_p!(Path.join(dir, "private"))
    File.write!(Path.join(dir, "issue.md"), "CLI駆動の詳細化パイプラインを実装する")

    File.write!(
      Path.join([dir, "docs", "unrelated.md"]),
      "quantum entanglement superposition particle physics relativity cosmology"
    )

    File.write!(Path.join([dir, "private", "arch.md"]), "CSS flexbox grid layout")

    File.write!(
      Path.join(dir, "actors.json"),
      Jason.encode!([
        %{
          id: "ARCH",
          domain: "frontend",
          desc: "React UI components styling",
          private_doc: "arch.md"
        },
        human_actor()
      ])
    )
  end

  defp write_covered_issue_files!(dir) do
    text = "CLI駆動の詳細化パイプラインを実装する"
    File.mkdir_p!(Path.join(dir, "docs"))
    File.mkdir_p!(Path.join(dir, "private"))
    File.write!(Path.join(dir, "issue.md"), text)

    File.write!(
      Path.join([dir, "docs", "reference.md"]),
      "受入基準はテストがgreenであること。CLI駆動の詳細化パイプライン。"
    )

    File.write!(Path.join([dir, "private", "arch.md"]), text)

    File.write!(
      Path.join(dir, "actors.json"),
      Jason.encode!([
        %{
          id: "ARCH",
          domain: "architecture",
          desc: "CLI駆動の詳細化パイプライン設計",
          private_doc: "arch.md"
        },
        human_actor()
      ])
    )
  end

  defp llm_actor do
    %{id: "ARCH", domain: "architecture", desc: "architectural reviewer"}
  end

  defp human_actor do
    %{id: "HUMAN", domain: "review", desc: "human reviewer", kind: "human"}
  end
end
