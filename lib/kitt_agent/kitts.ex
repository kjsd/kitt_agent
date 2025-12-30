defmodule KittAgent.Kitts do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt
  alias KittAgent.SystemActions.Queue

  use BasicContexts,
    repo: Repo,
    funcs: [:get, :create, :update, :delete, :change, :all],
    attrs: [singular: :kitt, plural: :kitts, schema: Kitt, preload: :biography,
           order_by: :inserted_at]

  use BasicContexts.PartialList,
    repo: Repo,
    plural: :kitts,
    schema: Kitt,
    last_fn: fn query, _ ->
      query
      |> preload(:biography)
  end

  def delete(%Kitt{id: id, audio_path: old} = kitt) do
    with {:ok, _} = x <- delete_kitt(kitt) do
      delete_audio(old)
      Queue.terminate(id)
      x
    end
  end

  def update(%Kitt{audio_path: old} = kitt, %{"audio_path" => new} = attr)
  when is_binary(old) do
    
    if old != new do
      with {:ok, _} = x <- update_kitt(kitt, attr) do
        delete_audio(old)
        x
      end
    else
      update_kitt(kitt, attr)
    end
  end
  def update(kitt, attr), do: update_kitt(kitt, attr)
    
  defp delete_audio(path) when is_binary(path) do
    filename = Path.basename(path)
    local_path = Path.join("uploads", filename)

    if File.exists?(local_path) do
      File.rm(local_path)
    end
  end
  defp delete_audio(_), do: nil

end
