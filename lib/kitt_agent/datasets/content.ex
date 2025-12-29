defmodule KittAgent.Datasets.Content do
  use Ecto.Schema
  import Ecto.Changeset

  use BasicContexts.Constants
  
  @derive {Jason.Encoder, only: [:id, :action, :message, :listener, :mood, :status,
                                 :system_actions]}
  schema "contents" do
    field :action, :string
    field :message, :string
    field :listener, :string
    field :mood, :string
    field :status, :string, default: "completed"

    belongs_to :event, KittAgent.Datasets.Event
    has_many :system_actions, KittAgent.Datasets.SystemAction
    
    timestamps()
  end

  define status_pending, "pending"
  define status_processing, "processing"
  define status_completed, "completed"
  define status_fail, "fail"

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:action, :message, :listener, :mood, :status])
    |> validate_required([:action, :message, :status])
    |> cast_assoc(:system_actions)
  end
end
