defmodule KittAgentWeb.SystemActionController do
  use KittAgentWeb, :controller

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.Datasets.Kitt
  alias KittAgent.{Kitts, Events, StageLogger}
  alias KittAgent.SystemActions.Queue

  require Content

  action_fallback KittAgentWeb.FallbackController

  def pending(conn, %{"id" => kitt_id}) do
    case dequeue_pending(kitt_id) do
      %Content{} = c ->
        if not virtual_led_action?(c) do
          Events.content_processing(c)
          StageLogger.mbot_action_started(c)
        end

        conn
        |> json(c)

      nil ->
        if KittAgent.SystemActions.thinking?(kitt_id) do
          conn
          |> json(KittAgent.SystemActions.thinking_action())
        else
          nil
        end
    end
  end

  def complete(conn, %{"id" => _kitt_id, "content_id" => content_id})
      when content_id in ["thinking", "talk_led"] do
    conn
    |> json(%{status: "OK"})
  end

  def complete(conn, %{"id" => kitt_id, "content_id" => content_id}) do
    with %Kitt{} = _ <- Kitts.get_kitt(kitt_id),
         %Content{} = c <- Events.get_content(content_id) do
      Events.content_completed(c)
      StageLogger.mbot_action_completed(c)

      conn
      |> json(%{status: "OK"})
    end
  end

  def fail(conn, %{"id" => _kitt_id, "content_id" => content_id})
      when content_id in ["thinking", "talk_led"] do
    conn
    |> json(%{status: "OK"})
  end

  def fail(conn, %{"id" => kitt_id, "content_id" => content_id}) do
    with %Kitt{} = _ <- Kitts.get_kitt(kitt_id),
         %Content{} = c <- Events.get_content(content_id) do
      Events.content_failed(c)
      StageLogger.mbot_action_failed(c)

      conn
      |> json(%{status: "OK"})
    end
  end

  defp virtual_led_action?(%Content{id: id}) when id in ["thinking", "talk_led"], do: true

  defp virtual_led_action?(%Content{parameter: param}) when is_binary(param) do
    String.starts_with?(param, "talk_led(") or String.starts_with?(param, "think_led(")
  end

  defp virtual_led_action?(_), do: false

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
