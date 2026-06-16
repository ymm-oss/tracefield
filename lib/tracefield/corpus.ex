defmodule Tracefield.Corpus do
  @moduledoc """
  Ingest a directory of files into `:corpus_chunk` reference entries for
  corpus-backed consult sources.
  """

  @default_chunk_size 1400
  @default_per_file 4

  @doc """
  Split `text` into newline-aware windows of at most `size` characters.
  """
  def windows(text, size \\ @default_chunk_size) do
    text
    |> String.split("\n")
    |> Enum.reduce([""], fn line, [cur | rest] ->
      if String.length(cur) + String.length(line) + 1 > size and cur != "",
        do: [line, cur | rest],
        else: [cur <> "\n" <> line | rest]
    end)
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Expand `globs` under `root`, chunk each regular file, and return entry maps
  suitable for `Reference.absorb/3` with `type: :corpus_chunk` and
  `author` set to `source_id`.
  """
  def ingest_entries(root, corpus_spec, source_id) when is_map(corpus_spec) do
    root = Path.expand(root)
    globs = Map.get(corpus_spec, "globs", Map.get(corpus_spec, :globs, []))
    per_file = corpus_int(corpus_spec, "per_file", @default_per_file)
    chunk_size = corpus_int(corpus_spec, "chunk_size", @default_chunk_size)

    globs
    |> Enum.flat_map(&expand_glob(root, &1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(&file_chunks(&1, root, per_file, chunk_size, source_id))
  end

  @doc false
  def private_doc_note(source_id) do
    """
    あなた (#{source_id}) はコーパス資料ソースです。各ターンで serve により取得した
    自リポジトリの corpus_chunk が唯一の根拠資料です。静的 private doc はありません。
    """
    |> String.trim()
  end

  defp corpus_int(spec, key, default) do
    spec
    |> Map.get(key, Map.get(spec, String.to_atom(key), default))
    |> case do
      n when is_integer(n) -> n
      n when is_binary(n) -> String.to_integer(n)
      _ -> default
    end
  end

  defp expand_glob(root, glob) do
    root
    |> Path.join(glob)
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
  end

  defp file_chunks(path, root, per_file, chunk_size, source_id) do
    rel = Path.relative_to(path, root)

    path
    |> File.read!()
    |> windows(chunk_size)
    |> Enum.take(per_file)
    |> Enum.with_index(1)
    |> Enum.map(fn {text, part} ->
      %{
        type: :corpus_chunk,
        author: source_id,
        text: text,
        meta: %{file: rel, part: part}
      }
    end)
  end
end
