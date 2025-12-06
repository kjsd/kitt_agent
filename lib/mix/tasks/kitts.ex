defmodule Mix.Tasks.Kitts do
  use Mix.Task

  def run(_) do
    Mix.Task.run("app.start")
    
    KittAgent.Datasets.Kitt
    |> KittAgent.Repo.all
    |> IO.inspect
  end
end
