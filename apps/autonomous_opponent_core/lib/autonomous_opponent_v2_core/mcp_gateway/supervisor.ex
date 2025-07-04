defmodule AutonomousOpponentV2Core.MCPGateway.Supervisor do
  @moduledoc """
  Supervisor for the MCP Gateway subsystem.
  
  Manages all MCP Gateway components including:
  - Transport handlers (HTTP+SSE, WebSocket)
  - Connection pools
  - Gateway router
  - Health monitoring
  
  ## Wisdom Preservation
  
  ### Why a Dedicated Supervisor?
  The MCP Gateway is a critical subsystem that bridges external connections
  to our internal VSM architecture. It needs isolated supervision to prevent
  cascading failures and enable independent restart strategies.
  
  ### Design Decisions
  1. **Rest-for-One Strategy**: Components depend on each other in order.
     If the router fails, transports need to restart to re-register.
  
  2. **Isolated Failure Domain**: Gateway failures shouldn't affect VSM core.
     This supervisor acts as a bulkhead, containing failures.
  """
  use Supervisor
  require Logger
  
  alias AutonomousOpponentV2Core.MCPGateway.{
    Router,
    ConnectionPool,
    HealthMonitor,
    TransportRegistry
  }
  
  def start_link(opts) do
    name = opts[:name] || __MODULE__
    Supervisor.start_link(__MODULE__, opts, name: name)
  end
  
  @impl true
  def init(opts) do
    children = [
      # Transport registry must start first
      {TransportRegistry, name: TransportRegistry},
      
      # Connection pool for managing connections
      {ConnectionPool, 
        name: ConnectionPool,
        pool_size: opts[:pool_size] || 50,
        max_overflow: opts[:max_overflow] || 10
      },
      
      # Gateway router with consistent hashing
      {Router,
        name: Router,
        hash_ring_size: opts[:hash_ring_size] || 1024
      },
      
      # Health monitoring
      {HealthMonitor,
        name: HealthMonitor,
        check_interval: opts[:health_check_interval] || 5_000
      }
    ]
    
    Logger.info("Starting MCP Gateway supervisor with #{length(children)} children")
    
    # Rest-for-one: if router fails, restart everything after it
    Supervisor.init(children, strategy: :rest_for_one)
  end
  
  @doc """
  Get the current status of all MCP Gateway components
  """
  def status do
    %{
      transport_registry: TransportRegistry.status(),
      connection_pool: ConnectionPool.status(),
      router: Router.status(),
      health: HealthMonitor.status()
    }
  end
end