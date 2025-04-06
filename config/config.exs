# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pii_monitor,
  generators: [timestamp_type: :utc_datetime]

# PII Monitor Configuration
config :pii_monitor, PiiMonitor.Monitoring,
  slack_channels: System.get_env("SLACK_MONITORED_CHANNELS"),
  notion_databases: System.get_env("NOTION_MONITORED_DATABASES"),
  monitoring_interval_ms: String.to_integer(System.get_env("MONITORING_INTERVAL_MS", "1000"))

# API Credentials
config :pii_monitor,
  slack_api_token: System.get_env("SLACK_API_TOKEN"),
  notion_api_key: System.get_env("NOTION_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  openai_organization_key: System.get_env("OPENAI_ORGANIZATION_KEY")

# Configures the endpoint
config :pii_monitor, PiiMonitorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PiiMonitorWeb.ErrorHTML, json: PiiMonitorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PiiMonitor.PubSub,
  live_view: [signing_salt: "IE6C+vJi"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  pii_monitor: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  pii_monitor: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
