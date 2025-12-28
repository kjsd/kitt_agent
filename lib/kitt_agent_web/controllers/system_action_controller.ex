defmodule KittAgentWeb.SystemActionController do
  use KittAgentWeb, :controller

  alias KittAgent.SystemActions.Queue
  alias KittAgent.Datasets.Content
  alias KittAgent.Repo

  action_fallback KittAgentWeb.FallbackController

  def index(conn, %{"id" => kitt_id}) do
    case Queue.dequeue(kitt_id) do
      [_|_] = actions ->
        # リストの先頭から content_id を取得（全部同じcontent_idのはず）
        content_id = List.first(actions).content_id

        # DBのstatusをprocessingに更新
        update_content_status(content_id, "processing")

        json(conn, %{data: actions})

      _ ->
        json(conn, %{data: []})
    end
  end

  def complete(conn, %{"id" => _kitt_id, "content_id" => content_id}) do
    case update_content_status(content_id, "completed") do
      {:ok, _content} ->
        send_resp(conn, :ok, "")
      
      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> put_view(json: KittAgentWeb.ErrorJSON)
        |> render(:"404")
    end
  end

  defp update_content_status(content_id, status) do
    case Repo.get(Content, content_id) do
      nil ->
        {:error, :not_found}
        
      content ->
        content
        |> Content.changeset(%{status: status})
        |> Repo.update()
    end
  end
end
