defmodule KittAgent.Repo.Migrations.Contents do
  use Ecto.Migration

  def change do
    create table("contents") do
      add :action, :string, null: false
      add :parameter, :text
      add :message, :text, null: false
      add :listener, :string
      add :mood, :string
      add :status, :string, default: "pending", null: false
      add :audio_path, :string

      add :event_id, references(:events, on_delete: :delete_all), null: false

      timestamps()
    end
  end
end
