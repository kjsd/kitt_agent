import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :kitt_agent, KittAgent.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DB_HOST") || "db",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  database: "kitt_agent_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kitt_agent, KittAgentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "QLWoEFLuRzNkclV1OCSvOEAnZANNMFblEhenikMHYeNWRvQfcZh/mo9HWFpqj0dL",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable summarizer in tests to avoid async DB errors
config :kitt_agent, KittAgent.Requests, talk: [enable_summarizer: false]
