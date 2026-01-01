defmodule KittAgent.FakeOpenRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  post "/api/chat" do
    # OpenRouterのレスポンス形式を模倣
    fake_ai_response = %{
      "message" => "Hello, I am a test Kitt.",
      "mood" => "happy",
      "action" => "Talk",
      "listener" => "user"
    }

    response_body = %{
      "choices" => [
        %{
          "message" => %{
            "content" => Jason.encode!(fake_ai_response)
          }
        }
      ]
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response_body))
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
