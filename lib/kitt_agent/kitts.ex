defmodule KittAgent.Kitts do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt

  use BasicContexts,
    repo: Repo,
    funcs: [:get, :create, :update, :delete, :change, :all],
    attrs: [singular: :kitt, plural: :kitts, schema: Kitt, preload: :biography]

  use BasicContexts.PartialList,
    repo: Repo,
    plural: :kitts,
    schema: Kitt,
    last_fn: fn query, _ ->
      query
      |> preload(:biography)
  end

end
