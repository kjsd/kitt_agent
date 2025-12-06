defmodule KittAgent.Memories do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Memory

  use BasicContexts, repo: Repo, funcs: [:get, :create],
    attrs: [singular: :memory, plural: :memories, schema: Memory]

  def last() do
    Memory
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one
  end

end
