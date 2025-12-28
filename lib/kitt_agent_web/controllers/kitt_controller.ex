defmodule KittAgentWeb.KittController do
  use KittAgentWeb, :controller
  action_fallback KittAgentWeb.FallbackController

  alias KittAgent.Kitts
  alias KittAgent.Datasets.Kitt

  require Logger

  def talk(conn, %{"id" => id, "text" => user_text}) do
    with %Kitt{} = kitt <- Kitts.get_kitt(id),
         {:ok, res} <- kitt |> KittAgent.talk(user_text) do
      conn
      |> json(res)
    end
  end

end
