defmodule KittAgent.Configs do
  import Ecto.Query, warn: false
  alias KittAgent.Repo
  alias KittAgent.Datasets.Config

  def get(key), do: Repo.get_by(Config, key: to_string(key))

  def get_config(key, default \\ nil) do
    key_str = to_string(key)
    cache_key = {__MODULE__, key_str}

    case :persistent_term.get(cache_key, :miss) do
      {:cached, v} when not is_nil(v) ->
        v

      {:cached, nil} ->
        default

      :miss ->
        try do
          case get(key_str) do
            %Config{value: v} ->
              :persistent_term.put(cache_key, {:cached, v})
              if is_nil(v), do: default, else: v

            nil ->
              :persistent_term.put(cache_key, {:cached, nil})
              default
          end
        rescue
          _ -> default
        catch
          :exit, _ -> default
        end
    end
  end

  def set_config(key, value) do
    key_str = to_string(key)
    value_str = if value, do: to_string(value), else: nil

    result =
      case Repo.get_by(Config, key: key_str) do
        nil ->
          %Config{}
          |> Config.changeset(%{key: key_str, value: value_str})
          |> Repo.insert()

        config ->
          config
          |> Config.changeset(%{value: value_str})
          |> Repo.update()
      end

    case result do
      {:ok, %Config{value: v}} ->
        :persistent_term.put({__MODULE__, key_str}, {:cached, v})

      _ ->
        :persistent_term.erase({__MODULE__, key_str})
    end

    result
  end

  def invalidate_cache(key) do
    :persistent_term.erase({__MODULE__, to_string(key)})
    :ok
  end

  def all_configs do
    Repo.all(Config)
    |> Enum.into(%{}, fn c ->
      :persistent_term.put({__MODULE__, c.key}, {:cached, c.value})
      {c.key, c.value}
    end)
  end
end
