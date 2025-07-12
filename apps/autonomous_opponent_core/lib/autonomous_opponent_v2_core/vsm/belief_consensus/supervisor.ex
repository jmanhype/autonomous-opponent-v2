defmodule AutonomousOpponentV2Core.VSM.BeliefConsensus.Supervisor do
  @moduledoc """
  Supervisor for the CRDT Belief Consensus system.
  
  Manages all belief consensus components:
  - BeliefConsensus workers for each VSM level (S1-S5)
  - ByzantineDetector for fault tolerance
  - DeltaSync for efficient synchronization
  - PatternIntegration for Issue #92 integration
  
  Starts components in dependency order to ensure proper initialization.
  """
  
  use Supervisor
  require Logger
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    # Generate unique node ID for this instance
    node_id = generate_node_id()
    
    children = [
      # Byzantine detector (shared across all levels)
      {AutonomousOpponentV2Core.VSM.BeliefConsensus.ByzantineDetector, []},
      
      # Pattern integration (connects to Issue #92)
      {AutonomousOpponentV2Core.VSM.BeliefConsensus.PatternIntegration, []},
      
      # S5 Policy level (starts first, provides constraints)
      {AutonomousOpponentV2Core.VSM.BeliefConsensus,
       [vsm_level: :s5, node_id: "#{node_id}_s5"]},
      
      # Delta sync for S5
      {AutonomousOpponentV2Core.VSM.BeliefConsensus.DeltaSync,
       [vsm_level: :s5, node_id: "#{node_id}_s5"]},
      
      # S4 Intelligence level
      {AutonomousOpponentV2Core.VSM.BeliefConsensus,
       [vsm_level: :s4, node_id: "#{node_id}_s4"]},
      
      # Delta sync for S4
      {AutonomousOpponentV2Core.VSM.BeliefConsensus.DeltaSync,
       [vsm_level: :s4, node_id: "#{node_id}_s4"]},
      
      # S3 Control level
      {AutonomousOpponentV2Core.VSM.BeliefConsensus,
       [vsm_level: :s3, node_id: "#{node_id}_s3"]},
      
      # Delta sync for S3
      {AutonomousOpponentV2Core.VSM.BeliefConsensus.DeltaSync,
       [vsm_level: :s3, node_id: "#{node_id}_s3"]},
      
      # S2 Coordination level
      {AutonomousOpponentV2Core.VSM.BeliefConsensus,
       [vsm_level: :s2, node_id: "#{node_id}_s2"]},
      
      # Delta sync for S2
      {AutonomousOpponentV2Core.VSM.BeliefConsensus.DeltaSync,
       [vsm_level: :s2, node_id: "#{node_id}_s2"]},
      
      # S1 Operations level
      {AutonomousOpponentV2Core.VSM.BeliefConsensus,
       [vsm_level: :s1, node_id: "#{node_id}_s1"]},
      
      # Delta sync for S1
      {AutonomousOpponentV2Core.VSM.BeliefConsensus.DeltaSync,
       [vsm_level: :s1, node_id: "#{node_id}_s1"]}
    ]
    
    # Use one_for_one strategy - if one belief consensus worker crashes,
    # only restart that specific worker, not the entire system
    opts = [
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    ]
    
    Logger.info("🧠 Starting Belief Consensus Supervisor with node base: #{node_id}")
    
    Supervisor.init(children, opts)
  end
  
  @doc """
  Check health of all belief consensus components.
  """
  def health_check do
    children = Supervisor.which_children(__MODULE__)
    
    status = Enum.map(children, fn {id, pid, type, modules} ->
      alive = if pid == :undefined, do: false, else: Process.alive?(pid)
      
      %{
        id: id,
        type: type,
        modules: modules,
        alive: alive,
        pid: pid
      }
    end)
    
    all_healthy = Enum.all?(status, & &1.alive)
    
    %{
      healthy: all_healthy,
      components: status,
      timestamp: DateTime.utc_now()
    }
  end
  
  @doc """
  Get metrics from all belief consensus levels.
  """
  def get_all_metrics do
    [:s1, :s2, :s3, :s4, :s5]
    |> Enum.map(fn level ->
      metrics = try do
        AutonomousOpponentV2Core.VSM.BeliefConsensus.get_metrics(level)
      rescue
        _ -> %{error: "unavailable"}
      end
      
      {level, metrics}
    end)
    |> Map.new()
  end
  
  @doc """
  Force consensus across all levels (emergency intervention).
  """
  def force_system_consensus(belief_content) do
    [:s5, :s4, :s3, :s2, :s1]  # Top-down enforcement
    |> Enum.each(fn level ->
      try do
        AutonomousOpponentV2Core.VSM.BeliefConsensus.force_consensus(level, [belief_content])
      rescue
        e ->
          Logger.error("Failed to force consensus at #{level}: #{inspect(e)}")
      end
    end)
  end
  
  # Private functions
  
  defp generate_node_id do
    # Generate unique node identifier
    # Format: "node_<hostname>_<timestamp>_<random>"
    hostname = :inet.gethostname() |> elem(1) |> List.to_string()
    timestamp = System.os_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    
    "node_#{hostname}_#{timestamp}_#{random}"
  end
end