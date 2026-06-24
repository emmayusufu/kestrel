# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kestrel,
  generators: [timestamp_type: :utc_datetime]

# Kestrel paper-trading engine. All virtual money, no real orders. Every
# market here runs every strategy from Kestrel.Strategies as its own process.
config :kestrel, :start_engine, true

config :kestrel, Kestrel.Engine,
  products: ["BTC-USD", "ETH-USD", "SOL-USD"],
  poll_ms: 10_000,
  start_cash: 20.0,
  fee_rate: 0.006

# Where bot state is persisted (DETS file), so it survives restarts.
config :kestrel, Kestrel.Store, path: "priv/kestrel_store.dets"

# Configures the endpoint
config :kestrel, KestrelWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KestrelWeb.ErrorHTML, json: KestrelWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kestrel.PubSub,
  live_view: [signing_salt: "cVi+KLbN"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  kestrel: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  kestrel: [
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
