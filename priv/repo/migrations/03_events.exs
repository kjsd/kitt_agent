defmodule KittAgent.Repo.Migrations.Events do
  use Ecto.Migration

  def change do
    create table("events") do
      add :role, :string, null: false

      add :kitt_id, references(:kitts, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end
  end
end
