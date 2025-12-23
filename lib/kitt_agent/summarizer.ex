defmodule KittAgent.Summarizer do
  use GenServer

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts
  alias KittAgent.Events
  alias KittAgent.Memories
  alias KittAgent.Requests

  # Threshold for new events to trigger a summary
  @threshold 20

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def exec(id), do: GenServer.cast(__MODULE__, {:exec, id})

  @impl GenServer
  def init(:ok), do: {:ok, :ok}

  @impl GenServer
  def handle_cast({:exec, id}, state) do
    with %Kitt{} = kitt <- Kitts.get_kitt(id),
         last_memory <- Memories.last_memory(kitt),
         last_ts <- if(last_memory, do: last_memory.inserted_at, else: nil),
         new_events <- Events.list_since(kitt, last_ts),
         true <- length(new_events) >= @threshold,
         {:ok, res} <- Requests.summary(kitt, new_events),
         {:ok, _} <- Memories.create_memory(kitt, res) do
      :ok
    else
      _ -> :ok
    end

    {:noreply, state}
  end
end
