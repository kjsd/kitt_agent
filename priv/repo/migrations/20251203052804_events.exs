defmodule KittAgent.Repo.Migrations.Events do
  use Ecto.Migration

  def change do
    create table("events") do
      add :role,    :string
      add :content, :map

      timestamps()
    end
  end
end
