defmodule KittAgent.Datasets.Content do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:action, :message, :listener, :mood]}
  schema "contents" do
    field :action, :string
    field :message, :string
    field :listener, :string
    field :mood, :string

    belongs_to :event, KittAgent.Datasets.Event
    has_many :system_actions, KittAgent.Datasets.SystemAction
    
    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:action, :message, :listener, :mood])
    |> validate_required([:action, :message])
  end
end
