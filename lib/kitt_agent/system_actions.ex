defmodule KittAgent.SystemActions do
  use Supervisor

  alias KittAgent.Datasets.Content
  require Content

  @thinking_table :kitt_thinking_state
  @thinking_ttl_ms 18_000

  @thinking_parameter """
  if 'think_led' in globals():
      think_led(0.36)
  else:
      mbuild.ultrasonic2.set_bri(60, "all", 1)
      cyberpi.led.on(0, 180, 255)
      time.sleep(0.18)
      mbuild.ultrasonic2.set_bri(15, "all", 1)
      cyberpi.led.on(140, 0, 255)
      time.sleep(0.18)
      cyberpi.led.off('all')
  """

  def start_link(_), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    ensure_thinking_table()

    children = [
      {DynamicSupervisor, name: KittAgent.SystemActions.Supervisor, strategy: :one_for_one},
      {Registry, keys: :unique, name: KittAgent.SystemActions.Registry}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  def set_thinking(kitt_id, true) when is_binary(kitt_id) do
    table = ensure_thinking_table()
    :ets.insert(table, {kitt_id, System.monotonic_time(:millisecond)})
    :ok
  end

  def set_thinking(kitt_id, false) when is_binary(kitt_id) do
    table = ensure_thinking_table()
    :ets.delete(table, kitt_id)
    :ok
  end

  def set_thinking(_, _), do: :ok

  def thinking?(kitt_id) when is_binary(kitt_id) do
    table = ensure_thinking_table()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(table, kitt_id) do
      [{^kitt_id, ts}] when now - ts < @thinking_ttl_ms ->
        true

      [{^kitt_id, _expired_ts}] ->
        :ets.delete(table, kitt_id)
        false

      _ ->
        false
    end
  end

  def thinking?(_), do: false

  def thinking_action do
    %Content{
      id: "thinking",
      action: Content.action_system(),
      status: Content.status_pending(),
      parameter: @thinking_parameter,
      updated_at: NaiveDateTime.utc_now()
    }
  end

  def enqueue_talk_led(kitt_id, duration_sec)
      when is_binary(kitt_id) and is_number(duration_sec) and duration_sec > 0 do
    dur = Float.round(duration_sec * 1.0, 1)

    action = %Content{
      id: "talk_led",
      action: Content.action_system(),
      status: Content.status_pending(),
      parameter: "talk_led(#{dur})",
      updated_at: NaiveDateTime.utc_now()
    }

    KittAgent.SystemActions.Queue.enqueue(kitt_id, action)
  end

  def enqueue_talk_led(_, _), do: :ok

  def clear_queue(kitt_id) do
    set_thinking(kitt_id, false)
    KittAgent.SystemActions.Queue.clear(kitt_id)
  end

  def clear_all_queues do
    KittAgent.Kitts.all_kitts()
    |> Enum.each(fn kitt -> clear_queue(kitt.id) end)
  end

  def queue_length(kitt_id) do
    KittAgent.SystemActions.Queue.queue(kitt_id) |> length()
  end

  def total_queue_length do
    KittAgent.Kitts.all_kitts()
    |> Enum.map(&queue_length(&1.id))
    |> Enum.sum()
  end

  defp ensure_thinking_table do
    case :ets.whereis(@thinking_table) do
      :undefined ->
        try do
          ets_opts =
            case Process.whereis(KittAgent.Supervisor) do
              pid when is_pid(pid) -> [:named_table, :public, :set, {:heir, pid, nil}]
              _ -> [:named_table, :public, :set]
            end

          :ets.new(@thinking_table, ets_opts)
        rescue
          ArgumentError -> @thinking_table
        end

      _tid ->
        @thinking_table
    end
  end
end
