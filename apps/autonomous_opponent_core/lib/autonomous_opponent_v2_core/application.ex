defmodule AutonomousOpponentV2Core.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Initialize telemetry handlers first
    AutonomousOpponentV2Core.Telemetry.SystemTelemetry.setup()
    
    # Ensure AMQP application is started before we check for it
    ensure_amqp_started()
    
    repo_children = if Application.get_env(:autonomous_opponent_core, :start_repo, true) do
      [AutonomousOpponentV2Core.Repo]
    else
      []
    end
    
    children = repo_children ++ [
      # Start the Hybrid Logical Clock for deterministic timestamps
      {AutonomousOpponentV2Core.Core.HybridLogicalClock, []},
      # Start the OrderedDelivery supervisor before EventBus
      AutonomousOpponentV2Core.EventBus.OrderedDeliverySupervisor,
      # Start the EventBus
      {AutonomousOpponentV2Core.EventBus, name: AutonomousOpponentV2Core.EventBus},
      # CircuitBreaker is initialized on-demand
      {AutonomousOpponentV2Core.Core.RateLimiter, name: AutonomousOpponentV2Core.Core.RateLimiter},
      # Start the Metrics system for comprehensive monitoring
      {AutonomousOpponentV2Core.Core.Metrics, name: AutonomousOpponentV2Core.Core.Metrics},
      # Start the Connection Pool Manager for external services
      AutonomousOpponentV2Core.Connections.PoolManager,
      # Start Security services (Task 7)
      AutonomousOpponentV2Core.Security.Supervisor,
      # Start Web Gateway (Task 8)
      AutonomousOpponentV2Core.WebGateway.Gateway,
    ] ++ ai_children() ++ amqp_children() ++ vsm_children() ++ mcp_children()

    opts = [strategy: :one_for_one, name: AutonomousOpponentV2Core.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Start AI services (gradually re-enabling to test stability)
  defp ai_children do
    [
      # CRDT Memory Store
      AutonomousOpponentV2Core.AMCP.Memory.CRDTStore,
      # CRDT Sync Monitor for safe peer synchronization
      AutonomousOpponentV2Core.AMCP.Memory.CRDTSyncMonitor,
      # LLM Response Cache (must start before LLMBridge)
      AutonomousOpponentV2Core.AMCP.Bridges.LLMCache,
      # LLM Bridge for multi-provider AI integration - RE-ENABLED
      AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge,
      # Semantic Analyzer for event analysis - RE-ENABLED
      AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer,
      # Semantic Fusion for pattern detection - RE-ENABLED
      AutonomousOpponentV2Core.AMCP.Events.SemanticFusion,
      # Consciousness module for AI self-awareness
      AutonomousOpponentV2Core.Consciousness,
      # Pattern HNSW Bridge - connects pattern matching to vector indexing
      AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge,
      # Goldrush Event Processor for pattern matching
      AutonomousOpponentV2Core.AMCP.Goldrush.EventProcessor
    ]
  end

  # Start VSM in all environments including test
  defp vsm_children do
    if Application.get_env(:autonomous_opponent_core, :start_vsm, true) do
      [AutonomousOpponentV2Core.VSM.Supervisor]
    else
      []
    end
  end
  
  # Start MCP (Model Context Protocol) services - TEMPORARILY DISABLED
  defp mcp_children do
    # if Application.get_env(:autonomous_opponent_core, :start_mcp, true) do
    #   [AutonomousOpponentV2Core.MCP.Supervisor]
    # else
      []
    # end
  end

  # Start AMQP services if enabled - TEMPORARILY DISABLED
  defp amqp_children do
    # if amqp_enabled?() do
    #   [
    #     # AMQP Supervisor manages all AMCP components
    #     AutonomousOpponentV2Core.AMCP.Supervisor
    #   ]
    # else
      []
    # end
  end
  
  defp ensure_amqp_started do
    if amqp_enabled?() do
      case Application.ensure_all_started(:amqp) do
        {:ok, _apps} ->
          :ok
        {:error, reason} ->
          Logger.warning("Failed to start AMQP application: #{inspect(reason)}")
      end
    end
  end
  
  defp amqp_enabled? do
    case Application.get_env(:autonomous_opponent_core, :amqp_enabled) do
      nil -> System.get_env("AMQP_ENABLED", "true") == "true"
      false -> false
      true -> true
      value when is_binary(value) -> value == "true"
      _ -> true
    end
  end
end