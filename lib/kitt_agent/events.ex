defmodule KittAgent.Events do
  import Ecto.Query, warn: false
  import BasicContexts.Query

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Datasets.Event
  alias KittAgent.Datasets.Content

  use BasicContexts, repo: Repo, funcs: [:get],
    attrs: [singular: :event, plural: :events, schema: Event, preload: :content]
  use BasicContexts.PartialList, repo: Repo, plural: :events, schema: Event,
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
    %Event{role: "user", content: %Content{
              action: "Talk",
              parameters: "none",
              timestamp: BasicContexts.Utils.now_jpn,
              target: "#{kitt.name}",
              message: text}}
  end

  def create_event!(%Kitt{} = kitt, %Event{role: r, content: c}) do
    kitt
    |> Ecto.build_assoc(:events, %{role: r})
    |> Repo.insert!
    |> Ecto.build_assoc(:content, c)
    |> Repo.insert!
  end

  def create_kitt_event!(%Kitt{} = kitt, attr) do
    v = attr |> Map.put("timestamp", BasicContexts.Utils.now_jpn)

    kitt
    |> Ecto.build_assoc(:events, %{role: "assistant"})
    |> Repo.insert!
    |> Ecto.build_assoc(:content)
    |> Content.changeset(v)
    |> Repo.insert!
  end

  def recents(%Kitt{} = kitt) do
    list_events(0..@recent, %{kitt: kitt})
    |> elem(0)
    |> Enum.reverse
  end

  def clear(%Kitt{} = kitt) do
    kitt
    |> Ecto.assoc(:events)
    |> order_by(asc: :inserted_at)
    |> limit(^@recent)
    |> Repo.delete_all
  end
  
end
