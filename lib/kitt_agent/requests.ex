defmodule KittAgent.Requests do
  alias KittAgent.Requests.OpenRouter
  alias KittAgent.Requests.OpenAITTS
  alias KittAgent.Requests.ZonosGradio

  alias KittAgent.Datasets.{Kitt, Content}

  def list_models(), do: OpenRouter.list_models()
  def talk(%Kitt{} = k, t), do: OpenRouter.talk(k, t)
  def summary(%Kitt{} = k, [_ | _] = e), do: OpenRouter.summary(k, e)

  def tts_provider() do
    KittAgent.Configs.get_config("tts_provider", "zonos") || "zonos"
  end

  def process_tts(%Content{} = c, %Kitt{} = k) do
    case tts_provider() do
      "openai" ->
        OpenAITTS.process(c, k)

      _zonos ->
        ZonosGradio.process(c, k)
    end
  end
end
