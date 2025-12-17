defmodule KittAgentWeb.HomeLive do
  use KittAgentWeb, :live_view

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts
  alias KittAgent.Events
  
  def mount(_params, _session, socket) do
    kitts = Kitts.all_kitts()
    {events, _} = Events.list_events(0..10)

    socket
    |> assign(kitts: kitts)
    |> assign(events: events)
    |> assign(response: "Response Area")
    |> then(&{:ok, &1})
  end

  def handle_event("talk",  %{"id" => id, "user_text" => text}, socket) do
    with %Kitt{} = kitt <- Kitts.get_kitt(id),
         {:ok, res} <- kitt |> KittAgent.talk(text) do
      {events, _} = Events.list_events(0..10)

      socket
      |> assign(events: events)
      |> assign(response: inspect(res))
      |> then(&{:noreply, &1})
    else
      _ ->
        socket
    end
  end

end
