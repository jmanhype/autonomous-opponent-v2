defmodule AutonomousOpponentV2Core.EventBus.Cluster do
  @moduledoc """
  EventBus Cluster Configuration and Management
  
  This module provides the high-level API for managing the distributed EventBus
  cluster. It handles configuration, topology management, and health monitoring
  for the distributed VSM nervous system.
  
  ## Usage
  
  The cluster is automatically started when the application starts if:
  1. The node is running in distributed mode (Node.alive?() == true)
  2. Clustering is not explicitly disabled in configuration
  
  ## Configuration
  
  Configure in your `config.exs`:
  
      config :autonomous_opponent_core, AutonomousOpponentV2Core.EventBus.Cluster,
        enabled: true,
        topology: [
          strategy: Cluster.Strategy.Gossip,
          config: [
            port: 45892,
            if_addr: "0.0.0.0",
            multicast_addr: "224.1.1.2",
            multicast_ttl: 1
          ]
        ],
        partition_strategy: :static_quorum,
        quorum_size: :majority,
        variety_quotas: %{
          algedonic: :unlimited,
          s5_policy: 50,
          s4_intelligence: 100,
          s3_control: 200,
          s2_coordination: 500,
          s1_operational: 1000,
          general: 100
        }
  
  ## Cybernetic Principles
  
  The cluster implements Beer's VSM principles across nodes:
  - Each node is an autonomous VSM instance
  - Variety channels connect corresponding subsystems
  - Algedonic signals bypass all variety constraints
  - Recursive structure enables fractal scaling
  """
  
  alias AutonomousOpponentV2Core.EventBus.Cluster.{
    ClusterBridge,
    AlgedonicBroadcast,
    VarietyManager,
    PartitionDetector
  }
  
  @doc """
  Get the current cluster topology including all nodes and their states
  """
  def topology do
    if cluster_available?() do
      ClusterBridge.topology()
    else
      %{
        node_id: node(),
        peers: [],
        peer_states: %{},
        partition_status: :single_node,
        variety_pressure: 0.0
      }
    end
  end
  
  @doc """
  Broadcast an algedonic (pain/pleasure) signal to all nodes.
  These signals bypass all variety constraints and achieve zero-latency propagation.
  
  ## Examples
  
      # Emergency pain signal
      Cluster.algedonic_scream(%{
        type: :pain,
        severity: 10,
        source: :memory_exhaustion,
        data: %{available_mb: 50, threshold_mb: 500}
      })
      
      # Pleasure signal for positive feedback
      Cluster.pleasure_signal(%{
        type: :pleasure,
        severity: 8,
        source: :goal_achieved,
        data: %{goal: "process_1m_requests", time_taken: 45_000}
      })
  """
  def algedonic_scream(signal) do
    if cluster_available?() do
      AlgedonicBroadcast.emergency_scream(signal)
    else
      {:error, :cluster_not_available}
    end
  end
  
  def pleasure_signal(signal) do
    if cluster_available?() do
      AlgedonicBroadcast.pleasure_signal(signal)
    else
      {:error, :cluster_not_available}
    end
  end
  
  @doc """
  Get current variety pressure across all channels.
  Returns a value from 0.0 (no pressure) to 1.0 (maximum pressure).
  """
  def variety_pressure do
    if cluster_available?() do
      VarietyManager.pressure()
    else
      0.0
    end
  end
  
  @doc """
  Get detailed variety statistics including flow rates and throttling
  """
  def variety_stats do
    if cluster_available?() do
      VarietyManager.get_stats()
    else
      %{
        quotas: %{},
        current_tokens: %{},
        events_allowed: %{},
        events_throttled: %{},
        events_compressed: %{},
        compression_ratio: 0.0,
        total_variety_reduced: 0,
        current_pressure: 0.0,
        pressure_by_channel: %{}
      }
    end
  end
  
  @doc """
  Check for network partitions (split-brain scenarios)
  """
  def check_partitions do
    if cluster_available?() do
      nodes = [node() | Node.list()]
      PartitionDetector.check(nodes)
    else
      :healthy
    end
  end
  
  @doc """
  Get partition detection status and history
  """
  def partition_status do
    if cluster_available?() do
      PartitionDetector.status()
    else
      %{
        strategy: :none,
        nodes: [node()],
        node_states: %{},
        current_partition: :healthy,
        partition_history: [],
        vsm_health_scores: %{}
      }
    end
  end
  
  @doc """
  Update VSM health score for partition detection.
  Higher scores indicate better health and increase partition weight.
  """
  def update_health_score(node, score) when score >= 0.0 and score <= 1.0 do
    if cluster_available?() do
      PartitionDetector.update_health_score(node, score)
    else
      :ok
    end
  end
  
  @doc """
  Get comprehensive cluster health report
  """
  def health_report do
    %{
      cluster_available: cluster_available?(),
      node: node(),
      distributed: Node.alive?(),
      topology: topology(),
      variety_pressure: variety_pressure(),
      partition_status: partition_status(),
      algedonic_stats: algedonic_stats()
    }
  end
  
  # Private Functions
  
  defp cluster_available? do
    Process.whereis(ClusterBridge) != nil
  end
  
  defp algedonic_stats do
    if cluster_available?() do
      AlgedonicBroadcast.stats()
    else
      %{
        screams_sent: 0,
        screams_received: 0,
        screams_confirmed: 0,
        screams_partial: 0,
        pain_signals_sent: 0,
        pain_signals_received: 0,
        pleasure_signals_sent: 0,
        pleasure_signals_received: 0,
        total_failed_nodes: 0,
        avg_confirmation_time_ms: 0
      }
    end
  end
end