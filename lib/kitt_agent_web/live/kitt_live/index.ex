defmodule KittAgentWeb.KittLive.Index do
  use KittAgentWeb, :live_view

  alias KittAgent.Kitts
  alias KittAgent.Datasets.Kitt

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :kitts, Kitts.all_kitts())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Kitt")
    |> assign(:kitt, Kitts.get_kitt!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Kitt")
    |> assign(:kitt, %Kitt{biography: %KittAgent.Datasets.Biography{}})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Kitts")
    |> assign(:kitt, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    kitt = Kitts.get_kitt!(id)
    {:ok, _} = Kitts.delete_kitt(kitt)

    {:noreply, stream_delete(socket, :kitts, kitt)}
  end

  @impl true
  def handle_info({KittAgentWeb.KittLive.FormComponent, {:saved, kitt}}, socket) do
    {:noreply, stream_insert(socket, :kitts, kitt)}
  end
end
