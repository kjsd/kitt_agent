defmodule KittAgent.Repo.Migrations.AddParametersToContents do
  use Ecto.Migration

  def change do
    alter table(:contents) do
      add :parameters, :string
    end
  end
end
