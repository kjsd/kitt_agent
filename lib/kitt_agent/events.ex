defmodule KittAgent.Events do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Datasets.Event

  use BasicContexts, repo: Repo, funcs: [:get, :create],
    attrs: [singular: :event, plural: :events, schema: Event]

  @recent 100
  
  def add_user_text(%Kitt{} = kitt, text) do
    o = %{role: "user", content: %{
             "action" => "Talk",
             "timestamp" => "#{BasicContexts.Utils.now_jpn}",
             "message" => text}}

    kitt
    |> Ecto.build_assoc(:events, o)
    |> Repo.insert
  end

  def add_kitt_event(%Kitt{} = kitt, ev) do
    v = ev |> Map.put("timestamp", "#{BasicContexts.Utils.now_jpn}")

    kitt
    |> Ecto.build_assoc(:events, %{role: "assistant", content: v})
    |> Repo.insert
  end

  def recents(%Kitt{} = kitt) do
    kitt
    |> Ecto.assoc(:events)
    |> order_by(desc: :inserted_at)
    |> limit(^@recent)
    |> Repo.all
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
