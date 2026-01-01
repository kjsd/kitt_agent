defmodule KittAgent.Requests do
  alias KittAgent.Requests.OpenRouter
  alias KittAgent.Requests.ZonosGradio

  alias KittAgent.Datasets.{Kitt, Content}

  def list_models(), do: OpenRouter.list_models()
  def talk(%Kitt{} = k, t), do: OpenRouter.talk(k, t)
  def summary(%Kitt{} = k, [_ | _] = e), do: OpenRouter.summary(k, e)
  def process_tts(%Content{} = c, %Kitt{} = k), do: ZonosGradio.process(c, k)
end
