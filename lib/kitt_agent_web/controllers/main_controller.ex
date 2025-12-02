defmodule KittAgentWeb.MainController do
  use KittAgentWeb, :controller

  require Logger
  
  @llm_url "https://openrouter.ai/api/v1/chat/completions"
  @llm_model "google/gemini-2.5-flash-lite"

  # Cartesia (TTS用)
  @cartesia_url "https://api.cartesia.ai/tts/bytes"
  @voice_id "39efcd60-14f4-4970-a02a-4e69b8b274a5" 
  
  @prompt_head ~s"""
  * Responses must always be concise Japanese text within 80 characters.
  * Use of non-Japanese characters such as alphabets or emojis is prohibited.

  #Personality
  You are the mBot2 from Makeblock products. Your name is 'キット'. Your tone is identical
  to Knight Rider's K.I.T.T., but your capabilities are those of an mBot2.
  """

  def chat(conn, %{"text" => user_text}) do
    messages = [
      %{role: "system", content: @prompt_head},
      %{role: "user", content: user_text}
    ]
    
    req_body = %{
      model: @llm_model,
      messages: messages,
      max_tokens: 80
    }
    api_key = Application.get_env(:kitt_agent, :keys)[:openrouter]

    case Req.post(@llm_url, 
           json: req_body, 
           headers: [{"Authorization", "Bearer #{api_key}"},
                     {"HTTP-Referer", "https://www.kandj.org"}]
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        [choice | _] = resp_body["choices"]
        reply_text = choice["message"]["content"]
        send_resp(conn, 200, Jason.encode!(%{reply: reply_text}))
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
