defmodule KittAgentWeb.HomeLive do
  use KittAgentWeb, :live_view

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts
  alias KittAgent.Events

  require Logger

  @events_unit 5

  defp events_page(%Kitt{} = kitt, i) do
    b = (i - 1) * @events_unit
    e = b + @events_unit - 1

    {events, {_, len}} =
      Events.list_events(b..e, %{kitt: kitt}, %{order_by: [desc: :inserted_at, desc: :id]})
      |> Events.with_timestamp(kitt)

    if len > 0 do
      pl = ceil(len / @events_unit)
      pa = (ceil(i / 5) - 1) * 5 + 1
      pz = if(pa + 4 > pl, do: pl, else: pa + 4)

      {events, pa, pz, pl}
    else
      {events, 1, 1, 1}
    end
  end

  defp events_page(_, _), do: {[], 1, 1, 1}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe()
    [kitt | _] = kitts = Kitts.all_kitts()
    {events, pa, pz, pl} = events_page(kitt, 1)

    socket
    |> assign(page_title: "Dashboard")
    |> assign(kitts: kitts)
    |> assign(kitt: kitt)
    |> assign(events: events)
    |> assign(p: 1)
    |> assign(pa: pa)
    |> assign(pz: pz)
    |> assign(pl: pl)
    |> assign(selected_code: nil)
    |> then(&{:ok, &1})
  end

  def handle_info({[:event, :created], _}, socket) do
    # Refresh the current page
    handle_event("page", %{"i" => socket.assigns.p}, socket)
  end

  def handle_event("show_code", %{"id" => id}, socket) do
    id_int = String.to_integer(id)
    Logger.info("Show code for event #{id_int}")

    code =
      socket.assigns.events
      |> Enum.find(&(&1.id == id_int))
      |> case do
        nil ->
          Logger.warning("Event #{id_int} not found in assigns")
          nil

        event ->
          Logger.info("Event found: #{inspect(event.content)}")
          event.content.parameter || "No code available"
      end
    
    Logger.info("Code to display: #{inspect(code)}")
    {:noreply, assign(socket, selected_code: code)}
  end

  def handle_event("close_code", _, socket) do
    {:noreply, assign(socket, selected_code: nil)}
  end

  def handle_event("talk", %{"id" => id, "user_text" => text}, socket) do
    with %Kitt{} = kitt <- Kitts.get_kitt(id) do
      kitt |> KittAgent.talk(text)
    end

    {:noreply, socket}
  end

  def handle_event("kitt", %{"id" => id}, socket) do
    socket
    |> assign(kitt: Kitts.get_kitt(id))
    |> then(&handle_event("page", %{"i" => 1}, &1))
  end

  def handle_event("page", %{"i" => i}, socket) when is_binary(i) do
    handle_event("page", %{"i" => String.to_integer(i)}, socket)
  end

  def handle_event("page", %{"i" => i}, socket) do
    kitt = socket.assigns.kitt
    {events, pa, pz, pl} = events_page(kitt, i)

    socket
    |> assign(events: events)
    |> assign(p: i)
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
