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
    # Check if AMQP is available using the same logic as everywhere else
    if amqp_available?() do
      Logger.info("Starting AMQP supervisor with full functionality")
    else
      Logger.warning("AMQP supervisor starting in stub mode - AMQP disabled or not available")
    end
    
    # Always start the same children - they handle stub mode internally
    children = [
      # Connection pool manages multiple AMQP connections
      {AutonomousOpponentV2Core.AMCP.ConnectionPool, [pool_size: 5]},
      
      # Health monitor tracks connection health and publishes metrics
      {AutonomousOpponentV2Core.AMCP.HealthMonitor, []},
      
      # Message abstraction layer
      {AutonomousOpponentV2Core.AMCP.MessageHandler, []},
      
      # VSM topology manager
      {AutonomousOpponentV2Core.AMCP.VSMTopology, []},
      
      # Router handles message routing between EventBus and AMQP
      {AutonomousOpponentV2Core.AMCP.Router, []},
      
      # VSM Consumer for handling incoming messages from queues
      {AutonomousOpponentV2Core.AMCP.VSMConsumer, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Checks if AMQP is currently available and functioning.
  """
  def amqp_available? do
    # Check if AMQP is enabled in config or environment
    amqp_enabled = case Application.get_env(:autonomous_opponent_core, :amqp_enabled) do
      nil -> System.get_env("AMQP_ENABLED", "true") == "true"
      false -> false
      true -> true
      value when is_binary(value) -> value == "true"
      _ -> true
    end
    
    # Also check if the AMQP module is available
    amqp_loaded = Code.ensure_loaded?(AMQP) and 
      Code.ensure_loaded?(AMQP.Connection) and
      (function_exported?(AMQP.Connection, :open, 1) or 
       function_exported?(AMQP.Connection, :open, 2))
    
    amqp_enabled and amqp_loaded
  end
end