defmodule KittAgent.Requests do
  alias KittAgent.Requests.OpenRouter
  alias KittAgent.Requests.OpenAITTS
  alias KittAgent.Voice.Zonos2Client

  alias KittAgent.Datasets.{Kitt, Content}

  def list_models(), do: OpenRouter.list_models()
  def talk(%Kitt{} = k, t), do: OpenRouter.talk(k, t)
  def summary(%Kitt{} = k, [_ | _] = e), do: OpenRouter.summary(k, e)

  def process_tts(%Content{} = c, %Kitt{} = k) do
    provider = KittAgent.Configs.get_config("tts_provider", "zonos2")

    case provider do
      "openai" ->
        OpenAITTS.process(c, k)

      _zonos2 ->
        Zonos2Client.process(c, k)
    end
  end
end
