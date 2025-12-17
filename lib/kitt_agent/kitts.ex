defmodule KittAgent.Kitts do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt

  use BasicContexts, repo: Repo, funcs: [:get, :create, :all],
    attrs: [singular: :kitt, plural: :kitts, schema: Kitt, preload: :biography]

  def create(attr, bio \\ %{}) do
    with {:ok, o} <- create_kitt(attr) do
      o
      |> Ecto.build_assoc(:biography, bio)
      |> Repo.insert!
    end
  end
      
end
