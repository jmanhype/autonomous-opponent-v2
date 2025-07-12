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
    
    # Add IP-based rate limiting
    plug AutonomousOpponentV2Core.Core.IPRateLimiter,
      algorithm: :sliding_window,
      rate_limiter: :api_rate_limiter,
      window_ms: 60_000,      # 1 minute window
      max_requests: 60,       # 60 requests per minute
      whitelist: ["127.0.0.1", "::1"]  # Allow localhost
  end
  
  pipeline :api_auth do
    plug :accepts, ["json"]
    plug AutonomousOpponentV2Web.Plugs.JWTAuthPlug, required: true
  end
  
  pipeline :api_auth_optional do
    plug :accepts, ["json"]
    plug AutonomousOpponentV2Web.Plugs.JWTAuthPlug, required: false
  end
  
  pipeline :sse do
    plug :accepts, ["html", "text"]
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
    live "/dashboard", DashboardLive
    live "/consciousness", ConsciousnessLive, :index
    live "/chat", ChatLive, :index
    
    # Pattern Analytics Dashboard - Issue #92 (temporarily public for testing)
    live "/patterns/analytics", PatternAnalyticsLive, :index
  end
  
  # Protected dashboards
  scope "/", AutonomousOpponentV2Web do
    pipe_through :authenticated_browser
    
    # VSM Metrics Dashboard
    live "/metrics/dashboard", MetricsDashboardLive, :index
    
    # Web Gateway Dashboard
    live "/web-gateway/dashboard", WebGatewayDashboardLive, :index
    
    # EventBus Ordering Dashboard
    live "/eventbus/ordering", EventOrderingLive, :index
    
    # Pattern Flow Dashboard
    live "/patterns/flow", PatternFlowLive, :index
    
    # Belief Consensus Dashboard
    live "/beliefs/consensus", BeliefConsensusLive, :index
  end
  
  # Web Gateway endpoints
  scope "/web-gateway", AutonomousOpponentV2Web do
    pipe_through :sse
    
    # Server-Sent Events endpoint (supports optional authentication)
    get "/sse", WebGatewaySSEController, :stream
  end
  
  # Prometheus metrics endpoint (no CSRF protection needed)
  scope "/", AutonomousOpponentV2Web do
    get "/metrics", MetricsController, :index
    get "/metrics/cluster", MetricsController, :cluster
    get "/metrics/vsm_health", MetricsController, :vsm_health
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
    
    # Test endpoint
    post "/test", ConsciousnessController, :test
    
    # AI Consciousness API endpoints
    post "/consciousness/chat", ConsciousnessController, :chat
    post "/consciousness/test", ConsciousnessController, :test
    get "/consciousness/state", ConsciousnessController, :state
    get "/consciousness/dialog", ConsciousnessController, :inner_dialog
    post "/consciousness/reflect", ConsciousnessController, :reflect
    get "/patterns", ConsciousnessController, :patterns
    get "/events/analyze", ConsciousnessController, :analyze_events
    get "/memory/synthesize", ConsciousnessController, :synthesize_memory
    
    # VSM API endpoints
    get "/vsm/state", VSMController, :state
    get "/vsm/metrics", VSMController, :metrics
    post "/vsm/algedonic", VSMController, :algedonic
    
    # Debug endpoint for seeding data (dev only)
    if Mix.env() == :dev do
      post "/debug/seed", ConsciousnessController, :seed_data
    end
  end

  # Enables LiveDashboard only on development environment
  # as it will show data from all your apps.
  if Mix.env() in [:dev, :test] do
    scope "/dev/dashboard", host: "*" do
      pipe_through [:browser]

      live_dashboard("/",
        metrics: AutonomousOpponentV2Web.Telemetry,
        additional_pages: [
          consciousness: {AutonomousOpponentV2Web.ConsciousnessPage, []}
        ]
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
