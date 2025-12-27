defmodule KittAgent.Datasets.SystemAction do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:action, :parameter, :target]}
  schema "system_actions" do
    field :action, :string
    field :parameter, :string
    field :target, :string

    belongs_to :content, KittAgent.Datasets.Content
    
    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:action, :parameter, :target])
    |> validate_required([:action, :parameter])
  end
end
