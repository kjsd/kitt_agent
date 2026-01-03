defmodule KittAgentWeb.SystemActionControllerTest do
  use KittAgentWeb.ConnCase

  alias KittAgent.Kitts
  alias KittAgent.Events
  alias KittAgent.Repo
  alias KittAgent.Datasets.Content
  alias KittAgent.SystemActions.Queue

  require Content

  setup %{conn: conn} do
    {:ok, kitt} =
      Kitts.create_kitt(%{name: "Test Kitt", lang: "Japanese", timezone: "Asia/Tokyo"})

    # テスト用のアクションを作成
    actions_content = %{
      "action" => "SystemAction",
      "message" => "Test",
      "parameter" => "mbot2.forward(100, 1)",
      "status" => Content.status_pending()
    }

    {:ok, event} = Events.make_kitt_event(actions_content) |> Events.create_kitt_event(kitt)

    # Queueに入れる
    Queue.enqueue(kitt.id, event.content)

    %{conn: conn, kitt: kitt, content: event.content}
  end

  describe "pending actions" do
    test "GET /kitt/:id/actions/pending retrieves pending actions", %{
      conn: conn,
      kitt: kitt,
      content: content
    } do
      conn = get(conn, ~p"/kitt/#{kitt.id}/actions/pending")

      assert %{"parameter" => "mbot2.forward(100, 1)"} = json_response(conn, 200)

      # ステータスが processing になっていることを確認
      updated_content = Repo.get(Content, content.id)
      assert updated_content.status == "processing"
      Queue.clear(kitt.id)
    end

    test "GET /kitt/:id/actions/pending returns empty if queue is empty", %{
      conn: conn,
      kitt: kitt
    } do
      # 最初のGETでQueueは空になるはず
      get(conn, ~p"/kitt/#{kitt.id}/actions/pending")

      # 2回目のGET
      conn = get(conn, ~p"/kitt/#{kitt.id}/actions/pending")
      assert response(conn, 404)
      Queue.clear(kitt.id)
    end
  end

  describe "complete action" do
    test "POST /kitt/:id/actions/:content_id/complete updates status", %{
      conn: conn,
      kitt: kitt,
      content: content
    } do
      # まずは processing にしておく
      get(conn, ~p"/kitt/#{kitt.id}/actions/pending")
      assert Repo.get(Content, content.id).status == "processing"

      # complete をPOST
      conn = post(conn, ~p"/kitt/#{kitt.id}/actions/#{content.id}/complete")
      assert response(conn, 200)

      # ステータスが completed になっていることを確認
      updated_content = Repo.get(Content, content.id)
      assert updated_content.status == "completed"
      Queue.clear(kitt.id)
    end
  end
end
