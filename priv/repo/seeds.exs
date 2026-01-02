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

today = BasicContexts.Utils.today_jpn()
personality = "%%NAME%%'s tone is identical to Knight Rider's K.I.T.T."

%{
  id: "2d16ba43-3eb0-46c2-9583-e38dbb82c5fa",
  name: "キット",
  lang: "Japanese",
  timezone: "Asia/Tokyo",
  biography: %{
    vendor: "Makeblock",
    model: "mBot2",
    birthday: today,
    hometown: "東白川村，日本",
    personality: personality
  }
}
|> Kitts.create_kitt()
