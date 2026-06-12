defmodule Tracefield.CoverageTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Tracefield.Dev
  alias Tracefield.{Coverage, Embed, Reference}

  @embed_opts [embed_adapter: Embed.Mock, threshold: 0.2]

  test "uncovered returns chunks below threshold with nearest actor" do
    chunks = [
      %{
        id: "e1",
        file: "docs/quantum.md",
        text: "quantum entanglement superposition particle physics relativity"
      }
    ]

    actors = [
      %{
        id: "ARCH",
        domain: "frontend",
        desc: "React UI components styling",
        kind: :llm,
        private_doc: "CSS flexbox grid layout"
      }
    ]

    [uncovered] = Coverage.uncovered(chunks, actors, @embed_opts)

    assert uncovered.id == "e1"
    assert uncovered.file == "docs/quantum.md"
    assert uncovered.nearest_actor == "ARCH"
    assert uncovered.sim < 0.2
  end

  test "uncovered returns empty when all chunks are covered" do
    text = "CLI駆動の詳細化パイプラインを実装する"

    chunks = [%{id: "e1", file: "issue.md", text: text}]

    actors = [
      %{
        id: "ARCH",
        domain: "architecture",
        desc: "CLI駆動の詳細化パイプライン設計",
        kind: :llm,
        private_doc: text
      }
    ]

    assert Coverage.uncovered(chunks, actors, @embed_opts) == []
  end

  test "uncovered ignores human actors even when they match the chunk" do
    chunks = [
      %{
        id: "e1",
        file: "docs/quantum.md",
        text: "quantum entanglement superposition particle physics relativity"
      }
    ]

    actors = [
      %{
        id: "ARCH",
        domain: "frontend",
        desc: "React UI components styling",
        kind: :llm,
        private_doc: "CSS flexbox grid layout"
      },
      %{
        id: "HUMAN",
        domain: "physics",
        desc: "quantum entanglement superposition particle physics relativity",
        kind: :human,
        private_doc: "quantum entanglement superposition particle physics relativity"
      }
    ]

    [uncovered] = Coverage.uncovered(chunks, actors, @embed_opts)
    assert uncovered.nearest_actor == "ARCH"
  end

  test "uncovered has no side effects on reference entries or state" do
    dir = tmp_issue_dir()
    write_issue_files!(dir)

    {:ok, reference} =
      Reference.start_link(
        persist_path: Path.join(dir, "store.jsonl"),
        embed_adapter: Embed.Mock
      )

    seed_reference!(reference, dir)
    entries_before = Reference.all(reference)
    state_before = Jason.decode!(File.read!(Path.join(dir, "state.json")))

    chunks = reference_docs(reference)
    actors = Dev.load_actors!(dir)

    assert Coverage.uncovered(chunks, actors, @embed_opts) != []

    assert Reference.all(reference) == entries_before
    assert Jason.decode!(File.read!(Path.join(dir, "state.json"))) == state_before
  end

  test "dev refine start defaults embed adapter to mock for reference and coverage" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)

    output =
      capture_io(fn ->
        result = Dev.run_dev(issue: dir, adapter: "mock")

        assert Enum.any?(result.entries, fn entry ->
                 entry.type == :chunk and entry.author == "ISSUE" and entry.embedding != []
               end)
      end)

    assert output =~ ~r/⚠ uncovered chunk e\d+ \(unrelated\.md\)/
    assert output =~ "nearest: ARCH"
  end

  test "dev refine start stays silent when all chunks are covered" do
    dir = tmp_issue_dir()
    write_covered_issue_files!(dir)

    output =
      capture_io(fn ->
        Dev.run_dev(issue: dir, adapter: "mock")
      end)

    refute output =~ "⚠ uncovered chunk"
    refute output =~ "⚠ coverage-threshold:"
  end

  test "detect_uncovered relative mode flags only the lower outlier in measured fixture" do
    scored = relative_fixture_chunks()

    {uncovered, meta} = Coverage.detect_uncovered(scored, coverage_mode: :relative)

    assert length(uncovered) == 1
    assert hd(uncovered).sim == 0.645
    assert_in_delta meta.cutoff, 0.648, 0.001
    assert_in_delta meta.median, 0.702, 0.001
    assert_in_delta meta.mad, 0.054, 0.001
    assert meta.k == 1.0
  end

  test "detect_uncovered relative mode returns empty for uniform similarities" do
    scored = [
      %{id: "e1", file: "a.md", nearest_actor: "ARCH", sim: 0.70},
      %{id: "e2", file: "b.md", nearest_actor: "ARCH", sim: 0.71},
      %{id: "e3", file: "c.md", nearest_actor: "ARCH", sim: 0.72}
    ]

    {uncovered, meta} = Coverage.detect_uncovered(scored, coverage_mode: :relative)

    assert uncovered == []
    assert_in_delta meta.cutoff, 0.70, 0.001
  end

  test "detect_uncovered absolute mode matches legacy threshold behavior" do
    scored = [
      %{id: "e1", file: "low.md", nearest_actor: "ARCH", sim: 0.15},
      %{id: "e2", file: "high.md", nearest_actor: "ARCH", sim: 0.85}
    ]

    {uncovered, meta} = Coverage.detect_uncovered(scored, threshold: 0.2)

    assert uncovered == [hd(scored)]
    assert meta == %{mode: :absolute, threshold: 0.2}
  end

  test "detect_uncovered relative mode warns with effective cutoff metadata" do
    scored = relative_fixture_chunks()

    {uncovered, meta} = Coverage.detect_uncovered(scored, coverage_mode: :relative)

    output =
      capture_io(fn ->
        Mix.shell().info(Coverage.detection_warning(meta))

        Enum.each(uncovered, fn item ->
          Mix.shell().info(
            "⚠ uncovered chunk #{item.id} (#{item.file}) — nearest: #{item.nearest_actor} (#{item.sim})"
          )
        end)
      end)

    assert output =~ "⚠ coverage-relative: cutoff=0.648 (median=0.702 MAD=0.054 k=1.000)"
    assert output =~ "⚠ uncovered chunk e3 (mobile-a11y.md)"
  end

  test "detect_uncovered relative mode skips detection when sample count is insufficient" do
    scored = [
      %{id: "e1", file: "a.md", nearest_actor: "ARCH", sim: 0.645},
      %{id: "e2", file: "b.md", nearest_actor: "ARCH", sim: 0.702}
    ]

    output =
      capture_io(fn ->
        assert Coverage.detect_uncovered(scored, coverage_mode: :relative) ==
                 {[], %{mode: :relative, insufficient_samples: true, n: 2}}
      end)

    assert output == ""
  end

  test "warn_uncovered_chunks! displays insufficient-sample note for relative mode" do
    dir = tmp_issue_dir()
    write_two_chunk_issue_files!(dir)

    output =
      capture_io(fn ->
        Dev.run_dev(issue: dir, adapter: "mock", coverage_mode: :relative)
      end)

    assert output =~ "⚠ coverage-relative: insufficient samples (N=2), skipping relative detection"
    refute output =~ "⚠ uncovered chunk"
  end

  test "detect_unowned_entries flags distant machine entries in relative mode" do
    territory = "frontend React UI components styling CSS flexbox grid layout"
    territories = [{"ARCH", territory}]

    entries = [
      %{id: "e1", type: :requirement, text: "React UI components styling flexbox grid layout"},
      %{id: "e2", type: :question, text: "frontend CSS flexbox grid layout components"},
      %{
        id: "e3",
        type: :observation,
        text: "quantum entanglement superposition particle physics relativity cosmology"
      }
    ]

    warnings =
      Coverage.detect_unowned_entries(entries, territories,
        embed_adapter: Embed.Mock,
        coverage_k: 1.0
      )

    assert length(warnings) == 1
    assert hd(warnings) =~ "⚠ 無人論点: e3 (observation)"
    assert hd(warnings) =~ "nearest: ARCH"
  end

  test "detect_unowned_entries stays silent for territory-aligned entries" do
    territory = "frontend React UI components styling CSS flexbox grid layout"
    territories = [{"ARCH", territory}]

    entries = [
      %{id: "e1", type: :requirement, text: "React UI components styling flexbox grid layout"},
      %{id: "e2", type: :question, text: "frontend CSS flexbox grid layout components"},
      %{id: "e3", type: :decision, text: "React UI flexbox grid layout styling components"}
    ]

    assert Coverage.detect_unowned_entries(entries, territories,
             embed_adapter: Embed.Mock,
             coverage_k: 1.0
           ) == []
  end

  test "detect_stale_questions warns after N rounds without human answer citation" do
    entries = [
      %{
        id: "e1",
        type: :question,
        status: :active,
        text: "未回答の質問",
        citations: [],
        meta: %{"round" => 1}
      },
      %{
        id: "e2",
        type: :question,
        status: :active,
        text: "まだ新しい質問",
        citations: [],
        meta: %{"round" => 3}
      },
      %{
        id: "e3",
        type: :answer,
        status: :active,
        text: "回答済み",
        citations: ["e4"],
        meta: %{}
      },
      %{
        id: "e4",
        type: :question,
        status: :active,
        text: "回答された質問",
        citations: [],
        meta: %{"round" => 1}
      }
    ]

    {warnings, skipped} = Coverage.detect_stale_questions(entries, 3, 2)

    assert skipped == 0
    assert warnings == ["⚠ 未回答の質問: e1（r1から放置）"]
    refute Enum.any?(warnings, &String.contains?(&1, "e4"))
  end

  test "detect_stale_questions skips questions without round metadata" do
    entries = [
      %{
        id: "e1",
        type: :question,
        status: :active,
        text: "round 欠損",
        citations: [],
        meta: %{}
      }
    ]

    assert Coverage.detect_stale_questions(entries, 5, 2) == {[], 1}
  end

  test "detect_unowned_entries and detect_stale_questions have no IO side effects" do
    entries = [
      %{
        id: "e1",
        type: :question,
        status: :active,
        text: "quantum entanglement superposition particle physics relativity cosmology",
        citations: [],
        meta: %{"round" => 1}
      }
    ]

    output =
      capture_io(fn ->
        Coverage.detect_unowned_entries(
          entries,
          [{"ARCH", "frontend React UI components styling"}],
          embed_adapter: Embed.Mock
        )

        Coverage.detect_stale_questions(entries, 3, 2)
      end)

    assert output == ""
  end

  test "detect_uncovered has no IO side effects" do
    scored = relative_fixture_chunks()

    output =
      capture_io(fn ->
        Coverage.detect_uncovered(scored, coverage_mode: :relative)
        Coverage.detect_uncovered(Enum.take(scored, 2), coverage_mode: :relative)
      end)

    assert output == ""
  end

  test "displayed coverage threshold matches value passed to Coverage.uncovered" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)
    threshold = 0.35

    output =
      capture_io(fn ->
        Dev.run_dev(issue: dir, adapter: "mock", coverage_threshold: threshold)
      end)

    assert output =~ "⚠ coverage-threshold: #{threshold}"

    displayed_threshold =
      output
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        case Regex.run(~r/^⚠ coverage-threshold: (.+)$/, line) do
          [_, value] -> String.to_float(value)
          _ -> nil
        end
      end)

    assert displayed_threshold == threshold

    uncovered_at_displayed =
      Coverage.uncovered(uncovered_fixture_chunks(), uncovered_fixture_actors(),
        embed_adapter: Embed.Mock,
        threshold: displayed_threshold
      )

    uncovered_at_passed =
      Coverage.uncovered(uncovered_fixture_chunks(), uncovered_fixture_actors(),
        embed_adapter: Embed.Mock,
        threshold: threshold
      )

    assert uncovered_at_displayed == uncovered_at_passed
  end

  defp tmp_issue_dir do
    dir = Path.join(System.tmp_dir!(), "tracefield-coverage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp write_issue_files!(dir) do
    File.mkdir_p!(Path.join(dir, "docs"))
    File.write!(Path.join(dir, "issue.md"), "CLI駆動の詳細化パイプラインを実装する")
    File.write!(Path.join(dir, "actors.json"), Jason.encode!([llm_actor(), human_actor()]))
    File.write!(Path.join(dir, "state.json"), Jason.encode!(%{"stage" => "refine", "status" => "new"}))
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
          kind: "llm",
          private_doc: "arch.md"
        },
        human_actor()
      ])
    )
  end

  defp write_two_chunk_issue_files!(dir) do
    File.mkdir_p!(Path.join(dir, "docs"))
    File.mkdir_p!(Path.join(dir, "private"))
    File.write!(Path.join(dir, "issue.md"), "CLI駆動の詳細化パイプラインを実装する")

    File.write!(
      Path.join([dir, "docs", "extra.md"]),
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
          kind: "llm",
          private_doc: "arch.md"
        },
        human_actor()
      ])
    )

    File.write!(Path.join(dir, "state.json"), Jason.encode!(%{"stage" => "refine", "status" => "new"}))
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
          kind: "llm",
          private_doc: "arch.md"
        },
        human_actor()
      ])
    )
  end

  defp uncovered_fixture_chunks do
    [
      %{
        id: "e1",
        file: "docs/unrelated.md",
        text: "quantum entanglement superposition particle physics relativity cosmology"
      }
    ]
  end

  defp relative_fixture_chunks do
    [
      %{id: "e1", file: "issue.md", nearest_actor: "ARCH", sim: 0.702},
      %{id: "e2", file: "architecture-notes.md", nearest_actor: "ARCH", sim: 0.756},
      %{id: "e3", file: "mobile-a11y.md", nearest_actor: "ARCH", sim: 0.645}
    ]
  end

  defp uncovered_fixture_actors do
    [
      %{
        id: "ARCH",
        domain: "frontend",
        desc: "React UI components styling",
        kind: :llm,
        private_doc: "CSS flexbox grid layout"
      },
      human_actor()
    ]
  end

  defp llm_actor do
    %{id: "ARCH", domain: "architecture", desc: "architectural reviewer", kind: "llm"}
  end

  defp human_actor do
    %{id: "HUMAN", domain: "review", desc: "human reviewer", kind: "human"}
  end

  defp seed_reference!(reference, dir) do
    issue_path = Path.join(dir, "issue.md")

    Reference.absorb_idempotent(
      reference,
      [
        %{
          type: :chunk,
          author: "ISSUE",
          text: File.read!(issue_path),
          meta: %{file: "issue.md"}
        },
        %{
          type: :chunk,
          author: "DOCS",
          text: "quantum entanglement superposition particle physics relativity cosmology",
          meta: %{file: "docs/unrelated.md"}
        }
      ],
      "ISSUE"
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
end
