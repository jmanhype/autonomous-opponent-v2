defmodule AutonomousOpponentV2Core.Connections.Supervisor do
  @moduledoc """
  Supervisor for connection pool infrastructure.
  
  Manages:
  - PoolManager with all configured pools
  - Telemetry handlers for monitoring
  - Health check processes
  """
  
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Attach telemetry handlers
    AutonomousOpponentV2Core.Connections.Telemetry.attach_handlers()
    
    children = [
      # Connection Pool Manager
      AutonomousOpponentV2Core.Connections.PoolManager
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end