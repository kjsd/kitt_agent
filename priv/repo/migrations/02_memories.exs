defmodule KittAgent.Repo.Migrations.Memories do
  use Ecto.Migration

  def change do
    create table("memories") do
      add :content, :text

      add :kitt_id, references(:kitts, type: :binary_id)

      timestamps()
    end
  end
end
