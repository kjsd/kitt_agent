defmodule KittAgent.Repo do
  use Ecto.Repo,
    otp_app: :kitt_agent,
    adapter: Ecto.Adapters.Postgres
end
