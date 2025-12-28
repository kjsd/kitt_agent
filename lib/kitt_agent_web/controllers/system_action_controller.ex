defmodule KittAgentWeb.SystemActionController do
  use KittAgentWeb, :controller

  alias KittAgent.SystemActions.Queue
  alias KittAgent.Datasets.Content
  alias KittAgent.Events

  require Logger
  
  action_fallback KittAgentWeb.FallbackController

  def pending(conn, %{"id" => kitt_id}) do
    with %Content{} = c <- Queue.dequeue(kitt_id) do
      Events.update_content_status(c, "processing")

      conn
      |> json(c)
    end
  end

  def complete(conn, %{"id" => _kitt_id, "content_id" => content_id}) do
    with %Content{} = c <- Events.get_content(content_id),
         {:ok, _} <- Events.update_content_status(c, "completed") do

      conn
      |> json(%{status: "OK"})
    end
  end

end
