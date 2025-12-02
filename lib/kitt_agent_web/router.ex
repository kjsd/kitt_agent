defmodule KittAgentWeb.Router do
  use KittAgentWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/kitt", KittAgentWeb do
    pipe_through :api

    post "/chat", MainController, :chat
    post "/tts", MainController, :tts
  end
end
