defmodule KittAgent.Events do
  import Ecto.Query, warn: false
  import BasicContexts.Query

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Datasets.Event

  use BasicContexts,
    repo: Repo,
    funcs: [:get, :create],
    attrs: [singular: :event, plural: :events, schema: Event, preload: :content]

  use BasicContexts.PartialList,
    repo: Repo,
    plural: :events,
    schema: Event,
    where_fn: fn query, attrs ->
      query
      |> add_if(attrs[:kitt], &(&2 |> where([t], t.kitt_id == ^&1.id)))
      |> add_if(attrs[:newer], &(&2 |> where([t], t.inserted_at > ^&1)))
    end,
    last_fn: fn query, args ->
      query
      |> add_if(args[:order_by], &(&2 |> order_by(^&1)))
      |> preload([:kitt, :content])
    end

  @recent 100

  def make_user_talk_event(text) do
    %Event{
      role: "user",
      content: %{
        action: "Talk",
        message: text
      }
    }
  end

  def make_kitt_event(attr) do
    %Event{
      role: "assistant",
      content: attr
    }
  end
  
  def create_kitt_event(%Event{} = ev, %Kitt{} = kitt) do
    kitt
    |> Ecto.build_assoc(:events, ev)
    |> Map.from_struct()
    |> create_event()
    |> broadcast_change([:event, :created])
  end

  @topic "events"

  def subscribe do
    Phoenix.PubSub.subscribe(KittAgent.PubSub, @topic)
  end

  defp broadcast_change({:ok, %Event{} = result}, event) do
    Phoenix.PubSub.broadcast(KittAgent.PubSub, @topic, {event, result})
    {:ok, result}
  end
  defp broadcast_change(result, _), do: result

  def delete_events([_ | _] = ids) do
    Event
    |> where([t], t.id in ^ids)
    |> Repo.delete_all()
  end

  def delete_events(_), do: {0, nil}

  def recents(%Kitt{} = kitt) do
    list_events(0..@recent, %{kitt: kitt}, desc: :inserted_at, desc: :id)
    |> elem(0)
    |> Enum.reverse()
  end

  def list_since(%Kitt{} = kitt, %NaiveDateTime{} = timestamp) do
    list_events(nil, %{kitt: kitt, newer: timestamp}, asc: :inserted_at)
    |> elem(0)
  end

  def list_since(%Kitt{} = kitt, _) do
    list_events(nil, %{kitt: kitt}, asc: :inserted_at)
    |> elem(0)
  end

  def with_timestamp({list, opt}, %Kitt{} = kitt) do
    list
    |> Enum.map(&with_timestamp(&1, kitt))
    |> then(&{&1, opt})
  end
  def with_timestamp(%Event{inserted_at: ts} = event, %Kitt{timezone: tz}) do
    with {:ok, utc} <- ts |> DateTime.from_naive("Etc/UTC"),
         {:ok, x} <- utc |> DateTime.shift_zone(tz) do
      event |> Map.put(:timestamp, x)
    else
      _ -> event |> Map.put(:timestamp, ts)
    end
  end
  
end
