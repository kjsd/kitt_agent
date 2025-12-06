defmodule KittAgent.Kitts do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt

  use BasicContexts, repo: Repo, funcs: [:get, :create],
    attrs: [singular: :kitt, plural: :kitts, schema: Kitt]

  def create(attr, bio \\ %{}) do
    with {:ok, o} <- create_kitt(attr) do
      o
      |> Ecto.build_assoc(:biography, bio)
      |> Repo.insert!

      {:ok, Repo.preload(o, :biography)}
    end
  end

  def biography(%Kitt{} = kitt) do
    kitt
    |> Repo.preload(:biography)
    |> then(&(&1.biography))
  end
      
end
