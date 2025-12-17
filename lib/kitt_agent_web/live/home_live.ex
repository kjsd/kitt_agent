defmodule KittAgentWeb.HomeLive do
  use KittAgentWeb, :live_view

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts
  alias KittAgent.Events

  @events_unit 5
  
  def mount(_params, _session, socket) do
    kitts = Kitts.all_kitts()
    {events, {_, len}} = Events.list_events(0..@events_unit-1)

    socket
    |> assign(page_title: "Dashboard")
    |> assign(kitts: kitts)
    |> assign(events: events)
    |> assign(p: 1)
    |> assign(l: ceil(len / @events_unit))
    |> assign(response: "Response Area")
    |> then(&{:ok, &1})
  end

  def handle_event("talk",  %{"id" => id, "user_text" => text}, socket) do
    with %Kitt{} = kitt <- Kitts.get_kitt(id),
         {:ok, res} <- kitt |> KittAgent.talk(text) do
      {events, _} = Events.list_events(0..@events_unit-1)

      socket
      |> assign(events: events)
      |> assign(response: inspect(res))
      |> then(&{:noreply, &1})
    else
      _ ->
        socket
    end
  end

  def handle_event("page",  %{"i" => i}, socket) do
    idx = String.to_integer(i)
    b = (idx - 1) * @events_unit
    e = b + @events_unit-1
    {events, {_, len}} = Events.list_events(b..e)
    
    socket
    |> assign(events: events)
    |> assign(p: idx)
    |> assign(l: ceil(len / @events_unit))
    |> then(&{:noreply, &1})
  end
  
end
