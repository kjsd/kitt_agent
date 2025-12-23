defmodule KittAgent.Summarizer do
  use GenServer

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts
  alias KittAgent.Events
  alias KittAgent.Memories
  alias KittAgent.Requests

  @unit 100
  
  def start_link(state \\ 0) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def exec(id), do: GenServer.cast(__MODULE__, {:exec, id})

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_cast({:exec, id}, state) do
    idx_b = state
    idx_e =  state + @unit - 1

    with %Kitt{} = kitt <- Kitts.get_kitt(id),
         {events, {_, len}} when len > @unit <- Events.list_events(kitt, idx_b..idx_e),
         {:ok, res} <- Requests.summary(kitt, events),
         {:ok, _} <- Memories.create_memory(kitt, res) do
      {:noreply, idx_e}
    else
      _ ->
        {:noreply, state}
    end
  end

end
