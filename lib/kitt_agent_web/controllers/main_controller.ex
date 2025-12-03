defmodule KittAgentWeb.MainController do
  use KittAgentWeb, :controller

  require Logger
  
  @llm_url "https://openrouter.ai/api/v1/chat/completions"
  @llm_model "google/gemini-2.5-flash-lite-preview-09-2025"

  # Cartesia (TTS用)
  @cartesia_url "https://api.cartesia.ai/tts/bytes"
  @voice_id "39efcd60-14f4-4970-a02a-4e69b8b274a5" 
  
  def chat(conn, %{"text" => user_text}) do
    messages = KittAgent.prompt(user_text)
    
    req_body = %{
      model: @llm_model,
      messages: messages
    }
    api_key = Application.get_env(:kitt_agent, :keys)[:openrouter]

    case Req.post(@llm_url, 
           json: req_body, 
           headers: [{"Authorization", "Bearer #{api_key}"},
                     {"HTTP-Referer", "https://www.kandj.org"}]
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        with [choice | _] <- resp_body["choices"],
             {:ok, res} <- Jason.decode(choice["message"]["content"]) do

          KittAgent.kitt_responce(res)
          
          res
          |> inspect
          |> Logger.info()
          
          conn
          |> json(res)
        else
          _ ->
            send_resp(conn, 500, Jason.encode!(%{error: "LLM Error"}))
        end

      {:ok, resp} ->
        Logger.error("LLM Error: #{inspect(resp.body)}")
        send_resp(conn, 500, Jason.encode!(%{error: "LLM Error"}))

      {:error, _} ->
        send_resp(conn, 500, "Net Error")
    end
  end

  def tts(conn, %{"text" => text}) do
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
    case Req.post(@cartesia_url, 
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
