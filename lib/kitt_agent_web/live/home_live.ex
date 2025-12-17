defmodule KittAgentWeb.HomeLive do
  use KittAgentWeb, :live_view

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts
  alias KittAgent.Events

  @events_unit 5

  defp events_page(i) do
    b = (i - 1) * @events_unit
    e = b + @events_unit-1
    {events, {_, len}} = Events.list_events(b..e)
    pl = ceil(len / @events_unit)
    pa = (ceil(i/5) - 1) * 5 + 1
    pz = if(pa + 4 > pl, do: pl, else: pa + 4)

     {i, pa, pz, pl} |> IO.inspect
    {events, pa, pz, pl}
  end

  def mount(_params, _session, socket) do
    kitts = Kitts.all_kitts()
    {events, pa, pz, pl} = events_page(1)

    socket
    |> assign(page_title: "Dashboard")
    |> assign(kitts: kitts)
    |> assign(events: events)
    |> assign(p: 1)
    |> assign(pa: pa)
    |> assign(pz: pz)
    |> assign(pl: pl)
    |> then(&{:ok, &1})
  end

  def handle_event("talk",  %{"id" => id, "user_text" => text}, socket) do
    with %Kitt{} = kitt <- Kitts.get_kitt(id),
         {:ok, res} <- kitt |> KittAgent.talk(text) do

      {events, pa, pz, pl} = events_page(1)

      socket
      |> assign(events: events)
      |> assign(p: 1)
      |> assign(pa: pa)
      |> assign(pz: pz)
      |> assign(pl: pl)
      |> then(&{:noreply, &1})
    else
      _ ->
        socket
    end
  end

  def handle_event("page",  %{"i" => i}, socket) do
    idx = String.to_integer(i)
    {events, pa, pz, pl} = events_page(idx)
    
    socket
    |> assign(events: events)
    |> assign(p: idx)
    |> assign(pa: pa)
    |> assign(pz: pz)
    |> assign(pl: pl)
    |> then(&{:noreply, &1})
  end
  
end
