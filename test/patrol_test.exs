defmodule Tracefield.PatrolTest do
  use ExUnit.Case, async: true

  alias Tracefield.Patrol

  test "split_sections splits markdown headings deterministically" do
    doc = """
    ## Alpha
    alpha body line

    ## Beta
    beta body line

    ## Gamma
    gamma body line
    """

    assert [
             %{title: "Alpha", body: "alpha body line"},
             %{title: "Beta", body: "beta body line"},
             %{title: "Gamma", body: "gamma body line"}
           ] = Patrol.split_sections(doc)
  end

  test "split_sections falls back to paragraph boundaries without headings" do
    doc = """
    First paragraph alpha body

    Second paragraph beta body
    """

    assert [
             %{title: "First paragraph alpha body", body: "First paragraph alpha body"},
             %{title: "Second paragraph beta body", body: "Second paragraph beta body"}
           ] = Patrol.split_sections(doc)
  end

  test "select_slice rotates deterministically with round index" do
    sections = [
      %{title: "Alpha", body: "alpha"},
      %{title: "Beta", body: "beta"},
      %{title: "Gamma", body: "gamma"}
    ]

    assert %{toc: ["Alpha", "Beta", "Gamma"], body: "Alpha\nalpha"} =
             Patrol.select_slice(sections, 1)

    assert %{toc: ["Alpha", "Beta", "Gamma"], body: "Beta\nbeta"} =
             Patrol.select_slice(sections, 2)

    assert %{toc: ["Alpha", "Beta", "Gamma"], body: "Gamma\ngamma"} =
             Patrol.select_slice(sections, 3)

    assert %{toc: ["Alpha", "Beta", "Gamma"], body: "Alpha\nalpha"} =
             Patrol.select_slice(sections, 4)
  end

  test "format_patrol_body always includes section index and selected slice" do
    slice = %{toc: ["Alpha", "Beta"], body: "Beta\nbeta body"}

    body = Patrol.format_patrol_body(slice, 2)

    assert body =~ "SECTION INDEX (full territory map):"
    assert body =~ "- Alpha"
    assert body =~ "- Beta"
    assert body =~ "SECTION CONTENT (patrol slice for round 2):"
    assert body =~ "Beta\nbeta body"
  end
end
