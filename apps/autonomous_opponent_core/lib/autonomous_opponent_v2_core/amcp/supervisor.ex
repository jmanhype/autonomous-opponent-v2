defmodule AutonomousOpponentV2Core.AMCP.Supervisor do
  @moduledoc """
  Supervises all AMQP-related processes including connection pool,
  health monitor, and message routers.
  
  **Wisdom Preservation:** Centralized supervision ensures orderly startup,
  shutdown, and restart of AMQP components. The supervision tree provides
  fault isolation and automatic recovery.
  """
  use Supervisor
  require Logger
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    # Check if AMQP is enabled
    amqp_enabled = Application.get_env(:autonomous_opponent_core, :amqp_enabled, false)
    
    children = if amqp_enabled and Code.ensure_loaded?(AMQP) do
      Logger.info("Starting AMQP supervisor with full functionality")
      
      [
        # Connection pool manages multiple AMQP connections
        {AutonomousOpponentV2Core.AMCP.ConnectionPool, [pool_size: 5]},
        
        # Health monitor tracks connection health and publishes metrics
        {AutonomousOpponentV2Core.AMCP.HealthMonitor, []},
        
        # Message abstraction layer
        {AutonomousOpponentV2Core.AMCP.MessageHandler, []},
        
        # VSM topology manager
        {AutonomousOpponentV2Core.AMCP.VSMTopology, []},
        
        # Router handles message routing between EventBus and AMQP
        {AutonomousOpponentV2Core.AMCP.Router, []}
      ]
    else
      Logger.warning("AMQP supervisor starting in stub mode - AMQP disabled or not available")
      
      # Start stub versions that integrate with EventBus only
      [
        {AutonomousOpponentV2Core.AMCP.ConnectionPool, []},
        {AutonomousOpponentV2Core.AMCP.HealthMonitor, []},
        {AutonomousOpponentV2Core.AMCP.MessageHandler, []},
        {AutonomousOpponentV2Core.AMCP.VSMTopology, []},
        {AutonomousOpponentV2Core.AMCP.Router, []}
      ]
    end
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Checks if AMQP is currently available and functioning.
  """
  def amqp_available? do
    Application.get_env(:autonomous_opponent_core, :amqp_enabled, false) and
      Code.ensure_loaded?(AMQP)
  end
end