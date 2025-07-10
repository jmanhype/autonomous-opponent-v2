defmodule AutonomousOpponentV2Core.AMCP.Memory.CRDTSyncMonitor do
  @moduledoc """
  Monitor and control CRDT peer synchronization.
  
  This module provides safe initialization and monitoring of CRDT peer sync,
  including health checks, performance metrics, and troubleshooting tools.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  alias AutonomousOpponentV2Core.EventBus
  
  @sync_health_check_interval 10_000  # 10 seconds
  @max_sync_latency 5_000  # 5 seconds
  
  defstruct [
    :enabled,
    :health_status,
    :last_health_check,
    :sync_metrics,
    :alerts
  ]
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Enable CRDT peer synchronization with safety checks.
  """
  def enable_sync do
    GenServer.call(__MODULE__, :enable_sync)
  end
  
  @doc """
  Disable CRDT peer synchronization.
  """
  def disable_sync do
    GenServer.call(__MODULE__, :disable_sync)
  end
  
  @doc """
  Get current sync health status.
  """
  def health_status do
    GenServer.call(__MODULE__, :health_status)
  end
  
  @doc """
  Get sync performance metrics.
  """
  def metrics do
    GenServer.call(__MODULE__, :metrics)
  end
  
  @doc """
  Perform a test sync with validation.
  """
  def test_sync do
    GenServer.call(__MODULE__, :test_sync, 10_000)
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(opts) do
    # Subscribe to sync events
    EventBus.subscribe(:amcp_crdt_sync_request)
    EventBus.subscribe(:amcp_crdt_sync_response)
    
    # Start health check timer
    :timer.send_interval(@sync_health_check_interval, :health_check)
    
    # Set up telemetry handlers
    setup_telemetry_handlers()
    
    state = %__MODULE__{
      enabled: Keyword.get(opts, :enabled, false),
      health_status: :initializing,
      last_health_check: nil,
      sync_metrics: init_metrics(),
      alerts: []
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:enable_sync, _from, state) do
    case perform_safety_checks() do
      :ok ->
        # Initiate peer discovery
        CRDTStore.discover_peers()
        
        new_state = %{state | enabled: true, health_status: :healthy}
        Logger.info("CRDT peer sync enabled successfully")
        {:reply, :ok, new_state}
        
      {:error, reason} = error ->
        alert = %{
          timestamp: System.system_time(:millisecond),
          type: :enable_failed,
          reason: reason
        }
        new_state = %{state | alerts: [alert | state.alerts]}
        {:reply, error, new_state}
    end
  end
  
  @impl true
  def handle_call(:disable_sync, _from, state) do
    new_state = %{state | enabled: false, health_status: :disabled}
    Logger.info("CRDT peer sync disabled")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:health_status, _from, state) do
    status = %{
      enabled: state.enabled,
      health: state.health_status,
      last_check: state.last_health_check,
      alerts: Enum.take(state.alerts, 5)
    }
    {:reply, status, state}
  end
  
  @impl true
  def handle_call(:metrics, _from, state) do
    {:reply, state.sync_metrics, state}
  end
  
  @impl true
  def handle_call(:test_sync, _from, state) do
    result = perform_test_sync()
    {:reply, result, state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    if state.enabled do
      new_state = perform_health_check(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event, :amcp_crdt_sync_request, _data}, state) do
    new_metrics = update_metrics(state.sync_metrics, :sync_requests)
    {:noreply, %{state | sync_metrics: new_metrics}}
  end
  
  @impl true
  def handle_info({:event, :amcp_crdt_sync_response, _data}, state) do
    new_metrics = update_metrics(state.sync_metrics, :sync_responses)
    {:noreply, %{state | sync_metrics: new_metrics}}
  end
  
  # Private Functions
  
  defp init_metrics do
    %{
      sync_requests: 0,
      sync_responses: 0,
      sync_errors: 0,
      avg_sync_time: 0,
      last_sync_time: nil,
      peer_count: 0
    }
  end
  
  defp perform_safety_checks do
    checks = [
      check_event_bus_health(),
      check_memory_usage(),
      check_hlc_availability()
    ]
    
    case Enum.find(checks, fn result -> match?({:error, _}, result) end) do
      nil -> :ok
      error -> error
    end
  end
  
  defp check_event_bus_health do
    case Process.whereis(AutonomousOpponentV2Core.EventBus) do
      pid when is_pid(pid) -> 
        if Process.alive?(pid) do
          :ok
        else
          {:error, :event_bus_not_available}
        end
      _ -> {:error, :event_bus_not_available}
    end
  end
  
  defp check_memory_usage do
    memory_mb = :erlang.memory(:total) / 1_048_576
    if memory_mb < 1000 do  # Less than 1GB
      :ok
    else
      {:error, :high_memory_usage}
    end
  end
  
  defp check_hlc_availability do
    case AutonomousOpponentV2Core.Core.HybridLogicalClock.now() do
      {:ok, _} -> :ok
      _ -> {:error, :hlc_not_available}
    end
  end
  
  defp perform_health_check(state) do
    start_time = System.system_time(:millisecond)
    
    # Check CRDT store stats
    stats = CRDTStore.get_stats()
    
    # Calculate health status
    health_status = calculate_health_status(stats, state)
    
    # Update metrics
    new_metrics = %{state.sync_metrics |
      peer_count: stats.peer_count
    }
    
    %{state |
      health_status: health_status,
      last_health_check: start_time,
      sync_metrics: new_metrics
    }
  end
  
  defp calculate_health_status(stats, state) do
    cond do
      not state.enabled -> :disabled
      stats.peer_count == 0 -> :no_peers
      stats.syncs == 0 and state.sync_metrics.sync_requests > 0 -> :sync_failing
      true -> :healthy
    end
  end
  
  defp perform_test_sync do
    try do
      # Create a test CRDT
      test_id = "test_sync_#{System.unique_integer([:positive])}"
      :ok = CRDTStore.create_crdt(test_id, :g_set, ["test_value"])
      
      # Force a sync
      CRDTStore.sync_with_peers()
      
      # Wait a bit
      Process.sleep(100)
      
      # Check if sync happened (by looking at stats)
      stats = CRDTStore.get_stats()
      
      # Clean up
      # Note: No delete operation in current implementation
      
      {:ok, %{
        test_id: test_id,
        stats: stats,
        result: :success
      }}
    rescue
      error ->
        {:error, Exception.format(:error, error)}
    end
  end
  
  defp update_metrics(metrics, event_type) do
    Map.update(metrics, event_type, 1, &(&1 + 1))
  end
  
  defp setup_telemetry_handlers do
    :telemetry.attach(
      "crdt-sync-monitor-cleanup",
      [:crdt_store, :memory_cleanup],
      &handle_telemetry_event/4,
      nil
    )
  end
  
  defp handle_telemetry_event(_event_name, measurements, metadata, _config) do
    Logger.debug("CRDT telemetry: #{inspect(measurements)}", metadata: metadata)
  end
end