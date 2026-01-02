defmodule KittAgent.Datasets.SystemAction do
  use Ecto.Schema
  import Ecto.Changeset

  use BasicContexts.Constants

  @derive {Jason.Encoder, only: [:action, :parameter, :target, :content_id]}
  schema "system_actions" do
    field :action, :string
    field :parameter, :string
    field :target, :string

    belongs_to :content, KittAgent.Datasets.Content

    timestamps()
  end

  define(move_forward, "MoveForward")
  define(move_backward, "MoveBackward")
  define(turn_left, "TurnLeft")
  define(turn_right, "TurnRight")
  define(stop, "Stop")
  
  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:action, :parameter, :target])
    |> validate_required([:action, :parameter])
  end
end
