defmodule Tracefield.Bridge.Link do
  @moduledoc """
  Live retraction propagation link between two Reference stores.
  """

  use GenServer

  alias Tracefield.Reference

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def history(link) do
    GenServer.call(link, :history)
  end

  @impl true
  def init(opts) do
    source = Keyword.fetch!(opts, :source)
    target = Keyword.fetch!(opts, :target)
    source_name = opts |> Keyword.fetch!(:source_name) |> to_string()

    :ok = Reference.subscribe(source, self())

    {:ok, %{source: source, target: target, source_name: source_name, history: []}}
  end

  @impl true
  def handle_call(:history, _from, state) do
    {:reply, state.history, state}
  end

  @impl true
  def handle_info({:tracefield_status, %{status: status, entry: entry}}, state)
      when status in [:retracted, :superseded] do
    additions =
      state.target
      |> Reference.propagate_retractions(state.source_name, [entry])
      |> Enum.map(fn result ->
        %{
          source_id: result.source_id,
          copy_id: result.copy.id,
          quarantined: length(result.closure)
        }
      end)

    {:noreply, %{state | history: state.history ++ additions}}
  end

  def handle_info({:tracefield_status, _payload}, state), do: {:noreply, state}
end
