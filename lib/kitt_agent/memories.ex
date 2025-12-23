defmodule KittAgent.Memories do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Datasets.Memory

  use BasicContexts,
    repo: Repo,
    funcs: [:get],
    attrs: [singular: :memory, plural: :memories, schema: Memory]

  def create_memory(%Kitt{} = kitt, content) do
    kitt
    |> Ecto.build_assoc(:memories, %{content: content})
    |> Repo.insert()
  end

  def last_memory(%Kitt{} = kitt) do
    kitt
    |> Ecto.assoc(:memories)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def last_content(%Kitt{} = kitt) do
    kitt
    |> last_memory()
    |> then(&if(is_nil(&1), do: "", else: &1.content))
  end
end
