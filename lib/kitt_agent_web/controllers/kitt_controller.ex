defmodule KittAgentWeb.KittController do
  use KittAgentWeb, :controller
  action_fallback KittAgentWeb.FallbackController

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.Kitts
  alias KittAgent.Talks.Queue

  require Logger

  @compile_env_uploads_dir Application.compile_env(:kitt_agent, :uploads_dir)

  def index(conn, _params) do
    kitts = Kitts.all_kitts()
    json(conn, kitts)
  end

  def show(conn, %{"id" => id}) do
    kitt = Kitts.get_kitt!(id)
    json(conn, kitt)
  end

  def talk(conn, %{"id" => id, "text" => user_text}) do
    with %Kitt{} = kitt <- Kitts.get_kitt(id),
         {:ok, res} <- kitt |> KittAgent.talk(user_text) do
      conn
      |> json(res)
    end
  end

  def dequeue_talk(conn, %{"id" => id}) do
    with %Kitt{} = _ <- Kitts.get_kitt(id),
        %Content{audio_path: x} = c when is_binary(x) <- Queue.dequeue(id) do
      conn
      |> json(c)
    else
      %Content{} = x ->
        x |> inspect |> Logger.info()
        nil

      e -> e
    end
  end

  def debug_uploads(conn, _params) do
    uploads_dir = Application.get_env(:kitt_agent, :uploads_dir)
    files = case File.ls(uploads_dir) do
      {:ok, list} -> list
      {:error, reason} -> "Error: #{inspect(reason)}"
    end

    conn
    |> json(%{
      env: to_string(Application.get_env(:kitt_agent, :env, :dev)),
      config_uploads_dir: uploads_dir,
      compile_env_uploads_dir: @compile_env_uploads_dir,
      files_in_dir: files
    })
  end

end
