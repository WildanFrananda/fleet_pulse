defmodule FleetPulseWeb.Router do
  use FleetPulseWeb, :router

  import FleetPulseWeb.AdminAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FleetPulseWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_admin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug FleetPulseWeb.Plugs.IdentityAuth
  end

  scope "/", FleetPulseWeb do
    get "/health", HealthController, :live
    get "/health/ready", HealthController, :ready
    get "/metrics", MetricsController, :index
  end

  scope "/", FleetPulseWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/admin/log_in", AdminSessionController, :new
    post "/admin/log_in", AdminSessionController, :create
    delete "/admin/log_out", AdminSessionController, :delete
  end

  scope "/", FleetPulseWeb do
    pipe_through [:browser, :require_authenticated_admin]

    live_session :require_authenticated_admin,
      on_mount: [{FleetPulseWeb.AdminAuth, :ensure_authenticated}] do
      live "/dispatch", DispatchLive
    end
  end


  scope "/", FleetPulseWeb do
    pipe_through [:api, :throttle_register]
    post "/driver/register", DriverRegistrationController, :create
  end

  pipeline :throttle_register do
    plug FleetPulseWeb.Plugs.RateLimit, bucket: :register
  end

  pipeline :fleet_reader do
    plug FleetPulseWeb.Plugs.RequireRole, ["seller", "admin"]
  end

  scope "/api/v1", FleetPulseWeb.Api.V1, as: :api_v1 do
    pipe_through [:authenticated_api, :fleet_reader]

    get "/drivers", DriverController, :index
    get "/drivers/nearby", DriverController, :nearby
    get "/drivers/:id", DriverController, :show
    get "/orders/:id", OrderController, :show
    post "/merchant/orders", MerchantOrderController, :create
  end

  scope "/api/v1", FleetPulseWeb.Api.V1, as: :api_v1 do
    pipe_through :authenticated_api

    post "/shipping/options", ShippingController, :options
  end

  if Application.compile_env(:fleet_pulse, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FleetPulseWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
