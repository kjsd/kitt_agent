defmodule KittAgent do
  @moduledoc """
  KittAgent keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Requests
  alias KittAgent.Voice.WhisperClient

  def talk(%Kitt{} = k, x), do: Requests.talk(k, x)
  def transcribe(audio_source, opts \\ []), do: WhisperClient.transcribe(audio_source, opts)
end
