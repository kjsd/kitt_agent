defmodule KittAgent.Datasets.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :role, :content]}
  schema "events" do
    field :role, :string
    field :content, :map

    belongs_to :kitt, KittAgent.Datasets.Kitt, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:role, :content])
    |> validate_required([:role, :content])
  end
end
