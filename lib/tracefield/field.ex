defmodule Tracefield.Field do
  @moduledoc """
  Supervisor for live Tracefield clusters, the META store, and bridge links.
  """

  use Supervisor

  alias Tracefield.Bridge.Link
  alias Tracefield.Reference

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def refs(field) do
    field
    |> Supervisor.which_children()
    |> Enum.flat_map(fn
      {{:tracefield_ref, name}, pid, _type, _modules} when is_pid(pid) -> [{name, pid}]
      _other -> []
    end)
    |> Map.new()
  end

  def links(field) do
    field
    |> Supervisor.which_children()
    |> Enum.flat_map(fn
      {{:tracefield_link, from, to}, pid, _type, _modules} when is_pid(pid) -> [{{from, to}, pid}]
      _other -> []
    end)
    |> Map.new()
  end

  @impl true
  def init(opts) do
    field_id = Keyword.get(opts, :id, System.unique_integer([:positive]))
    cluster_specs = Keyword.get(opts, :clusters, [])
    meta_path = Keyword.get(opts, :meta)

    refs =
      cluster_specs
      |> Enum.map(&cluster_ref_spec(&1, field_id))
      |> Kernel.++([meta_ref_spec(meta_path, field_id)])

    links = link_specs(Keyword.get(opts, :links, :auto), cluster_specs, field_id)

    Supervisor.init(refs ++ links, strategy: :one_for_one)
  end

  defp cluster_ref_spec(cluster, field_id) do
    name = cluster |> Map.fetch!(:name) |> to_string()
    persist_path = Map.get(cluster, :persist_path)
    ref_name = ref_name(field_id, name)

    %{
      id: {:tracefield_ref, name},
      start: {Reference, :start_link, [[persist_path: persist_path, name: ref_name]]}
    }
  end

  defp meta_ref_spec(meta_path, field_id) do
    %{
      id: {:tracefield_ref, "META"},
      start: {Reference, :start_link, [[persist_path: meta_path, name: ref_name(field_id, "META")]]}
    }
  end

  defp link_specs(:auto, cluster_specs, field_id) do
    Enum.flat_map(cluster_specs, fn cluster ->
      name = cluster |> Map.fetch!(:name) |> to_string()

      [
        link_spec(name, "META", ref_name(field_id, name), ref_name(field_id, "META"), name),
        link_spec("META", name, ref_name(field_id, "META"), ref_name(field_id, name), "META")
      ]
    end)
  end

  defp link_specs(link_specs, _cluster_specs, field_id) when is_list(link_specs) do
    Enum.map(link_specs, fn spec ->
      from = spec |> Map.fetch!(:from) |> to_string()
      to = spec |> Map.fetch!(:to) |> to_string()
      source_name = spec |> Map.get(:source_name, from) |> to_string()

      link_spec(from, to, ref_name(field_id, from), ref_name(field_id, to), source_name)
    end)
  end

  defp link_specs(_links, _cluster_specs, _field_id), do: []

  defp link_spec(from, to, source, target, source_name) do
    %{
      id: {:tracefield_link, from, to},
      start: {Link, :start_link, [[source: source, target: target, source_name: source_name]]}
    }
  end

  defp ref_name(field_id, name), do: {:global, {__MODULE__, field_id, name}}
end
