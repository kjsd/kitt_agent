defmodule KittAgentWeb.KittController do
  use KittAgentWeb, :controller
  action_fallback KittAgentWeb.FallbackController

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.Kitts
  alias KittAgent.Talks.Queue

  require Logger

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

end
