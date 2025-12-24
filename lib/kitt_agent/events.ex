defmodule KittAgent.Events do
  import Ecto.Query, warn: false
  import BasicContexts.Query

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Datasets.Event
  alias KittAgent.Datasets.Content

  use BasicContexts,
    repo: Repo,
    funcs: [:get],
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

  def make_talk_event(%Kitt{} = kitt, text) do
    %Event{
      role: "user",
      content: %Content{
        action: "Talk",
        parameters: "none",
        timestamp: BasicContexts.Utils.now_jpn(),
        target: "#{kitt.name}",
        message: text
      }
    }
  end

  @topic "events"

  def subscribe do
    Phoenix.PubSub.subscribe(KittAgent.PubSub, @topic)
  end

  def create_event(%Kitt{} = kitt, %Event{role: r, content: c}) do
    o = kitt
    |> Ecto.build_assoc(:events, %{role: r})
    |> Repo.insert!()

    o
    |> Ecto.build_assoc(:content, c)
    |> Repo.insert!()

    o |> Repo.preload(:content)
    |> broadcast_change([:event, :created])
  end

  def create_kitt_event(%Kitt{} = kitt, attr) do
    v = attr |> Map.put("timestamp", BasicContexts.Utils.now_jpn())

    o = kitt
    |> Ecto.build_assoc(:events, %{role: "assistant"})
    |> Repo.insert!()

    o
    |> Ecto.build_assoc(:content)
    |> Content.changeset(v)
    |> Repo.insert!()
    
    o |> Repo.preload(:content)
    |> broadcast_change([:event, :created])
  end

  defp broadcast_change(%Event{} = result, event) do
    Phoenix.PubSub.broadcast(KittAgent.PubSub, @topic, {event, result})
    {:ok, result}
  end

  def delete_events([_|_] = ids) do
    Event
    |> where([t], t.id in ^ids)
    |> Repo.delete_all()
  end
  def delete_events(_), do: {0, nil}
  
  def recents(%Kitt{} = kitt) do
    list_events(0..@recent, %{kitt: kitt}, [desc: :inserted_at, desc: :id])
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
end
