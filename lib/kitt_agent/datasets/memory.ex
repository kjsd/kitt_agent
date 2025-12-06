defmodule KittAgent.Datasets.Memory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "memory" do
    field :content, :string

    belongs_to :kitt, KittAgent.Datasets.Kitt, type: :binary_id
    
    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:content])
    |> validate_required([:content])
  end
end
