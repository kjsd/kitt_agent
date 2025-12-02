defmodule KittAgentWeb.MainController do
  use KittAgentWeb, :controller

  require Logger
  
  @llm_url "https://openrouter.ai/api/v1/chat/completions"
  @llm_model "google/gemini-2.5-flash-lite"

  # Cartesia (TTS用)
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
end
