defmodule Tracefield.Coverage do
  @moduledoc """
  Advisory coverage: detect reference chunks distant from all llm/cli actors.
  """

  alias Tracefield.Embed

  # 0.2 flags chunks with no meaningful actor overlap while tolerating paraphrase.
  @default_threshold 0.2

  @type chunk :: %{
          required(:id) => String.t(),
          required(:file) => String.t(),
          required(:text) => String.t()
        }
  @type actor :: %{
          required(:id) => String.t(),
          required(:domain) => String.t(),
          required(:desc) => String.t(),
          required(:kind) => atom(),
          required(:private_doc) => String.t()
        }
  @type uncovered_chunk :: %{
          id: String.t(),
          file: String.t(),
          nearest_actor: String.t(),
          sim: float()
        }

  @spec uncovered([chunk()], [actor()], keyword()) :: [uncovered_chunk()]
  def uncovered(chunks, actors, opts) do
    embed_adapter = Keyword.fetch!(opts, :embed_adapter)
    threshold = Keyword.get(opts, :threshold, @default_threshold)

    measurable_actors =
      actors
      |> Enum.filter(&(&1.kind in [:llm, :cli]))
      |> Enum.map(fn actor -> {actor.id, actor_profile(actor)} end)

    cond do
      measurable_actors == [] -> []
      chunks == [] -> []
      true -> uncovered_chunks(chunks, measurable_actors, embed_adapter, threshold)
    end
  end

  defp uncovered_chunks(chunks, measurable_actors, embed_adapter, threshold) do
    actor_profiles = Enum.map(measurable_actors, fn {_id, profile} -> profile end)
    chunk_texts = Enum.map(chunks, & &1.text)

    {:ok, embeddings} =
      Embed.embed(chunk_texts ++ actor_profiles,
        adapter: embed_adapter,
        model: "nomic-embed-text"
      )

    {chunk_embeddings, actor_embeddings} = Enum.split(embeddings, length(chunks))
    actor_ids = Enum.map(measurable_actors, fn {id, _profile} -> id end)

    chunks
    |> Enum.zip(chunk_embeddings)
    |> Enum.reduce([], fn {chunk, chunk_embedding}, acc ->
      {nearest_actor, max_sim} =
        actor_ids
        |> Enum.zip(actor_embeddings)
        |> Enum.map(fn {actor_id, actor_embedding} ->
          {actor_id, Embed.cosine(chunk_embedding, actor_embedding)}
        end)
        |> Enum.max_by(fn {_actor_id, sim} -> sim end, fn -> {"", 0.0} end)

      if max_sim < threshold do
        [%{id: chunk.id, file: chunk.file, nearest_actor: nearest_actor, sim: max_sim} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp actor_profile(%{domain: domain, desc: desc, private_doc: private_doc}) do
    [domain, desc, private_doc]
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> String.trim()
  end
end
