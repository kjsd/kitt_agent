defmodule KittAgentWeb.SystemActionController do
  use KittAgentWeb, :controller

  alias KittAgent.SystemActions.Queue
  alias KittAgent.Datasets.Content
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts
  alias KittAgent.Events

  require Content

  action_fallback KittAgentWeb.FallbackController

  def pending(conn, %{"id" => kitt_id}) do
    with %Content{} = c <- dequeue_pending(kitt_id) do
      Events.content_processing(c)

      conn
      |> json(c)
    end
  end

  def complete(conn, %{"id" => kitt_id, "content_id" => content_id}) do
    with %Kitt{} = _ <- Kitts.get_kitt(kitt_id),
         %Content{} = c <- Events.get_content(content_id) do
      Events.content_completed(c)

      conn
      |> json(%{status: "OK"})
    end
  end

  defp dequeue_pending(id) do
    with %Content{status: Content.status_pending()} = c <- Queue.dequeue(id) do
      c
    else
      %Content{} ->
        dequeue_pending(id)

      x ->
        x
    end
  end
end
