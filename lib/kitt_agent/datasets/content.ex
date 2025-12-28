defmodule KittAgent.Datasets.Content do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :action, :message, :listener, :mood, :status,
                                 :system_actions]}
  schema "contents" do
    field :action, :string
    field :message, :string
    field :listener, :string
    field :mood, :string
    field :status, :string, default: "pending"

    belongs_to :event, KittAgent.Datasets.Event
    has_many :system_actions, KittAgent.Datasets.SystemAction
    
    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:action, :message, :listener, :mood, :status])
    |> validate_required([:action, :message, :status])
    |> cast_assoc(:system_actions)
  end
end
