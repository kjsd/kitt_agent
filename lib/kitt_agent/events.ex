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
    order_by: [desc: :inserted_at, desc: :id],
    where_fn: fn query, attrs ->
      query
      |> add_if(attrs[:kitt], &(&2 |> where([t], t.kitt_id == ^&1.id)))
    end,
    last_fn: fn query, _ ->
      query
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

  def recents(%Kitt{} = kitt) do
    list_events(0..@recent, %{kitt: kitt})
    |> elem(0)
    |> Enum.reverse()
  end

  def clear(%Kitt{} = kitt) do
    kitt
    |> Ecto.assoc(:events)
    |> order_by(asc: :inserted_at)
    |> limit(^@recent)
    |> Repo.delete_all()
  end

  def list_since(%Kitt{} = kitt, timestamp) do
    Event
    |> where([e], e.kitt_id == ^kitt.id)
    |> then(fn q ->
      if timestamp do
        where(q, [e], e.inserted_at > ^timestamp)
      else
        q
      end
    end)
    |> order_by([e], asc: e.inserted_at)
    |> preload([:content])
    |> Repo.all()
  end
end
