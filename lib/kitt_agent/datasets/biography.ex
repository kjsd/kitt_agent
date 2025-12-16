defmodule KittAgent.Datasets.Biography do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:personality]}
  schema "biographies" do
    field :personality, :string

    belongs_to :kitt, KittAgent.Datasets.Kitt, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:personality])
  end
end
