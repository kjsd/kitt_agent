defmodule KittAgent.Datasets.Kitt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Jason.Encoder,
           only: [:id, :name, :lang, :timezone, :biography]}
  schema "kitts" do
    field :name, :string
    field :lang, :string, default: "English"
    field :timezone, :string, default: "Etc/UTC"
    field :audio_path, :string

    has_one :biography, KittAgent.Datasets.Biography
    has_many :events, KittAgent.Datasets.Event
    has_many :memories, KittAgent.Datasets.Memory

    timestamps()
  end

  @doc false
  def changeset(o, attrs) do
    o
    |> cast(attrs, [
      :id,
      :name,
      :lang,
      :timezone,
      :audio_path
    ])
    |> validate_required([:name])
    |> cast_assoc(:biography)
  end
end
