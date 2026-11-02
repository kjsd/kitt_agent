defmodule KittAgent.Talks do
  use Supervisor

  alias KittAgent.Datasets.Content

  def start_link(_), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    children = [
      {DynamicSupervisor, name: KittAgent.Talks.Supervisor, strategy: :one_for_one},
      {Registry, keys: :unique, name: KittAgent.Talks.Registry},
      {Registry, keys: :duplicate, name: KittAgent.Talks.WSRegistry}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Registers the calling WebSocket process to receive real-time talk/audio events for `kitt_id`.
  """
  def register_ws(kitt_id) when is_binary(kitt_id) do
    Registry.register(KittAgent.Talks.WSRegistry, kitt_id, :ok)
  end

  @doc """
  Returns true if at least one WebSocket client (`kitt_talker`) is currently connected for `kitt_id`.
  """
  def ws_connected?(kitt_id) when is_binary(kitt_id) do
    case Process.whereis(KittAgent.Talks.WSRegistry) do
      nil -> false
      _pid -> Registry.lookup(KittAgent.Talks.WSRegistry, kitt_id) != []
    end
  end

  def ws_connected?(_), do: false

  @doc """
  Broadcasts a map payload as JSON to all connected WebSocket clients for `kitt_id`.
  Returns `true` if delivered to at least one connected socket, `false` otherwise.
  """
  def broadcast_ws(kitt_id, payload) when is_binary(kitt_id) and is_map(payload) do
    case Process.whereis(KittAgent.Talks.WSRegistry) do
      nil ->
        false

      _pid ->
        entries = Registry.lookup(KittAgent.Talks.WSRegistry, kitt_id)

        if entries == [] do
          false
        else
          json = Jason.encode!(payload)
          Enum.each(entries, fn {pid, _} -> send(pid, {:ws_push, json}) end)
          true
        end
    end
  end

  def broadcast_ws(_, _), do: false

  @doc """
  Pushes `content` immediately over WebSocket if a `kitt_talker` client is connected;
  otherwise enqueues it in `KittAgent.Talks.Queue` for HTTP polling fallback.
  """
  def enqueue_or_push(kitt_id, %Content{} = content) when is_binary(kitt_id) do
    payload = %{
      type: "talk",
      id: content.id,
      action: content.action,
      message: content.message,
      mood: content.mood,
      audio_path: content.audio_path,
      is_last: true
    }

    if broadcast_ws(kitt_id, payload) do
      :ok
    else
      KittAgent.Talks.Queue.enqueue(kitt_id, content)
    end
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
