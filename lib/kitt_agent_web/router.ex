defmodule KittAgentWeb.Router do
  use KittAgentWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/kitt/:id", KittAgentWeb do
    pipe_through :api

    post "/talk/", MainController, :talk
    post "/tts", MainController, :tts
  end
end
