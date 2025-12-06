defmodule Summarizer do
  use GenServer

  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def exec(), do: GenServer.cast(__MODULE__, :exec)

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_cast(:exec, state) do

    
    {:noreply, state}
  end
end
