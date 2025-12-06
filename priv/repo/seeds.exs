# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     KittAgent.Repo.insert!(%KittAgent.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias KittAgent.Kitts

today = BasicContexts.Utils.today_jpn

%{
  name: "キット",
  vendor: "Makeblock",
  model: "mBot2",
  birthday: today,
  hometown: "東白川村，日本"
}
|> Kitts.create_kitt()
