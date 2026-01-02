defmodule KittAgent.Datasets.SystemAction do
  use Ecto.Schema
  import Ecto.Changeset

  use BasicContexts.Constants

  @derive {Jason.Encoder, only: [:action, :parameter, :content_id]}
  schema "system_actions" do
    field :action, :string
    field :parameter, :string

    belongs_to :content, KittAgent.Datasets.Content

    timestamps()
  end

  define(execute_code, "ExecuteCode")
  
  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [:action, :parameter])
    |> validate_required([:action, :parameter])
  end
end
