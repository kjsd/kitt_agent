defmodule KittAgent.Repo.Migrations.AddStatusToContents do
  use Ecto.Migration

  def change do
    alter table(:contents) do
      add :status, :string, default: "pending", null: false
    end
  end
end