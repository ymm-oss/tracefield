defmodule Tracefield.TransferTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Tracefield.{Reference, Transfer}

  test "distill transfers experience summary, filters stale memory, updates agents, and leaves private doc behind" do
    %{a: a, b: b, active: active, stale: stale} = transfer_fixture()

    File.write!(
      Path.join([a, "memory", "X.jsonl"]),
      memory_line("valid active memory", [active.id]) <>
        memory_line("stale memory must not travel", [stale.id]) <>
        memory_line("valid unknown memory", ["unknown-e99"])
    )

    result = Transfer.move(a, b, "X", policy: :distill)

    assert result.policy == :distill
    assert result.stale_excluded == 1
    assert result.summary_entry.text =~ "経験サマリ（X, A より転籍）"
    assert result.summary_entry.text =~ "valid active memory"
    assert result.summary_entry.text =~ "valid unknown memory"
    refute result.summary_entry.text =~ "stale memory must not travel"
    assert result.summary_entry.author == "TRANSFER/X"
    assert result.summary_entry.meta.transfer_from == "A"
    assert result.summary_entry.meta.agent == "X"

    [b_agent] = agents(b)
    assert b_agent["id"] == "X"
    assert b_agent["model"] == "model-x"
    assert b_agent["procedure"] == "procedure-x.md"
    assert b_agent["private_doc"] == "X-experience.md"
    assert File.exists?(Path.join(b, "procedure-x.md"))
    assert File.read!(Path.join([b, "private", "X-experience.md"])) =~ "valid active memory"
    refute File.exists?(Path.join([b, "private", "x.md"]))
    assert File.read!(Path.join([b, "memory", "X.jsonl"])) == ""
    assert agents(a) == []
    refute File.exists?(Path.join([a, "memory", "X.jsonl"]))

    assert Enum.any?(store_entries(a), &(&1.text =~ "AGENT X が B へ転籍（distill）"))
  end

  test "fresh carries no memory and records arrival" do
    %{a: a, b: b, active: active} = transfer_fixture()
    File.write!(Path.join([a, "memory", "X.jsonl"]), memory_line("left behind", [active.id]))

    result = Transfer.move(a, b, "X", policy: :fresh)

    assert result.policy == :fresh
    assert result.summary_entry == nil
    [b_agent] = agents(b)
    assert b_agent["private_doc"] == "X-fresh.md"
    assert File.read!(Path.join([b, "private", "X-fresh.md"])) =~ "新任。私的知見はこれから蓄積"
    assert File.read!(Path.join([b, "memory", "X.jsonl"])) == ""
    refute File.read!(Path.join(b, "store.jsonl")) =~ "left behind"
    assert Enum.any?(store_entries(b), &(&1.text =~ "AGENT X が A から転入（fresh）"))
  end

  test "full copies valid memory verbatim and warns" do
    %{a: a, b: b, active: active} = transfer_fixture()

    memory =
      memory_line("copied active memory", [active.id]) <> memory_line("copied uncited memory")

    File.write!(Path.join([a, "memory", "X.jsonl"]), memory)
    parent = self()

    output =
      capture_io(fn ->
        send(parent, {:result, Transfer.move(a, b, "X", policy: :full)})
      end)

    assert_receive {:result, result}
    assert output =~ "機密注意"
    assert result.policy == :full
    assert result.summary_entry == nil
    assert File.read!(Path.join([b, "memory", "X.jsonl"])) == memory
    assert Enum.any?(store_entries(b), &(&1.text =~ "AGENT X が A から転入（full）"))
  end

  test "move returns validation errors for missing agent and existing target agent" do
    %{a: a, b: b} = transfer_fixture()

    assert {:error, :missing_agent} = Transfer.move(a, b, "NOPE")

    File.write!(
      Path.join(b, "agents.json"),
      Jason.encode!([%{id: "X", domain: "other", desc: "exists", private_doc: "other.md"}]) <>
        "\n"
    )

    assert {:error, :already_exists} = Transfer.move(a, b, "X")
  end

  test "transfer demo prints the required story" do
    Mix.Task.reenable("tracefield.transfer")

    output =
      capture_io(fn ->
        Mix.Tasks.Tracefield.Transfer.run(["--demo"])
      end)

    assert output =~ "tracefield.transfer demo"
    assert output =~ "stale exclusion: 1"
    assert output =~ "経験サマリ（X, A より転籍）"
    assert output =~ "transfer_from=A agent=X"
    assert output =~ ~s("private_doc": "X-experience.md")
    assert output =~ "AGENT X が B へ転籍（distill）"
  end

  defp transfer_fixture do
    base =
      Path.join(
        System.tmp_dir!(),
        "tracefield-transfer-test-#{System.unique_integer([:positive])}"
      )

    a = Path.join(base, "A")
    b = Path.join(base, "B")
    File.mkdir_p!(Path.join(a, "private"))
    File.mkdir_p!(Path.join(b, "private"))
    File.mkdir_p!(Path.join(a, "memory"))
    File.write!(Path.join(a, "task.md"), "A task\n")
    File.write!(Path.join(b, "task.md"), "B task\n")
    File.write!(Path.join(a, "procedure-x.md"), "X procedure\n")
    File.write!(Path.join([a, "private", "x.md"]), "cluster A private document\n")
    File.write!(Path.join(b, "agents.json"), "[]\n")

    File.write!(
      Path.join(a, "agents.json"),
      Jason.encode!(
        [
          %{
            id: "X",
            domain: "x",
            desc: "transfer target",
            private_doc: "x.md",
            model: "model-x",
            procedure: "procedure-x.md"
          }
        ],
        pretty: true
      ) <> "\n"
    )

    {:ok, ref} = Reference.start_link(persist_path: Path.join(a, "store.jsonl"))
    [active] = Reference.absorb(ref, [%{type: :observation, text: "active basis"}], "A")
    [stale] = Reference.absorb(ref, [%{type: :observation, text: "stale basis"}], "A")
    Reference.retract(ref, stale.id)
    GenServer.stop(ref)

    on_exit(fn -> File.rm_rf(base) end)
    %{a: a, b: b, active: active, stale: stale}
  end

  defp agents(dir) do
    dir |> Path.join("agents.json") |> File.read!() |> Jason.decode!()
  end

  defp store_entries(dir) do
    {:ok, ref} = Reference.start_link(persist_path: Path.join(dir, "store.jsonl"))
    entries = Reference.all(ref)
    GenServer.stop(ref)
    entries
  end

  defp memory_line(text, citations \\ []) do
    Jason.encode!(%{
      ts: "2026-06-10T00:00:00Z",
      mode: "converge",
      text: text,
      citations: citations
    }) <> "\n"
  end
end
