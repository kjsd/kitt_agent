defmodule Mix.Tasks.Kitts do
  use Mix.Task

  import Ecto.Query, warn: false

  def run(_) do
    Mix.Task.run("app.start")
    
    KittAgent.Datasets.Kitt
    |> preload(:biography)
    |> KittAgent.Repo.all
    |> IO.inspect
  end
end
