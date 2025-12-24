defmodule KittAgentWeb.Router do
  use KittAgentWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KittAgentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/kitt-web", KittAgentWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/kitts", KittLive.Index, :index
    live "/kitts/new", KittLive.Index, :new
    live "/kitts/:id/edit", KittLive.Index, :edit
  end

  scope "/kitt/:id", KittAgentWeb do
    pipe_through :api

    post "/talk/", KittController, :talk
    post "/tts", KittController, :tts
  end
end
