defmodule KittAgent.Events do
  import Ecto.Query, warn: false
  import BasicContexts.Query

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Datasets.Event
  alias KittAgent.Datasets.Content

  require Content
  
  use BasicContexts,
    repo: Repo,
    funcs: [:get, :create],
    attrs: [singular: :event, plural: :events, schema: Event, preload: :content]

  use BasicContexts,
    repo: Repo,
    funcs: [:get, :update],
    attrs: [singular: :content, plural: :contents, schema: Content,
            preload: :system_actions]

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
      |> preload([:kitt, content: :system_actions])
    end

  use BasicContexts.PartialList,
    repo: Repo,
    plural: :contents,
    schema: Content,
    where_fn: fn query, attrs ->
      query
      |> join(:inner, [c], e in assoc(c, :event))
      |> add_if(attrs[:kitt_id], &where(&2, [c, e], e.kitt_id == ^&1))
      |> add_if(attrs[:role], &where(&2, [c, e], e.role == ^&1))
      |> add_if(attrs[:status], &where(&2, [c], c.status == ^&1))
    end,
    last_fn: fn query, args ->
      query
      |> add_if(args[:order_by], &(&2 |> order_by(^&1)))
      |> preload([:system_actions, event: :kitt])
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
    update_fn = fn
      %Content{system_actions: [_|_]} = c ->
        c
        |> Map.from_struct()
        |> Map.put("status", Content.status_pending)
        |> Map.reject(fn {_, v} -> match?(%Ecto.Association.NotLoaded{}, v) end)

      %Content{} = c ->
        c
        |> Map.from_struct()
        |> Map.reject(fn {_, v} -> match?(%Ecto.Association.NotLoaded{}, v) end)

      %{"system_actions" => [_|_]} = c ->
        c |> Map.put("status", Content.status_pending)

      x ->
        x
    end

    kitt
    |> Ecto.build_assoc(:events, ev)
    |> Map.from_struct()
    |> Map.reject(fn {_, v} -> match?(%Ecto.Association.NotLoaded{}, v) end)
    |> Map.update(:content, nil, update_fn)
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

  def with_timestamp(x) when is_list(x), do: x |> Enum.map(&with_timestamp/1)
  def with_timestamp(%Content{inserted_at: ts} = content),
    do: with_timestamp(content, ts)
  def with_timestamp(%Event{inserted_at: ts} = event),
    do: with_timestamp(event, ts)

  def with_timestamp({list, opt}, %Kitt{} = kitt) when is_list(list) do
    list
    |> with_timestamp(kitt)
    |> then(&{&1, opt})
  end
  def with_timestamp({list, opt}, _) when is_list(list) do
    list
    |> with_timestamp()
    |> then(&{&1, opt})
  end
  def with_timestamp(x, %Kitt{} = kitt) when is_list(x),
    do: x |> Enum.map(&with_timestamp(&1, kitt))
  def with_timestamp(%Content{inserted_at: ts} = content, %Kitt{timezone: tz}) do
    ts
    |> to_datetime(tz)
    |> then(&Map.put(content, :timestamp, &1))
  end
  def with_timestamp(%Event{inserted_at: ts} = event, %Kitt{timezone: tz}) do
    ts
    |> to_datetime(tz)
    |> then(&Map.put(event, :timestamp, &1))
  end
  def with_timestamp(x, %NaiveDateTime{} = ts) do
    ts
    |> DateTime.from_naive!("Etc/UTC")
    |> then(&Map.put(x, :timestamp, &1))
  end
  def with_timestamp(x, %DateTime{} = ts), do: Map.put(x, :timestamp, ts)

  def content_with_actions(%Event{content: %Content{system_actions: [_|_]} = x}), do: x
  def content_with_actions(_), do: nil
 
  def content_pending(%Content{} = c),
    do: update_content(c, %{status: Content.status_pending})
  def content_processing(%Content{} = c),
    do: update_content(c, %{status: Content.status_processing})
  def content_completed(%Content{} = c),
    do: update_content(c, %{status: Content.status_completed})
  def content_failed(%Content{} = c),
    do: update_content(c, %{status: Content.status_failed})

  defp to_datetime(%NaiveDateTime{} = ts, tz) do
    ts
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(tz)
  end
  defp to_datetime(_, tz), do: DateTime.now(tz) 
  
end
