defmodule KittAgentWeb.TalkerSocket do
  @moduledoc """
  WebSocket handler (`GET /kitts/:id/ws`) for `kitt_talker` clients.
  Pushes real-time STT recognition results, sentence-by-sentence TTS audio chunks,
  and completed Talk events with zero polling latency.
  """
  @behaviour WebSock

  alias KittAgent.Datasets.Content
  alias KittAgent.Talks
  alias KittAgent.Talks.Queue

  require Logger

  @impl true
  def init(%{kitt_id: kitt_id} = state) do
    {:ok, _} = Talks.register_ws(kitt_id)
    Logger.info("TalkerSocket: Client connected for Kitt #{kitt_id} (pid=#{inspect(self())})")

    # Drain any pending talks that were enqueued prior to WebSocket connection
    drain_pending_queue(kitt_id)

    welcome = Jason.encode!(%{type: "connected", kitt_id: kitt_id})
    {:push, {:text, welcome}, state}
  end

  @impl true
  def handle_in({"ping", _opts}, state) do
    {:push, {:text, ~s({"type":"pong"})}, state}
  end

  def handle_in({_text, _opts}, state) do
    {:ok, state}
  end

  @impl true
  def handle_info({:ws_push, json_text}, state) when is_binary(json_text) do
    {:push, {:text, json_text}, state}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl true
  def terminate(reason, %{kitt_id: kitt_id}) do
    Logger.info("TalkerSocket: Client disconnected for Kitt #{kitt_id} (reason=#{inspect(reason)})")
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp drain_pending_queue(kitt_id) do
    case Queue.dequeue(kitt_id) do
      %Content{audio_path: audio_path} = content when is_binary(audio_path) and audio_path != "" ->
        payload =
          Jason.encode!(%{
            type: "talk",
            id: content.id,
            action: content.action,
            message: content.message,
            mood: content.mood,
            audio_path: content.audio_path,
            is_last: true
          })

        send(self(), {:ws_push, payload})
        drain_pending_queue(kitt_id)

      _ ->
        :ok
    end
  end
end
