defmodule KittAgent.Kitts do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt
  alias KittAgent.SystemActions.Queue

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

  def delete(%Kitt{} = kitt) do
    Queue.terminate(kitt.id)
    delete_kitt(kitt)
  end
  
end
