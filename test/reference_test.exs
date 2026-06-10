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
end
