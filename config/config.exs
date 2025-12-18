# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kitt_agent,
  api_urls: [
    openrouter: "https://openrouter.ai/api/v1/chat/completions",
    cartesia: "https://api.cartesia.ai/tts/bytes"
  ]

config :kitt_agent,
  ecto_repos: [KittAgent.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :kitt_agent, KittAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KittAgentWeb.ErrorHTML, json: KittAgentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: KittAgent.PubSub,
  live_view: [signing_salt: "Re36i3vR"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  kitt_agent: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  kitt_agent: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

for config <- ["#{config_env()}.secret.exs"] |> Path.expand(__DIR__) |> Path.wildcard() do
  if File.exists?(config), do: import_config(config)
end
