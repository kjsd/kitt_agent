defmodule KittAgent.Datasets.Kitt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kitts" do
    field :name, :string
    field :model, :string
    field :vendor, :string
    field :birthday, :date
    field :hometown, :string

    has_one :biography, KittAgent.Datasets.Biography
    has_many :events, KittAgent.Datasets.Event
    has_many :memories, KittAgent.Datasets.Memory

    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:id, :name, :model, :vendor, :birthday, :hometown])
    |> validate_required([:name])
  end
end
