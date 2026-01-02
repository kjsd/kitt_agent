defmodule KittAgent.Datasets.Biography do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:model, :vendor, :birthday, :hometown, :personality]}
  schema "biographies" do
    field :model, :string
    field :vendor, :string
    field :birthday, :date
    field :hometown, :string
    field :personality, :string

    belongs_to :kitt, KittAgent.Datasets.Kitt, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:model, :vendor, :birthday, :hometown, :personality])
    |> validate_required([:personality])
  end
end
