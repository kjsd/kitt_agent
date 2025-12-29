defmodule KittAgent.Repo.Migrations.CreateConfigs do
  use Ecto.Migration

  def change do
    create table(:configs) do
      add :key, :string, null: false
      add :value, :text
      timestamps()
    end

    create unique_index(:configs, [:key])
  end
end
