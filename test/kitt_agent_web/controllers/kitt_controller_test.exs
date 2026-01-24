defmodule KittAgentWeb.KittControllerTest do
  use KittAgentWeb.ConnCase, async: false

  alias KittAgent.Kitts
  alias KittAgent.Repo
  alias KittAgent.Datasets.Content

  setup do
    # FakeOpenRouterサーバーをポート4100で起動
    # すでに起動している場合のエラーハンドリングが必要だが、start_supervised!は自動で管理してくれる
    start_supervised!({Bandit, plug: KittAgent.FakeOpenRouter, scheme: :http, port: 4100})

    # API URLの設定を上書き
    original_config = Application.get_env(:kitt_agent, :api_urls)
    Application.put_env(:kitt_agent, :api_urls, openrouter: "http://localhost:4100/api/chat")

    on_exit(fn ->
      if original_config do
        Application.put_env(:kitt_agent, :api_urls, original_config)
      else
        Application.delete_env(:kitt_agent, :api_urls)
      end
    end)

    # テスト用Kitt作成
    {:ok, kitt} =
      Kitts.create_kitt(%{
        name: "Test Kitt",
        lang: "Japanese",
        timezone: "Asia/Tokyo",
        biography: %{
          model: "test-model",
          vendor: "test-vendor",
          birthday: ~D[2024-01-01],
          hometown: "Test City",
          personality: "A friendly test assistant named %%NAME%%."
        }
      })

    %{kitt: kitt}
  end

  describe "index/2" do
    test "lists all kitts", %{conn: conn, kitt: kitt} do
      conn = get(conn, ~p"/kitts")
      data = json_response(conn, 200)
      assert is_list(data)
      assert Enum.any?(data, fn k -> k["id"] == kitt.id && k["name"] == "Test Kitt" end)
    end
  end

  describe "show/2" do
    test "returns a specific kitt", %{conn: conn, kitt: kitt} do
      conn = get(conn, ~p"/kitts/#{kitt.id}")
      assert %{"id" => id, "name" => "Test Kitt"} = json_response(conn, 200)
      assert id == kitt.id
    end
  end

  describe "talk/2" do
    test "returns AI response successfully", %{conn: conn, kitt: kitt} do
      params = %{"id" => kitt.id, "text" => "Hello"}

      conn = post(conn, ~p"/kitts/#{kitt.id}/talk", params)

      assert %{"message" => "Hello, I am a test Kitt."} = json_response(conn, 200)

      # DBに会話ログ(Content)が保存されていることを確認
      # ユーザーの発言とAIの発言で少なくとも2つはあるはず
      contents = Repo.all(Content)
      assert length(contents) >= 2
    end

    test "returns 404 for non-existent kitt", %{conn: conn} do
      fake_id = "00000000-0000-0000-0000-000000000000"
      params = %{"id" => fake_id, "text" => "Hello"}

      # FallbackControllerが適切に処理するか確認
      # もしコントローラーがnilを返してクラッシュする場合は修正が必要
      conn = post(conn, ~p"/kitts/#{fake_id}/talk", params)

      assert response(conn, 404)
    end
  end
end
