defmodule KittAgentWeb.SystemActionController do
  use KittAgentWeb, :controller

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.Datasets.Kitt
  alias KittAgent.{Kitts, Events}
  alias KittAgent.SystemActions.Queue

  require Content

  action_fallback KittAgentWeb.FallbackController

  def pending(conn, %{"id" => kitt_id}) do
    with %Content{} = c <- dequeue_pending(kitt_id) do
      if not String.starts_with?(c.parameter || "", "talk_led(") do
        Events.content_processing(c)
      end

      conn
      |> json(c)
    end
  end

  def complete(conn, %{"id" => kitt_id, "content_id" => content_id}) do
    with %Kitt{} = _ <- Kitts.get_kitt(kitt_id),
         %Content{} = c <- Events.get_content(content_id) do
      Events.content_completed(c)

      conn
      |> json(%{status: "OK"})
    end
  end

  def fail(conn, %{"id" => kitt_id, "content_id" => content_id}) do
    with %Kitt{} = _ <- Kitts.get_kitt(kitt_id),
         %Content{} = c <- Events.get_content(content_id) do
      Events.content_failed(c)

      conn
      |> json(%{status: "OK"})
    end
  end

  defp dequeue_pending(id) do
    with %Content{status: Content.status_pending()} = c <- Queue.dequeue(id) do
      if stale_talk_led?(c) do
        dequeue_pending(id)
      else
        c
      end
    else
      %Content{} ->
        dequeue_pending(id)

      x ->
        x
    end
  end

  defp stale_talk_led?(%Content{parameter: param, updated_at: %NaiveDateTime{} = ts})
       when is_binary(param) do
    String.starts_with?(param, "talk_led(") and
      NaiveDateTime.diff(NaiveDateTime.utc_now(), ts, :second) > 20
  end

  defp stale_talk_led?(_), do: false
end
