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
  
  pipeline :api_auth do
    plug :accepts, ["json"]
    plug AutonomousOpponentV2Web.Plugs.JWTAuthPlug, required: true
  end
  
  pipeline :api_auth_optional do
    plug :accepts, ["json"]
    plug AutonomousOpponentV2Web.Plugs.JWTAuthPlug, required: false
  end

  # Define authenticated browser pipeline
  pipeline :authenticated_browser do
    plug :browser
    plug AutonomousOpponentV2Web.Plugs.JWTAuthPlug, required: true
  end
  
  scope "/", AutonomousOpponentV2Web do
    pipe_through :browser

    get "/", PageController, :home
  end
  
  # Protected dashboards
  scope "/", AutonomousOpponentV2Web do
    pipe_through :authenticated_browser
    
    # VSM Metrics Dashboard
    live "/metrics/dashboard", MetricsDashboardLive, :index
    
    # MCP Gateway Dashboard
    live "/mcp/dashboard", MCPDashboardLive, :index
  end
  
  # MCP Gateway endpoints
  scope "/mcp", AutonomousOpponentV2Web do
    pipe_through :api_auth_optional
    
    # Server-Sent Events endpoint (supports optional authentication)
    get "/sse", MCPSSEController, :stream
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
