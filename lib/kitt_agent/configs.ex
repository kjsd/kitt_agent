defmodule KittAgent.Configs do
  import Ecto.Query, warn: false
  alias KittAgent.Repo
  alias KittAgent.Datasets.Config

  def get_config(key, default \\ nil) do
    case Repo.get_by(Config, key: to_string(key)) do
      nil -> default
      config -> config.value
    end
  end

  def set_config(key, value) do
    key_str = to_string(key)
    value_str = if value, do: to_string(value), else: nil

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
  end

  def all_configs do
    Repo.all(Config)
    |> Enum.into(%{}, fn c -> {c.key, c.value} end)
  end
end
