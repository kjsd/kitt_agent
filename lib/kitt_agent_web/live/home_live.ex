defmodule KittAgentWeb.HomeLive do
  use KittAgentWeb, :live_view

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts
  alias KittAgent.Events

  @events_unit 5

  defp events_page(i) do
    b = (i - 1) * @events_unit
    e = b + @events_unit - 1

    {events, {_, len}} =
      Events.list_events(b..e, nil, %{order_by: [desc: :inserted_at, desc: :id]})

    if len > 0 do
      pl = ceil(len / @events_unit)
      pa = (ceil(i / 5) - 1) * 5 + 1
      pz = if(pa + 4 > pl, do: pl, else: pa + 4)

      {events, pa, pz, pl}
    else
      {events, 1, 1, 1}
    end
  end

  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe()
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

  def handle_info({[:event, :created], _}, socket) do
    # Refresh the current page
    page = socket.assigns.p
    {events, pa, pz, pl} = events_page(page)

    socket
    |> assign(events: events)
    |> assign(pa: pa)
    |> assign(pz: pz)
    |> assign(pl: pl)
    |> then(&{:noreply, &1})
  end

  def handle_event("talk", %{"id" => id, "user_text" => text}, socket) do
    with %Kitt{} = kitt <- Kitts.get_kitt(id) do
      kitt |> KittAgent.talk(text)
    end

    {:noreply, socket}
  end

  def handle_event("page", %{"i" => i}, socket) do
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

  def handle_event("delete_events", %{"ids" => ids} = arg, socket) do
    Events.delete_events(ids)

    handle_event("page", arg, socket)
  end

  def handle_event("delete_events", arg, socket) do
    handle_event("page", arg, socket)
  end
end
