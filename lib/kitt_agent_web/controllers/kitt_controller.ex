defmodule KittAgentWeb.KittController do
  use KittAgentWeb, :controller
  action_fallback KittAgentWeb.FallbackController

  alias KittAgent.Kitts
  alias KittAgent.Datasets.Kitt

  require Logger
  
  # Cartesia (TTS用)
  @voice_id "39efcd60-14f4-4970-a02a-4e69b8b274a5" 
  
  def talk(conn, %{"id" => id, "text" => user_text}) do
    with %Kitt{} = kitt <- Kitts.get_kitt(id),
         {:ok, res} <- kitt |> KittAgent.talk(user_text) do

      conn
      |> json(res)
    end
  end

  def tts(conn, %{"id" => id, "text" => text}) do
    with %Kitt{} = _ <- Kitts.get_kitt(id) do
      # Cartesiaへのリクエストボディ
      cartesia_body = %{
        model_id: "sonic-multilingual", # 日本語対応モデル
        transcript: text,
        voice: %{
          mode: "id",
          id: @voice_id
        },
        output_format: %{
          container: "wav",       # WAVコンテナ
          encoding: "pcm_s16le",  # 16bit PCM
          sample_rate: 16000      # CyberPi用の16kHz
        }
      }

      api_key = Application.get_env(:kitt_agent, :keys)[:cartesia]

      # Cartesiaへリクエスト
      # 注意: Cartesiaはバイナリデータを返します
      case Req.post(Application.get_env(:kitt_agent, :api_urls)[:cartesia], 
            json: cartesia_body,
            headers: [
              {"X-API-Key", api_key},
              {"Cartesia-Version", "2024-06-10"},
              {"Content-Type", "application/json"}
            ]
          ) do
        {:ok, %{status: 200, body: audio_binary}} ->
          Logger.info("TTS Generated: #{byte_size(audio_binary)} bytes")
          
          # 音声データをそのままCyberPiへ返す
          conn
          |> put_resp_content_type("audio/wav")
          |> send_resp(200, audio_binary)

        {:ok, resp} ->
          Logger.error("Cartesia Error: #{inspect(resp.body)}")
          send_resp(conn, 500, "TTS Error")

        {:error, reason} ->
          Logger.error("Req Failed: #{inspect(reason)}")
          send_resp(conn, 500, "Network Error")
      end
    end
  end
  
end
