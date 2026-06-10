defmodule Tracefield.ReferenceTest do
  use ExUnit.Case

  alias Tracefield.Reference

  test "absorb assigns ids, versions, and embeddings" do
    {:ok, ref} = Reference.start_link()

    [entry] = Reference.absorb(ref, [%{type: :belief, text: "security access concern"}], "SEC")

    assert entry.id == "e1"
    assert entry.version == 1
    assert entry.author == "SEC"
    assert entry.status == :active
    assert is_list(entry.embedding)
    assert length(entry.embedding) > 0
    assert Reference.get(ref, "e1") == entry
  end

  test "absorb accepts procedure entries" do
    {:ok, ref} = Reference.start_link()

    [entry] =
      Reference.absorb(ref, [%{type: :procedure, text: "contrast procedure"}], "FACILITATOR")

    assert entry.type == :procedure
    assert entry.author == "FACILITATOR"
  end

  test "serve applies k, active status, exclude_author, only_author, and cosine order" do
    {:ok, ref} = Reference.start_link()

    [security] = Reference.absorb(ref, [%{text: "security access control"}], "SEC")
    [_business] = Reference.absorb(ref, [%{text: "quarterly revenue planning"}], "BIZ")

    [_retracted] =
      Reference.absorb(ref, [%{text: "security access control", status: :retracted}], "OLD")

    [_superseded] =
      Reference.absorb(ref, [%{text: "security access control", status: :superseded}], "OLD")

    served = Reference.serve(ref, "security access control", k: 1)
    assert Enum.map(served, & &1.id) == [security.id]

    assert Reference.serve(ref, "security access control", k: 4, exclude_author: "SEC")
           |> Enum.all?(&(&1.author != "SEC"))

    assert Reference.serve(ref, "security access control", k: 4, only_author: "BIZ")
           |> Enum.all?(&(&1.author == "BIZ"))
  end

  test "serve policy diverse returns newest author-balanced round robin excluding procedures" do
    {:ok, ref} = Reference.start_link()

    [a_old] = Reference.absorb(ref, [%{text: "a old"}], "A")
    [b_old] = Reference.absorb(ref, [%{text: "b old"}], "B")
    [c_old] = Reference.absorb(ref, [%{text: "c old"}], "C")
    [a_new] = Reference.absorb(ref, [%{text: "a new"}], "A")
    [b_new] = Reference.absorb(ref, [%{text: "b new"}], "B")
    [_procedure] = Reference.absorb(ref, [%{type: :procedure, text: "c procedure"}], "C")
    [c_new] = Reference.absorb(ref, [%{text: "c new"}], "C")
    [_requester] = Reference.absorb(ref, [%{text: "requester latest"}], "REQ")

    served =
      Reference.serve(ref, "ignored for diverse",
        k: 6,
        exclude_author: "REQ",
        policy: :diverse
      )

    assert Enum.map(served, & &1.id) == [
             c_new.id,
             b_new.id,
             a_new.id,
             c_old.id,
             b_old.id,
             a_old.id
           ]

    refute Enum.any?(served, &(&1.type == :procedure))
    refute Enum.any?(served, &(&1.author == "REQ"))
  end

  test "retract marks the target and returns active multi-hop reverse-citation closure" do
    {:ok, ref} = Reference.start_link()

    [e1] = Reference.absorb(ref, [%{text: "root"}], "A")
    [e2] = Reference.absorb(ref, [%{text: "depends on root", citations: [e1.id]}], "B")
    [e3] = Reference.absorb(ref, [%{text: "depends on middle", citations: [e2.id]}], "C")

    [_inactive] =
      Reference.absorb(ref, [%{text: "inactive", status: :superseded, citations: [e1.id]}], "D")

    pure_closure = Reference.closure(Reference.all(ref), e1.id)
    closure = Reference.retract(ref, e1.id)

    assert MapSet.new(Enum.map(pure_closure, & &1.id)) == MapSet.new([e2.id, e3.id])
    assert MapSet.new(Enum.map(closure, & &1.id)) == MapSet.new([e2.id, e3.id])
    assert Reference.get(ref, e1.id).status == :retracted
  end

  test "verify grounds citations with mock rules and always accepts procedure citations" do
    {:ok, ref} = Reference.start_link()

    [procedure] = Reference.absorb(ref, [%{type: :procedure, text: "adopted procedure"}], "FAC")
    [support] = Reference.absorb(ref, [%{text: "solar comfort finance support"}], "A")
    [unrelated] = Reference.absorb(ref, [%{text: "zzzz yyyy xxxx"}], "B")

    [claim] =
      Reference.absorb(
        ref,
        [
          %{
            text: "solar comfort plan reduces budget risk",
            citations: [support.id, unrelated.id, procedure.id]
          }
        ],
        "C"
      )

    judgments = Reference.verify(ref, [claim], judge_adapter: Tracefield.LLM.Mock)

    assert judgments[{claim.id, support.id}]
    refute judgments[{claim.id, unrelated.id}]
    assert judgments[{claim.id, procedure.id}]
  end

  test "quarantine supersedes active ids and most_cited chooses active non-procedure by count" do
    {:ok, ref} = Reference.start_link()

    [_chunk] = Reference.absorb(ref, [%{type: :chunk, text: "task"}], "TASK")
    [a] = Reference.absorb(ref, [%{text: "candidate a"}], "A")
    [b] = Reference.absorb(ref, [%{text: "candidate b"}], "B")

    Reference.absorb(ref, [%{text: "cites b once", citations: [b.id]}], "C")
    Reference.absorb(ref, [%{text: "cites b twice", citations: [b.id]}], "D")
    Reference.absorb(ref, [%{text: "cites a once", citations: [a.id]}], "E")

    assert Reference.most_cited(ref).id == b.id

    [quarantined] = Reference.quarantine(ref, [b.id])
    assert quarantined.status == :superseded
    assert Reference.get(ref, b.id).status == :superseded
    assert Reference.most_cited(ref).id == a.id
  end

  test "persistent store round-trips entries, statuses, closure, and id continuation" do
    path = tmp_store_path()

    {:ok, ref} = Reference.start_link(persist_path: path)
    [root] = Reference.absorb(ref, [%{text: "root", meta: %{source: "seed"}}], "A")
    [middle] = Reference.absorb(ref, [%{text: "depends on root", citations: [root.id]}], "B")
    [leaf] = Reference.absorb(ref, [%{text: "depends on middle", citations: [middle.id]}], "C")
    [_other] = Reference.absorb(ref, [%{text: "independent"}], "D")

    Reference.retract(ref, root.id)
    Reference.quarantine(ref, [leaf.id])

    expected_entries = Reference.all(ref)
    expected_closure = Reference.closure(expected_entries, root.id)
    GenServer.stop(ref)

    {:ok, restored} = Reference.start_link(persist_path: path)

    assert Reference.all(restored) == expected_entries
    assert Reference.closure(Reference.all(restored), root.id) == expected_closure
    assert Reference.stats(restored) == %{entries: 4, restored: 4, skipped_lines: 0}

    [next] = Reference.absorb(restored, [%{text: "new after restore"}], "E")
    assert next.id == "e5"
  end

  test "persistent store skips a truncated jsonl line during replay" do
    path = tmp_store_path()

    {:ok, ref} = Reference.start_link(persist_path: path)
    [entry] = Reference.absorb(ref, [%{text: "valid line"}], "A")
    GenServer.stop(ref)

    File.write!(path, ~s({"op":"absorb"), [:append])

    {:ok, restored} = Reference.start_link(persist_path: path)

    assert Reference.all(restored) |> Enum.map(& &1.id) == [entry.id]
    assert Reference.stats(restored) == %{entries: 1, restored: 1, skipped_lines: 1}
  end

  test "persistent store is created with 0600 mode" do
    path = tmp_store_path()

    {:ok, ref} = Reference.start_link(persist_path: path)
    Reference.absorb(ref, [%{text: "secret local store"}], "SEC")

    assert Integer.mod(File.stat!(path).mode, 0o1000) == 0o600
  end

  test "absorb_idempotent reuses restored seeds regardless of status" do
    path = tmp_store_path()
    seed = %{type: :chunk, author: "DOCS", text: "same seed"}

    {:ok, ref} = Reference.start_link(persist_path: path)
    [first] = Reference.absorb_idempotent(ref, [seed], "DOCS")
    Reference.retract(ref, first.id)
    GenServer.stop(ref)

    {:ok, restored} = Reference.start_link(persist_path: path)
    [again] = Reference.absorb_idempotent(restored, [seed], "DOCS")

    assert again.id == first.id
    assert again.status == :retracted
    assert length(Reference.all(restored)) == 1

    [_new] = Reference.absorb_idempotent(restored, [%{seed | text: "different seed"}], "DOCS")
    assert length(Reference.all(restored)) == 2
  end

  test "export/import creates idempotent copies with provenance and reused embeddings" do
    {:ok, source} = Reference.start_link()
    {:ok, target} = Reference.start_link()

    [entry] =
      Reference.absorb(
        source,
        [%{type: :observation, text: "measured energy savings", meta: %{domain: "energy"}}],
        "ENG"
      )

    exported = Reference.export(source, [entry.id, "missing"])
    assert length(exported) == 1
    assert hd(exported).id == entry.id
    assert hd(exported).type == "observation"

    [copy] = Reference.import(target, exported, "A")

    assert copy.author == "A/ENG"
    assert copy.status == entry.status
    assert copy.embedding == entry.embedding
    assert copy.meta.domain == "energy"
    assert copy.meta.source_cluster == "A"
    assert copy.meta.source_id == entry.id

    [again] = Reference.import(target, exported, "A")

    assert again.id == copy.id
    assert Reference.all(target) == [copy]
  end

  test "import remaps batch citations and records out-of-batch citations as unresolved" do
    {:ok, source} = Reference.start_link()
    {:ok, target} = Reference.start_link()

    [_seed] = Reference.absorb(target, [%{text: "local seed"}], "LOCAL")
    [root] = Reference.absorb(source, [%{text: "source root"}], "A")

    [child] =
      Reference.absorb(
        source,
        [%{text: "source child", citations: [root.id, "e999"]}],
        "B"
      )

    [root_copy, child_copy] =
      Reference.import(target, Reference.export(source, [root.id, child.id]), "SRC")

    assert root_copy.id != root.id
    assert child_copy.id != child.id
    assert child_copy.citations == [root_copy.id]
    assert child_copy.meta.unresolved_citations == ["e999"]
  end

  test "propagate_retractions retracts imported copy and quarantines local closure" do
    {:ok, source} = Reference.start_link()
    {:ok, target} = Reference.start_link()

    [a1] = Reference.absorb(source, [%{text: "field measurement supports loan"}], "ENERGY")
    [copy] = Reference.import(target, Reference.export(source, [a1.id]), "A")

    [b1] =
      Reference.absorb(
        target,
        [%{type: :decision, text: "design loan", citations: [copy.id]}],
        "FIN"
      )

    Reference.retract(source, a1.id)
    [result] = Reference.propagate_retractions(target, "A", Reference.export(source, [a1.id]))

    assert result.source_id == a1.id
    assert result.copy.id == copy.id
    assert result.copy.status == :retracted
    assert Enum.map(result.closure, & &1.id) == [b1.id]
    assert Reference.get(target, copy.id).status == :retracted
    assert Reference.get(target, b1.id).status == :superseded
  end

  test "persistent imported copies and propagated statuses round-trip" do
    source_path = tmp_store_path()
    target_path = tmp_store_path()

    {:ok, source} = Reference.start_link(persist_path: source_path)
    {:ok, target} = Reference.start_link(persist_path: target_path)

    [a1] = Reference.absorb(source, [%{text: "correctable measurement"}], "ENERGY")
    [copy] = Reference.import(target, Reference.export(source, [a1.id]), "A")

    [b1] =
      Reference.absorb(
        target,
        [%{text: "depends on imported measurement", citations: [copy.id]}],
        "FIN"
      )

    GenServer.stop(target)

    Reference.retract(source, a1.id)
    {:ok, restored_target} = Reference.start_link(persist_path: target_path)

    assert Reference.get(restored_target, copy.id).meta.source_cluster == "A"

    [result] =
      Reference.propagate_retractions(restored_target, "A", Reference.export(source, [a1.id]))

    assert result.copy.id == copy.id
    assert Reference.get(restored_target, copy.id).status == :retracted
    assert Reference.get(restored_target, b1.id).status == :superseded
    GenServer.stop(restored_target)

    {:ok, restored_again} = Reference.start_link(persist_path: target_path)

    assert Reference.get(restored_again, copy.id).status == :retracted
    assert Reference.get(restored_again, b1.id).status == :superseded
  end

  defp tmp_store_path do
    path =
      Path.join(
        System.tmp_dir!(),
        "tracefield-reference-#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)
    path
  end
end
