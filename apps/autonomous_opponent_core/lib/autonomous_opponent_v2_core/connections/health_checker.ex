defmodule AutonomousOpponentV2Core.Connections.HealthChecker do
  @moduledoc """
  Periodic health checker for connection pools.
  
  Monitors pool health and publishes metrics to telemetry.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Connections.PoolManager
  alias AutonomousOpponentV2Core.EventBus
  
  @check_interval 30_000 # 30 seconds
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    pools = Keyword.get(opts, :pools, [])
    
    # Schedule first check
    Process.send_after(self(), :check_health, 5_000)
    
    {:ok, %{pools: pools, status: %{}}}
  end
  
  @impl true
  def handle_info(:check_health, state) do
    new_status = check_all_pools(state.pools)
    
    # Compare with previous status and emit events for changes
    detect_status_changes(state.status, new_status)
    
    # Schedule next check
    Process.send_after(self(), :check_health, @check_interval)
    
    {:noreply, %{state | status: new_status}}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end
  
  # Private functions
  
  defp check_all_pools(pools) do
    pools
    |> Enum.map(fn {name, _config} ->
      Task.async(fn ->
        {name, check_pool(name)}
      end)
    end)
    |> Task.await_many(10_000)
    |> Map.new()
  end
  
  defp check_pool(name) do
    start_time = System.monotonic_time(:millisecond)
    
    result = case PoolManager.health_check(name) do
      :ok ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:healthy, duration}
        
      {:error, reason} ->
        {:unhealthy, reason}
    end
    
    # Record telemetry
    :telemetry.execute(
      [:pool_manager, :health_check],
      %{duration: elem(result, 1)},
      %{pool: name, status: elem(result, 0)}
    )
    
    result
  end
  
  defp detect_status_changes(old_status, new_status) do
    Enum.each(new_status, fn {pool, status} ->
      old_pool_status = Map.get(old_status, pool)
      
      case {old_pool_status, status} do
        {nil, _} ->
          # First check, don't emit change event
          :ok
          
        {{:healthy, _}, {:unhealthy, reason}} ->
          Logger.warning("Pool #{pool} became unhealthy: #{inspect(reason)}")
          EventBus.publish(:pool_unhealthy, %{
            pool: pool,
            reason: reason,
            timestamp: DateTime.utc_now()
          })
          
        {{:unhealthy, _}, {:healthy, _}} ->
          Logger.info("Pool #{pool} recovered and is now healthy")
          EventBus.publish(:pool_recovered, %{
            pool: pool,
            timestamp: DateTime.utc_now()
          })
          
        _ ->
          # No status change
          :ok
      end
    end)
  end
  
  # Public API
  
  @doc """
  Gets the current health status of all pools.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end
end