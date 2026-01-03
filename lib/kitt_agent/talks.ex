defmodule KittAgent.Talks do
  use Supervisor

  def start_link(_), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    children = [
      {DynamicSupervisor, name: KittAgent.Talks.Supervisor, strategy: :one_for_one},
      {Registry, keys: :unique, name: KittAgent.Talks.Registry}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  def clear_queue(kitt_id) do
    KittAgent.Talks.Queue.clear(kitt_id)
  end

  def clear_all_queues do
    KittAgent.Kitts.all_kitts()
    |> Enum.each(fn kitt -> clear_queue(kitt.id) end)
  end

  def queue_length(kitt_id) do
    KittAgent.Talks.Queue.queue(kitt_id) |> length()
  end

  def total_queue_length do
    KittAgent.Kitts.all_kitts()
    |> Enum.map(&queue_length(&1.id))
    |> Enum.sum()
  end
end
