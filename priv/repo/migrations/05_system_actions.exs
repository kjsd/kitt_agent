defmodule KittAgent.Repo.Migrations.SystemActions do
  use Ecto.Migration

  def change do
    create table("system_actions") do
      add :action, :string, null: false
      add :parameter, :string, null: false
      add :target, :string

      add :content_id, references(:contents, on_delete: :delete_all), null: false

      timestamps()
    end
  end
end
