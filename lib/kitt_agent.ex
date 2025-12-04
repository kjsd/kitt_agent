defmodule KittAgent do
  @moduledoc """
  KittAgent keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias KittAgent.Events
  alias KittAgent.Prompts

  def make_llm_request(), do: Prompts.make()

  def user_talk(x), do: Events.add_user_text(x)
  def kitt_responce(x), do: Events.add_kitt_event(x)
end
