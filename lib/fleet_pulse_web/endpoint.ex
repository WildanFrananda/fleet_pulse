defmodule FleetPulseWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :fleet_pulse

  @session_options [
    store: :cookie,
    key: "_fleet_pulse_key",
    signing_salt: "99JSgBpt",
    same_site: "Lax"
  ]

  @drainer [batch_size: 1_000, batch_interval: 1_000, shutdown: 8_000]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]],
    drainer: @drainer

  socket "/driver", FleetPulseWeb.DriverSocket,
    websocket: [
      connect_info: [:peer_data, :user_agent],
      error_handler: {FleetPulseWeb.DriverSocket, :handle_error, []}
    ],
    longpoll: false,
    drainer: @drainer

  socket "/merchant", FleetPulseWeb.MerchantSocket,
    websocket: [
      connect_info: [:peer_data, :user_agent],
      error_handler: {FleetPulseWeb.MerchantSocket, :handle_error, []}
    ],
    longpoll: false,
    drainer: @drainer

  plug FleetPulseWeb.Plugs.HttpMetrics

  plug Plug.Static,
    at: "/",
    from: :fleet_pulse,
    gzip: not code_reloading?,
    only: FleetPulseWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :fleet_pulse
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug FleetPulseWeb.Router
end
