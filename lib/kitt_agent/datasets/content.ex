defmodule KittAgent.Datasets.Content do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:action, :message, :target, :timestamp]}
  schema "contents" do
    field :action, :string
    field :message, :string
    field :target, :string
    field :mood, :string
    field :timestamp, :naive_datetime

    belongs_to :event, KittAgent.Datasets.Event

    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:action, :message, :target, :mood, :timestamp])
    |> validate_required([:action, :message])
  end
end
