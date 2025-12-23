defmodule KittAgent.Repo.Migrations.ModifyMemoriesContentToText do
  use Ecto.Migration

  def change do
    alter table(:memories) do
      modify :content, :text
    end
  end
end
