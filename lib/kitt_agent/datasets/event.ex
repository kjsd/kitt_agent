defmodule KittAgent.Datasets.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:role]}
  schema "events" do
    field :role, :string

    belongs_to :kitt, KittAgent.Datasets.Kitt, type: :binary_id
    has_one :content, KittAgent.Datasets.Content

    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:role, :kitt_id])
    |> validate_required([:role, :kitt_id])
    |> cast_assoc(:content)
  end
end
