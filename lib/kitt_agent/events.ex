defmodule KittAgent.Events do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Event

  use BasicContexts, repo: Repo, funcs: [:get, :create],
    attrs: [singular: :event, plural: :events, schema: Event]

  def add_user_text(text) do
    create_event(%{"role" => "user",
                   "content" => %{"action" => "Talk",
                                  "timestamp" => "#{BasicContexts.Utils.now_jpn}",
                                  "message" => text}})
  end

  def add_kitt_event(ev) do
    v = ev |> Map.put("timestamp", "#{BasicContexts.Utils.now_jpn}")
    create_event(%{"role" => "assistant", "content" => v})
  end

  def recents(n \\ 100) do
    Event
    |> order_by(desc: :inserted_at)
    |> limit(^n)
    |> Repo.all
    |> Enum.reverse
  end
    
end
