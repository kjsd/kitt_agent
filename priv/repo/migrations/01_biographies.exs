defmodule KittAgent.Repo.Migrations.Biographies do
  use Ecto.Migration

  def change do
    create table("biographies") do
      add :model, :string
      add :vendor, :string
      add :birthday, :date
      add :hometown, :string
      add :personality, :string

      add :kitt_id, references(:kitts, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end
  end
end
