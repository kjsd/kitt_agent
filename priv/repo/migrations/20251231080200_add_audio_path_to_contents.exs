defmodule KittAgent.Repo.Migrations.AddAudioPathToContents do
  use Ecto.Migration

  def change do
    alter table(:contents) do
      add :audio_path, :string
    end
  end
end