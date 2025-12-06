defmodule KittAgent.Kitts do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt

  use BasicContexts, repo: Repo, funcs: [:get, :create],
    attrs: [singular: :kitt, plural: :kitts, schema: Kitt]
end
