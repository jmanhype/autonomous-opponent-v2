defmodule AutonomousOpponentV2Web.Router do
  use AutonomousOpponentV2Web, :router

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {AutonomousOpponentV2Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AutonomousOpponentV2Web do
    pipe_through :browser

    get "/", PageController, :home
    
    # VSM Metrics Dashboard
    live "/metrics/dashboard", MetricsDashboardLive, :index
  end
  
  # Prometheus metrics endpoint (no CSRF protection needed)
  scope "/", AutonomousOpponentV2Web do
    get "/metrics", MetricsController, :index
  end
  
  # Health check endpoint
  scope "/", AutonomousOpponentV2Web do
    pipe_through :api
    get "/health", HealthCheckController, :index
  end

  # MCP Gateway SSE endpoints
  scope "/mcp", AutonomousOpponentV2Web do
    get "/sse/connect", MCPSSEController, :connect
    get "/sse/events/:topic", MCPSSEController, :events
  end
  
  # Other scopes may use the generated code from Phoenix
  # for controllers and views, but here you can control
  # any modules with the `AutonomousOpponentV2Web` namespace.
  scope "/api", AutonomousOpponentV2Web do
    pipe_through :api
  end

  # Enables LiveDashboard only on development environment
  # as it will show data from all your apps.
  if Mix.env() in [:dev, :test] do
    scope "/dev/dashboard", host: "*" do
      pipe_through [:browser]

      live_dashboard("/",
        metrics: {AutonomousOpponentV2Web.Telemetry, :metrics}
      )
    end
  end

  # Enables the Swoosh mailbox preview in development.
  #
  # For more information see: https://hexdocs.pm/swoosh/Swoosh.html#mailbox_preview/1
  if Mix.env() == :dev do
    scope "/dev/mailbox" do
      pipe_through [:browser]
      forward "/", Plug.Swoosh.MailboxPreview
    end
  end
end
