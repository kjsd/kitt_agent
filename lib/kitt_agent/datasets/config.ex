defmodule KittAgent.Datasets.Config do
  use Ecto.Schema
  import Ecto.Changeset

  schema "configs" do
    field :key, :string
    field :value, :string

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
