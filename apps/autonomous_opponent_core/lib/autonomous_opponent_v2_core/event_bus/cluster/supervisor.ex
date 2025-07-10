defmodule AutonomousOpponentV2Core.EventBus.Cluster.Supervisor do
  @moduledoc """
  Supervisor for EventBus Cluster Components
  
  This supervisor manages the lifecycle of all distributed EventBus components,
  ensuring proper startup order and fault tolerance. It follows OTP principles
  to create a robust distributed nervous system for the VSM.
  
  ## Supervision Tree
  
  ```
  ClusterSupervisor
  ├── PartitionDetector     (detects split-brain scenarios)
  ├── VarietyManager        (manages channel capacity)
  ├── AlgedonicBroadcast    (zero-latency pain signals)
  └── ClusterBridge         (main event replication)
  ```
  
  ## Restart Strategy
  
  Uses `:rest_for_one` strategy because:
  - PartitionDetector must be running before ClusterBridge
  - VarietyManager must be available for ClusterBridge
  - AlgedonicBroadcast can run independently
  """
  
  use Supervisor
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus.Cluster.{
    ClusterBridge,
    AlgedonicBroadcast,
    VarietyManager,
    PartitionDetector
  }
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    # Check if clustering is enabled
    if enabled?(opts) do
      Logger.info("VSM Cluster: Initializing distributed EventBus")
      
      children = [
        # Partition detection must start first
        {PartitionDetector, partition_detector_opts(opts)},
        
        # Variety management for channel capacity
        {VarietyManager, variety_manager_opts(opts)},
        
        # Algedonic bypass channel
        {AlgedonicBroadcast, algedonic_opts(opts)},
        
        # Main cluster bridge (depends on above)
        {ClusterBridge, cluster_bridge_opts(opts)}
      ]
      
      # Use rest_for_one - if ClusterBridge crashes, don't restart earlier processes
      Supervisor.init(children, strategy: :rest_for_one)
    else
      Logger.info("VSM Cluster: Clustering disabled, running in single-node mode")
      Supervisor.init([], strategy: :one_for_one)
    end
  end
  
  # Configuration Helpers
  
  defp enabled?(opts) do
    Keyword.get(opts, :enabled, true) and Node.alive?()
  end
  
  defp partition_detector_opts(opts) do
    [
      strategy: Keyword.get(opts, :partition_strategy, :static_quorum),
      quorum_size: Keyword.get(opts, :quorum_size, :majority),
      detection_interval: Keyword.get(opts, :partition_check_interval, 5_000),
      vsm_weight_factors: Keyword.get(opts, :vsm_weight_factors, %{
        s5_policy: 5.0,
        s4_intelligence: 4.0,
        s3_control: 3.0,
        s2_coordination: 2.0,
        s1_operational: 1.0,
        algedonic_health: 10.0
      })
    ]
  end
  
  defp variety_manager_opts(opts) do
    [
      quotas: Keyword.get(opts, :variety_quotas, %{
        algedonic: :unlimited,
        s5_policy: 50,
        s4_intelligence: 100,
        s3_control: 200,
        s2_coordination: 500,
        s1_operational: 1000,
        general: 100
      }),
      compression: Keyword.get(opts, :semantic_compression, %{
        enabled: true,
        similarity_threshold: 0.8,
        aggregation_window: 100
      }),
      algedonic_bypass: true
    ]
  end
  
  defp algedonic_opts(_opts) do
    # Algedonic broadcast has minimal configuration
    # It's designed to work with defaults for maximum reliability
    []
  end
  
  defp cluster_bridge_opts(opts) do
    [
      variety_quotas: Keyword.get(opts, :variety_quotas),
      semantic_compression: Keyword.get(opts, :semantic_compression),
      circuit_breaker: Keyword.get(opts, :circuit_breaker, %{
        failure_threshold: 5,
        recovery_time: 30_000,
        half_open_calls: 3
      }),
      quorum_size: Keyword.get(opts, :quorum_size, :majority),
      partition_strategy: Keyword.get(opts, :partition_strategy, :static_quorum),
      event_ttl: Keyword.get(opts, :event_ttl, 300_000),
      max_hops: Keyword.get(opts, :max_hops, 3)
    ]
  end
end