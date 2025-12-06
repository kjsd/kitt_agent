defmodule KittAgent do
  @moduledoc """
  KittAgent keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Events
  alias KittAgent.Prompts

  def make_llm_request(%Kitt{} = k), do: Prompts.make(k)

  def user_talk(%Kitt{} = k, x), do: Events.add_user_text(k, x)
  def kitt_responce(%Kitt{} = k, x), do: Events.add_kitt_event(k, x)
end
