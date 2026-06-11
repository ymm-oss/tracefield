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

  test "dev refine start warns on uncovered chunks with chunk id and nearest actor" do
    dir = tmp_issue_dir()
    write_uncovered_issue_files!(dir)

    output =
      capture_io(fn ->
        Dev.run_dev(issue: dir, adapter: "mock")
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

  defp uncovered_fixture_chunks do
    [
      %{
        id: "e1",
        file: "docs/unrelated.md",
        text: "quantum entanglement superposition particle physics relativity cosmology"
      }
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
    %{id: "ARCH", domain: "architecture", desc: "architectural reviewer"}
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
