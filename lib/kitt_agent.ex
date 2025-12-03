defmodule KittAgent do
  @moduledoc """
  KittAgent keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias KittAgent.Events
  alias KittAgent.Prompts

  def prompt(user_text) do
    Events.add_user_text(user_text)

    Prompts.make()
  end
  
  def kitt_responce(x), do: Events.add_kitt_event(x)
end
