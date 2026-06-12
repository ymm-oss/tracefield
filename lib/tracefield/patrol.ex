defmodule Tracefield.Patrol do
  @moduledoc """
  Deterministic territory document patrol slicing for context injection.
  """

  @heading_pattern ~r/^(#+)\s+(.+)$/

  @spec split_sections(String.t()) :: [%{title: String.t(), body: String.t()}]
  def split_sections(doc) when is_binary(doc) do
    doc = String.trim(doc)

    cond do
      doc == "" ->
        []

      heading_sections?(doc) ->
        sections_from_headings(doc)

      true ->
        sections_from_paragraphs(doc)
    end
  end

  @spec select_slice([%{title: String.t(), body: String.t()}], pos_integer()) :: %{
          toc: [String.t()],
          body: String.t()
        }
  def select_slice(sections, round) when is_list(sections) and is_integer(round) and round >= 1 do
    case sections do
      [] ->
        %{toc: [], body: ""}

      _ ->
        index = rem(round - 1, length(sections))
        selected = Enum.at(sections, index)
        toc = Enum.map(sections, & &1.title)

        %{
          toc: toc,
          body: format_section(selected)
        }
    end
  end

  @doc false
  @spec format_patrol_body(%{toc: [String.t()], body: String.t()}, pos_integer()) :: String.t()
  def format_patrol_body(%{toc: toc, body: body}, round) do
    toc_text =
      toc
      |> Enum.map_join("\n", &"- #{&1}")
      |> case do
        "" -> "(none)"
        text -> text
      end

    """
    SECTION INDEX (full territory map):
    #{toc_text}

    SECTION CONTENT (patrol slice for round #{round}):
    #{body}
    """
    |> String.trim()
  end

  defp heading_sections?(doc) do
    doc
    |> String.split("\n")
    |> Enum.any?(fn line -> match?({:ok, _title}, heading_match(line)) end)
  end

  defp heading_match(line) do
    case Regex.run(@heading_pattern, line) do
      [_, hashes, title] when byte_size(hashes) in 1..6 ->
        {:ok, String.trim(title)}

      _ ->
        :error
    end
  end

  defp sections_from_headings(doc) do
    lines = String.split(doc, "\n", trim: false)

    {sections, preamble, current} =
      Enum.reduce(lines, {[], [], nil}, fn line, {sections, preamble, current} ->
        case heading_match(line) do
          {:ok, title} ->
            sections =
              sections
              |> maybe_prepend_preamble(preamble)
              |> finalize_current(current)

            {sections, [], %{title: title, body_lines: []}}

          :error ->
            if current do
              {sections, preamble, %{current | body_lines: current.body_lines ++ [line]}}
            else
              {sections, preamble ++ [line], nil}
            end
        end
      end)

    sections
    |> maybe_prepend_preamble(preamble)
    |> finalize_current(current)
    |> Enum.reverse()
  end

  defp maybe_prepend_preamble(sections, []), do: sections

  defp maybe_prepend_preamble(sections, preamble_lines) do
    body = preamble_lines |> Enum.join("\n") |> String.trim()

    if body == "" do
      sections
    else
      [%{title: preamble_title(body), body: body} | sections]
    end
  end

  defp finalize_current(sections, nil), do: sections

  defp finalize_current(sections, %{title: title, body_lines: body_lines}) do
    body = body_lines |> Enum.join("\n") |> String.trim()
    [%{title: title, body: body} | sections]
  end

  defp preamble_title(body) do
    body
    |> String.split("\n", parts: 2)
    |> List.first()
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "Preamble"
      line -> line
    end
  end

  defp sections_from_paragraphs(doc) do
    doc
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.with_index(1)
    |> Enum.map(fn {paragraph, index} ->
      title =
        paragraph
        |> String.split("\n", parts: 2)
        |> List.first()
        |> to_string()
        |> String.trim()
        |> case do
          "" -> "Section #{index}"
          line -> line
        end

      %{title: title, body: String.trim(paragraph)}
    end)
  end

  defp format_section(%{title: title, body: body}) do
    if body == "" do
      title
    else
      "#{title}\n#{body}"
    end
  end
end
