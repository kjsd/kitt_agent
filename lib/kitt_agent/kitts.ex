defmodule KittAgent.Kitts do
  import Ecto.Query, warn: false

  alias KittAgent.Repo
  alias KittAgent.Datasets.Kitt
  alias KittAgent.{SystemActions, TTS}

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

  def resource(%Kitt{} = kitt, x) when is_binary(x), do: resource(kitt) |> Path.join(x)
  def resource(_, _), do: nil
  def resource(%Kitt{id: id}) do
    Application.get_env(:kitt_agent, :uploads_dir) |> Path.join(id)
  end
  def resource_audio(%Kitt{audio_path: path} = kitt) when is_binary(path), 
    do: resource(kitt, Path.basename(path))
  def resource_audio(_), do: nil

  def path(%Kitt{} = kitt, x) when is_binary(x), do: path(kitt) |> Path.join(x)
  def path(_, _), do: nil
  def path(%Kitt{id: id}) do
    Application.get_env(:kitt_agent, :uploads_path) |> Path.join(id)
  end

  defp path2resource(path, %Kitt{} = kitt) when is_binary(path) do
    fname = Path.basename(path)
    src = Application.get_env(:kitt_agent, :uploads_dir) |> Path.join(fname)

    if File.exists?(src) do
      kitt
      |> resource()
      |> File.mkdir_p!()

      File.cp!(src, resource(kitt, fname))
      File.rm!(src)
    end
  end
  defp path2resource(_, _), do: :ok
      
  def create(%{"audio_path" => path} = attr) do
    with {:ok, x} <- create_kitt(attr) do
      path2resource(path, x)
      update_kitt(x, %{"audio_path" => path(x, Path.basename(path))})
    end
  end
  def create(x), do: create_kitt(x)
  
  def update(%Kitt{} = kitt, %{"audio_path" => new} = attr) do
    with {:ok, x} = res <- update_kitt(kitt, attr) do
      delete_audio(kitt)
      if is_binary(new) do
        path2resource(new, kitt)
        update_kitt(x, %{"audio_path" => path(x, Path.basename(new))})
      else
        res
      end
    end
  end
    
  def delete(%Kitt{id: id} = kitt) do
    with {:ok, _} = x <- delete_kitt(kitt) do
      kitt
      |> resource()
      |> File.rm_rf!()

      SystemActions.Queue.terminate(id)
      TTS.RequestBroker.terminate_child(id)
      x
    end
  end

  defp delete_audio(%Kitt{audio_path: path} = kitt) when is_binary(path) do
    resource(kitt, Path.basename(path))
    |> File.rm()
  end
  defp delete_audio(_), do: :ok

end
