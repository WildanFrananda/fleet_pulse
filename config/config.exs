import Config

config :fleet_pulse, start_grpc_server: true

config :fleet_pulse,
  ecto_repos: [FleetPulse.Repo],
  generators: [timestamp_type: :utc_datetime]

config :fleet_pulse, FleetPulseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FleetPulseWeb.ErrorHTML, json: FleetPulseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FleetPulse.PubSub,
  live_view: [signing_salt: "5WcZjYkx"],
  http: [thousand_island_options: [shutdown_timeout: 10_000]]

config :fleet_pulse, FleetPulse.GrpcDrain, budget_ms: 5_000

config :fleet_pulse, FleetPulse.Tracking.PersistenceBatcher,
  enabled: true,
  interval_ms: 30_000,
  chunk_size: 1_000

config :fleet_pulse, FleetPulse.Tracking.IdleReaper,
  enabled: true,
  interval_ms: 60_000,
  idle_after_ms: 900_000

config :fleet_pulse, FleetPulse.Dispatch.ReDispatcher,
  enabled: true,
  debounce_ms: 1_000

config :fleet_pulse, FleetPulse.Tracking.PingRetention,
  enabled: true,
  interval_ms: :timer.hours(24),
  retention_ms: :timer.hours(24 * 30)

config :fleet_pulse, FleetPulseWeb.Plugs.RateLimit,
  enabled: true,
  scale_ms: 60_000,
  register: 3

config :fleet_pulse, FleetPulseWeb.DispatchLive, flush_interval_ms: 500

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

config :fleet_pulse, FleetPulse.Mailer, adapter: Swoosh.Adapters.Local

config :esbuild,
  version: "0.25.4",
  fleet_pulse: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.0",
  fleet_pulse: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter, metadata: :all

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
