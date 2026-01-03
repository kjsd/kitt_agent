defmodule KittAgentWeb.ActivityLive.Index do
  use KittAgentWeb, :live_view

  alias KittAgent.Events
  alias KittAgent.Kitts
  alias KittAgent.Talks
  alias KittAgent.SystemActions

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    kitts = Kitts.all_kitts()

    {:ok,
     socket
     |> assign(kitts: kitts)
     |> assign(page_title: "Activities")
     |> assign(selected_code: nil)
     |> assign(talks_queue_length: 0)
     |> assign(actions_queue_length: 0)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    kitt_id = params["kitt_id"]
    kitt = if kitt_id, do: Kitts.get_kitt(kitt_id), else: nil

    status = params["status"]
    page = String.to_integer(params["page"] || "1")

    filter = %{role: "assistant"}
    filter = if kitt, do: Map.put(filter, :kitt_id, kitt_id), else: filter
    filter = if status && status != "", do: Map.put(filter, :status, status), else: filter

    offset = (page - 1) * @per_page
    range = offset..(offset + @per_page - 1)

    {contents, {_off, total}} =
      Events.list_contents(range, filter, order_by: [desc: :inserted_at])
      |> Events.with_timestamp(kitt)

    pl = ceil(total / @per_page)
    pl = if pl == 0, do: 1, else: pl
    pa = (ceil(page / 5) - 1) * 5 + 1
    pz = if(pa + 4 > pl, do: pl, else: pa + 4)

    socket =
      socket
      |> assign(:contents, contents)
      |> assign(:filter_kitt_id, kitt_id)
      |> assign(:filter_status, status)
      |> assign(:page, page)
      |> assign(:pa, pa)
      |> assign(:pz, pz)
      |> assign(:pl, pl)
      |> update_queue_lengths()

    {:noreply, socket}
  end

  defp update_queue_lengths(socket) do
    kitt_id = socket.assigns.filter_kitt_id

    {talks_len, actions_len} =
      if kitt_id && kitt_id != "" do
        {Talks.queue_length(kitt_id), SystemActions.queue_length(kitt_id)}
      else
        {Talks.total_queue_length(), SystemActions.total_queue_length()}
      end

    socket
    |> assign(:talks_queue_length, talks_len)
    |> assign(:actions_queue_length, actions_len)
  end

  @impl true
  def handle_event("filter_change", %{"kitt_id" => kitt_id, "status" => status}, socket) do
    params = %{kitt_id: kitt_id, status: status, page: 1}
    params = Enum.reject(params, fn {_, v} -> v == "" or v == nil end)
    {:noreply, push_patch(socket, to: ~p"/kitt-web/activities?#{params}")}
  end

  def handle_event("clear_talks", _params, socket) do
    case socket.assigns.filter_kitt_id do
      nil -> Talks.clear_all_queues()
      "" -> Talks.clear_all_queues()
      id -> Talks.clear_queue(id)
    end

    {:noreply, socket |> put_flash(:info, "Talk queue cleared") |> update_queue_lengths()}
  end

  def handle_event("clear_actions", _params, socket) do
    case socket.assigns.filter_kitt_id do
      nil -> SystemActions.clear_all_queues()
      "" -> SystemActions.clear_all_queues()
      id -> SystemActions.clear_queue(id)
    end

    {:noreply, socket |> put_flash(:info, "System Action queue cleared") |> update_queue_lengths()}
  end

  def handle_event("change_status", %{"id" => id, "status" => new_status}, socket) do
    content = Events.get_content!(id)
    {:ok, _} = Events.update_content(content, %{status: new_status})

    params = %{
      kitt_id: socket.assigns.filter_kitt_id,
      status: socket.assigns.filter_status,
      page: socket.assigns.page
    }

    params = Enum.reject(params, fn {_, v} -> v == "" or v == nil end)
    {:noreply, push_patch(socket, to: ~p"/kitt-web/activities?#{params}")}
  end

    def handle_event("page", %{"i" => page}, socket) do

      params = %{

        kitt_id: socket.assigns.filter_kitt_id,

        status: socket.assigns.filter_status,

        page: page

      }

  

      params = Enum.reject(params, fn {_, v} -> v == "" or v == nil end)

      {:noreply, push_patch(socket, to: ~p"/kitt-web/activities?#{params}")}

    end

  

    def handle_event("show_code", %{"id" => id}, socket) do

      code =

        socket.assigns.contents

        |> Enum.find(&(&1.id == String.to_integer(id)))

                |> case do

                  nil -> nil

                  c -> c.parameter || "No code available"

                end

  

      {:noreply, assign(socket, selected_code: code)}

    end

  

    def handle_event("close_code", _, socket) do

      {:noreply, assign(socket, selected_code: nil)}

    end

  

    defp status_color("pending"), do: "btn-warning"
  defp status_color("processing"), do: "btn-info"
  defp status_color("completed"), do: "btn-success"
  defp status_color("failed"), do: "btn-error"
  defp status_color(_), do: "btn-ghost"
end
