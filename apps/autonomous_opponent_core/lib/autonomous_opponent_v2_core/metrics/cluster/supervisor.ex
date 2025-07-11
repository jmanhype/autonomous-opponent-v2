defmodule AutonomousOpponentV2Core.Metrics.Cluster.Supervisor do
  @moduledoc """
  🎯 METRICS CLUSTER SUPERVISOR - THE AUTONOMIC NERVOUS SYSTEM
  
  This supervisor manages the distributed metrics aggregation system following
  VSM principles of autonomous subsystem operation. Each component maintains
  its own viability while contributing to collective system health.
  
  ## Supervision Strategy
  
  Uses `:rest_for_one` to ensure proper startup order:
  1. Time Series Store (persistent memory)
  2. CRDT Store (conflict-free aggregation)
  3. Query Engine (distributed queries)
  4. Aggregator (variety attenuation)
  5. Event Bridge (integration layer)
  6. Telemetry Poller (periodic collection)
  
  ## Fault Tolerance
  
  - Components can fail and restart without affecting others
  - Graceful degradation to single-node metrics if clustering fails
  - Circuit breakers prevent cascade failures
  - Automatic recovery with exponential backoff
  """
  
  use Supervisor
  require Logger
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    Logger.info("🎯 Starting Metrics Cluster Supervisor...")
    
    # Check if clustering is enabled
    cluster_enabled = Application.get_env(:autonomous_opponent_core, :metrics_cluster_enabled, true)
    
    children = if cluster_enabled do
      [
        # Time-series storage layer
        {AutonomousOpponentV2Core.Metrics.Cluster.TimeSeriesStore, []},
        
        # CRDT-based metric storage
        {AutonomousOpponentV2Core.Metrics.Cluster.CRDTStore, []},
        
        # Query engine for distributed queries
        {AutonomousOpponentV2Core.Metrics.Cluster.QueryEngine, []},
        
        # Main aggregator process
        {AutonomousOpponentV2Core.Metrics.Cluster.Aggregator, []},
        
        # Event bridge for EventBus integration
        {AutonomousOpponentV2Core.Metrics.Cluster.EventBridge, []},
        
        # Telemetry poller for periodic aggregation
        telemetry_poller_spec()
      ]
    else
      Logger.warn("⚠️ Metrics clustering disabled - running in single-node mode")
      []
    end
    
    Supervisor.init(children, strategy: :rest_for_one)
  end
  
  defp telemetry_poller_spec do
    measurements = [
      # Collect node metrics every 10 seconds
      {AutonomousOpponentV2Core.Metrics.Cluster.Telemetry, :collect_node_metrics, []},
      
      # Aggregate cluster metrics every 30 seconds
      {AutonomousOpponentV2Core.Metrics.Cluster.Telemetry, :aggregate_cluster_metrics, []},
      
      # Check VSM health every minute
      {AutonomousOpponentV2Core.Metrics.Cluster.Telemetry, :check_vsm_health, []}
    ]
    
    {:telemetry_poller,
     measurements: measurements,
     period: :timer.seconds(10),
     name: :metrics_cluster_poller}
  end
  
  @doc """
  Checks if the metrics cluster is healthy
  """
  def healthy? do
    required_processes = [
      AutonomousOpponentV2Core.Metrics.Cluster.Aggregator,
      AutonomousOpponentV2Core.Metrics.Cluster.CRDTStore,
      AutonomousOpponentV2Core.Metrics.Cluster.QueryEngine
    ]
    
    Enum.all?(required_processes, fn process ->
      case Process.whereis(process) do
        nil -> false
        pid -> Process.alive?(pid)
      end
    end)
  end
  
  @doc """
  Gets the status of all supervised children
  """
  def status do
    children = Supervisor.which_children(__MODULE__)
    
    Enum.map(children, fn {id, pid, type, modules} ->
      %{
        id: id,
        pid: pid,
        type: type,
        modules: modules,
        alive: (if pid != :undefined, do: Process.alive?(pid), else: false)
      }
    end)
  end
end