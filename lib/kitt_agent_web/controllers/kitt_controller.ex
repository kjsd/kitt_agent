defmodule KittAgentWeb.KittController do
  use KittAgentWeb, :controller
  action_fallback KittAgentWeb.FallbackController

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.Kitts
  alias KittAgent.Talks.Queue
  alias KittAgent.Voice.WhisperClient

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

  def talk_audio(conn, %{"id" => id} = params) do
    case Kitts.get_kitt(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Kitt not found"})

      %Kitt{} = kitt ->
        audio_source =
          case params do
            %{"audio" => %Plug.Upload{} = upload} ->
              upload

            %{"audio_base64" => b64} when is_binary(b64) and b64 != "" ->
              case Base.decode64(b64) do
                {:ok, binary} -> binary
                :error -> nil
              end

            _ ->
              nil
          end

        if is_nil(audio_source) do
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Missing or invalid audio parameter (expected 'audio' file upload or 'audio_base64')"})
        else
          case WhisperClient.transcribe(audio_source) do
            {:ok, ""} ->
              Logger.debug("talk_audio: No speech detected in audio")
              conn
              |> json(%{status: "ignored", text: "", message: "No speech detected"})

            {:ok, user_text} ->
              Logger.debug("talk_audio: Transcribed \"#{user_text}\", triggering talk...")
              case KittAgent.talk(kitt, user_text) do
                {:ok, %Content{} = content} ->
                  conn
                  |> json(%{
                    status: "ok",
                    text: user_text,
                    reply: content.message,
                    mood: content.mood,
                    action: content.action,
                    parameter: content.parameter,
                    audio_path: content.audio_path
                  })

                {:error, reason} ->
                  Logger.error("talk_audio: Talk error: #{inspect(reason)}")
                  conn
                  |> put_status(:internal_server_error)
                  |> json(%{status: "error", error: inspect(reason), text: user_text})
              end

            {:error, reason} ->
              Logger.error("talk_audio: STT error: #{inspect(reason)}")
              conn
              |> put_status(:bad_gateway)
              |> json(%{status: "error", error: "STT error: #{inspect(reason)}"})
          end
        end
    end
  end

  def dequeue_talk(conn, %{"id" => id}) do
    with %Kitt{} = _ <- Kitts.get_kitt(id),
        %Content{audio_path: x} = c when is_binary(x) <- Queue.dequeue(id) do
      conn
      |> json(c)
    else
      %Content{} = x ->
        Logger.debug(fn -> "dequeue_talk without audio_path: #{inspect(x)}" end)
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
