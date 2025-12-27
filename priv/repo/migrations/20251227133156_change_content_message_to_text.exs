defmodule KittAgent.Repo.Migrations.ChangeContentMessageToText do
  use Ecto.Migration

  def change do
    alter table(:contents) do
      modify :message, :text
    end
  end
end