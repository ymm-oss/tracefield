defmodule Tracefield.ReferenceTest do
  use ExUnit.Case

  alias Tracefield.Bridge.Link
  alias Tracefield.Field
  alias Tracefield.Meta
  alias Tracefield.Reference

  defmodule QueryEmbedding do
    @behaviour Tracefield.Embed

    @impl true
    def embed(texts, _opts) when is_list(texts) do
      {:ok, Enum.map(texts, fn _text -> [1.0, 0.0] end)}
    end
  end

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

  test "serve policy contrastive ranks distinctive entries above consensus cluster" do
    {:ok, ref} = Reference.start_link(embed_adapter: QueryEmbedding)

    [distinctive, b1, b2, c1, c2] =
      import_with_embeddings(ref, [
        %{id: "d1", author: "D", text: "distinctive D", embedding: [0.90, -0.4358898944]},
        %{id: "b1", author: "B", text: "consensus B1", embedding: [0.95, 0.3122498999]},
        %{id: "b2", author: "B", text: "consensus B2", embedding: [0.95, 0.3122498999]},
        %{id: "c1", author: "C", text: "consensus C1", embedding: [0.95, 0.3122498999]},
        %{id: "c2", author: "C", text: "consensus C2", embedding: [0.95, 0.3122498999]}
      ])

    contrastive =
      Reference.serve(ref, "query",
        k: 1,
        policy: :contrastive
      )

    similar =
      Reference.serve(ref, "query",
        k: 1,
        policy: :similar
      )

    diverse =
      Reference.serve(ref, "query",
        k: 1,
        policy: :diverse
      )

    assert Enum.map(contrastive, & &1.id) == [distinctive.id]
    assert Enum.map(similar, & &1.id) == [b1.id]
    assert Enum.map(diverse, & &1.id) == [c2.id]

    assert MapSet.new(Enum.map([b1, b2, c1, c2], & &1.id))
           |> MapSet.member?(hd(similar).id)
  end

  test "serve policy contrastive returns empty for k zero and empty candidate pool" do
    {:ok, ref} = Reference.start_link(embed_adapter: QueryEmbedding)
    [_entry] = import_with_embeddings(ref, [%{id: "a1", author: "A", embedding: [1.0, 0.0]}])

    assert Reference.serve(ref, "query", k: 0, policy: :contrastive) == []

    {:ok, empty_ref} = Reference.start_link(embed_adapter: QueryEmbedding)
    assert Reference.serve(empty_ref, "query", k: 3, policy: :contrastive) == []
  end

  test "serve policy contrastive author balances by score before taking k" do
    {:ok, ref} = Reference.start_link(embed_adapter: QueryEmbedding)

    import_with_embeddings(ref, [
      %{id: "a1", author: "A", embedding: [1.0, 0.0]},
      %{id: "a2", author: "A", embedding: [0.99, 0.1410673598]},
      %{id: "a3", author: "A", embedding: [0.98, 0.1989974874]},
      %{id: "b1", author: "B", embedding: [0.85, -0.5267826876]},
      %{id: "c1", author: "C", embedding: [0.80, -0.60]}
    ])

    served = Reference.serve(ref, "query", k: 4, policy: :contrastive)

    assert served |> Enum.take(3) |> Enum.map(& &1.author) |> MapSet.new() |> MapSet.size() == 3
    assert Enum.map(served, & &1.author) != ["SRC/A", "SRC/A", "SRC/A", "SRC/B"]
  end

  test "serve policy contrastive is deterministic with entry number tie break" do
    {:ok, ref} = Reference.start_link(embed_adapter: QueryEmbedding)

    [first, second] =
      import_with_embeddings(ref, [
        %{id: "a1", author: "A", embedding: [0.8, 0.6]},
        %{id: "a2", author: "A", embedding: [0.8, 0.6]}
      ])

    first_run = Reference.serve(ref, "query", k: 2, policy: :contrastive)
    second_run = Reference.serve(ref, "query", k: 2, policy: :contrastive)

    assert Enum.map(first_run, & &1.id) == [first.id, second.id]
    assert Enum.map(second_run, & &1.id) == [first.id, second.id]
  end

  test "serve still raises for unknown policy" do
    {:ok, ref} = Reference.start_link()
    trap_exit = Process.flag(:trap_exit, true)

    try do
      assert {{%ArgumentError{message: "unknown serve policy :unknown"}, _stack}, _call} =
               catch_exit(Reference.serve(ref, "query", k: 1, policy: :unknown))

      assert_receive {:EXIT, ^ref, _reason}
    after
      Process.flag(:trap_exit, trap_exit)
    end
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

  defp import_with_embeddings(ref, entries) do
    exported =
      Enum.map(entries, fn entry ->
        %{
          id: Map.fetch!(entry, :id),
          type: Map.get(entry, :type, :belief),
          author: Map.fetch!(entry, :author),
          version: 1,
          status: Map.get(entry, :status, :active),
          text: Map.get(entry, :text, Map.fetch!(entry, :id)),
          citations: Map.get(entry, :citations, []),
          embedding: Map.fetch!(entry, :embedding),
          meta: %{}
        }
      end)

    Reference.import(ref, exported, "SRC")
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

  test "H4: citations store flat ids while non-default stances ride in meta and round-trip" do
    path = tmp_store_path()
    {:ok, ref} = Reference.start_link(persist_path: path)
    [a] = Reference.absorb(ref, [%{text: "source a"}], "A")
    [b] = Reference.absorb(ref, [%{text: "source b"}], "B")

    [claim] =
      Reference.absorb(
        ref,
        [
          %{
            text: "claim",
            citations: [%{id: a.id, stance: "relies_on"}, %{id: b.id, stance: "refutes"}]
          }
        ],
        "C"
      )

    # stored citations stay a flat id list (every existing consumer is unaffected)
    assert claim.citations == [a.id, b.id]
    # only the non-default stance is recorded; relies_on is the implicit default
    assert claim.meta[:citation_stances] == %{b.id => "refutes"}

    GenServer.stop(ref)
    {:ok, restored} = Reference.start_link(persist_path: path)
    reloaded = Enum.find(Reference.all(restored), &(&1.id == claim.id))
    assert reloaded.citations == [a.id, b.id]
    assert reloaded.meta[:citation_stances] == %{b.id => "refutes"}
  end

  test "H4: bare-string citations normalize to relies_on with no citation_stances meta" do
    {:ok, ref} = Reference.start_link()
    [a] = Reference.absorb(ref, [%{text: "source"}], "A")
    [claim] = Reference.absorb(ref, [%{text: "claim", citations: [a.id]}], "B")

    assert claim.citations == [a.id]
    refute Map.has_key?(claim.meta, :citation_stances)
  end

  test "H4: verify grounds stance-bearing citations by id (stance-independent)" do
    {:ok, ref} = Reference.start_link()
    [support] = Reference.absorb(ref, [%{text: "solar comfort finance support"}], "A")
    [unrelated] = Reference.absorb(ref, [%{text: "zzzz yyyy xxxx"}], "B")

    [claim] =
      Reference.absorb(
        ref,
        [
          %{
            text: "solar comfort plan reduces budget risk",
            citations: [
              %{id: support.id, stance: "relies_on"},
              %{id: unrelated.id, stance: "refutes"}
            ]
          }
        ],
        "C"
      )

    assert claim.citations == [support.id, unrelated.id]

    judgments = Reference.verify(ref, [claim], judge_adapter: Tracefield.LLM.Mock)
    assert judgments[{claim.id, support.id}]
    refute judgments[{claim.id, unrelated.id}]
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

  test "subscribe delivers retract and quarantine status events" do
    {:ok, ref} = Reference.start_link()
    :ok = Reference.subscribe(ref, self())

    [root] = Reference.absorb(ref, [%{text: "root"}], "A")
    [child] = Reference.absorb(ref, [%{text: "child", citations: [root.id]}], "B")

    Reference.retract(ref, root.id)

    assert_receive {:tracefield_status,
                    %{store: ^ref, id: root_id, status: :retracted, entry: %{status: "retracted"}}}

    assert root_id == root.id

    Reference.quarantine(ref, [child.id])

    assert_receive {:tracefield_status,
                    %{
                      store: ^ref,
                      id: child_id,
                      status: :superseded,
                      entry: %{status: "superseded"}
                    }}

    assert child_id == child.id
  end

  test "live link propagates source retraction and records history" do
    {:ok, source} = Reference.start_link()
    {:ok, target} = Reference.start_link()
    {:ok, link} = Link.start_link(source: source, target: target, source_name: "A")

    [a1] = Reference.absorb(source, [%{text: "shared assumption"}], "ENG")
    [copy] = Reference.import(target, Reference.export(source, [a1.id]), "A")
    [b1] = Reference.absorb(target, [%{text: "local decision", citations: [copy.id]}], "FIN")

    Reference.retract(source, a1.id)

    wait_until(fn ->
      Reference.get(target, copy.id).status == :retracted and
        Reference.get(target, b1.id).status == :superseded
    end)

    assert Link.history(link) == [%{source_id: a1.id, copy_id: copy.id, quarantined: 1}]
  end

  test "import keeps source chain across two hops and stays idempotent on final hop" do
    {:ok, a} = Reference.start_link()
    {:ok, meta} = Reference.start_link()
    {:ok, b} = Reference.start_link()

    [a1] = Reference.absorb(a, [%{text: "two hop evidence"}], "ENG")
    [meta_copy] = Reference.import(meta, Reference.export(a, [a1.id]), "A")
    [b_copy] = Reference.import(b, Reference.export(meta, [meta_copy.id]), "META")
    [again] = Reference.import(b, Reference.export(meta, [meta_copy.id]), "META")

    assert b_copy.meta.source_chain == [%{source_cluster: "A", source_id: a1.id}]
    assert b_copy.meta.source_cluster == "META"
    assert b_copy.meta.source_id == meta_copy.id
    assert again.id == b_copy.id
    assert Reference.all(b) == [b_copy]
  end

  test "meta publish selects defaults and explicit ids, discover filters clusters, and pull imports" do
    {:ok, a} = Reference.start_link()
    {:ok, b} = Reference.start_link()
    {:ok, meta} = Reference.start_link()

    [_chunk] = Reference.absorb(a, [%{type: :chunk, text: "chunk solar loan"}], "DOC")
    [low] = Reference.absorb(a, [%{text: "solar insulation low citation"}], "ENG")
    [high] = Reference.absorb(a, [%{text: "solar insulation rebate green loan"}], "ENG")
    [newer] = Reference.absorb(a, [%{text: "solar roof battery finance"}], "ENG")

    Reference.absorb(a, [%{text: "cites high once", citations: [high.id]}], "X")
    Reference.absorb(a, [%{text: "cites high twice", citations: [high.id]}], "Y")
    Reference.absorb(a, [%{text: "cites low once", citations: [low.id]}], "Z")

    default_copies = Meta.publish(meta, "A", a, limit: 2)
    assert Enum.map(default_copies, & &1.meta.source_id) == [high.id, low.id]

    [explicit_copy] = Meta.publish(meta, "A", a, ids: [newer.id])
    assert explicit_copy.meta.source_id == newer.id

    [found | _rest] = Meta.discover(meta, "rebate green loan insulation", k: 2)
    assert found.source_cluster == "A"
    assert found.source_id == high.id

    assert Meta.discover(meta, "rebate green loan insulation", exclude_cluster: "A") == []

    [pulled] = Meta.pull(b, meta, [found.entry.id])
    assert pulled.meta.source_cluster == "META"
    assert pulled.meta.source_id == found.entry.id
    assert pulled.meta.source_chain == [%{source_cluster: "A", source_id: high.id}]
  end

  test "field auto links propagate A retraction through META into B" do
    base = tmp_dir()

    {:ok, field} =
      Field.start_link(
        clusters: [
          %{name: "A", persist_path: Path.join(base, "A.jsonl")},
          %{name: "B", persist_path: Path.join(base, "B.jsonl")}
        ],
        meta: Path.join(base, "META.jsonl"),
        links: :auto
      )

    refs = Field.refs(field)
    links = Field.links(field)
    a = Map.fetch!(refs, "A")
    b = Map.fetch!(refs, "B")
    meta = Map.fetch!(refs, "META")

    [a1] = Reference.absorb(a, [%{text: "field shared evidence"}], "ENG")
    [meta_copy] = Meta.publish(meta, "A", a, ids: [a1.id])
    [b_copy] = Meta.pull(b, meta, [meta_copy.id])
    [b1] = Reference.absorb(b, [%{text: "uses imported evidence", citations: [b_copy.id]}], "FIN")

    Reference.retract(a, a1.id)

    wait_until(fn ->
      Reference.get(b, b_copy.id).status == :retracted and
        Reference.get(b, b1.id).status == :superseded
    end)

    assert Enum.any?(Link.history(Map.fetch!(links, {"A", "META"})), &(&1.source_id == a1.id))

    assert Enum.any?(
             Link.history(Map.fetch!(links, {"META", "B"})),
             &(&1.source_id == meta_copy.id and &1.copy_id == b_copy.id and &1.quarantined == 1)
           )
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

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "tracefield-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp wait_until(predicate, attempts \\ 50)

  defp wait_until(predicate, 0), do: flunk("condition did not become true: #{inspect(predicate)}")

  defp wait_until(predicate, attempts) do
    if predicate.() do
      :ok
    else
      Process.sleep(20)
      wait_until(predicate, attempts - 1)
    end
  end
end
