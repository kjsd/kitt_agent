defmodule KittAgent.Repo.Migrations.Kitts do
  use Ecto.Migration

  def change do
    create table(:kitts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :model, :string
      add :vendor, :string
      add :birthday, :date
      add :hometown, :string

      timestamps()
    end
  end
end
