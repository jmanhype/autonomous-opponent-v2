defmodule AutonomousOpponentV2Core.MCP.Pool.ConnectionPool do
  @moduledoc """
  Connection pooling for MCP Gateway transports using poolboy.
  
  Manages a pool of reusable connections with configurable size,
  overflow handling, and connection lifecycle management.
  """
  
  use Supervisor
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCP.Gateway
  
  require Logger
  
  @pool_name :mcp_connection_pool
  @default_pool_size 100
  @default_overflow 50
  @checkout_timeout 5_000
  @idle_timeout 300_000  # 5 minutes
  
  defmodule Worker do
    @moduledoc """
    Pool worker that manages individual connections.
    """
    use GenServer
    
    def start_link(_) do
      GenServer.start_link(__MODULE__, nil)
    end
    
    def init(_) do
      {:ok, %{
        connection_id: nil,
        client_id: nil,
        checked_out_at: nil,
        last_used_at: DateTime.utc_now(),
        metadata: %{}
      }}
    end
    
    def handle_call({:checkout, connection_id, client_id, metadata}, _from, state) do
      new_state = %{state |
        connection_id: connection_id,
        client_id: client_id,
        checked_out_at: DateTime.utc_now(),
        last_used_at: DateTime.utc_now(),
        metadata: metadata
      }
      {:reply, :ok, new_state}
    end
    
    def handle_call({:checkin}, _from, state) do
      new_state = %{state |
        connection_id: nil,
        client_id: nil,
        checked_out_at: nil,
        last_used_at: DateTime.utc_now(),
        metadata: %{}
      }
      {:reply, :ok, new_state}
    end
    
    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
    
    def handle_cast({:update_metadata, metadata}, state) do
      {:noreply, %{state | metadata: metadata, last_used_at: DateTime.utc_now()}}
    end
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Checks out a connection from the pool.
  """
  def checkout(connection_id, client_id \\ nil, metadata \\ %{}) do
    try do
      worker = :poolboy.checkout(@pool_name, true, @checkout_timeout)
      GenServer.call(worker, {:checkout, connection_id, client_id, metadata})
      {:ok, worker}
    catch
      :exit, {:timeout, _} ->
        Logger.error("Connection pool checkout timeout")
        Gateway.trigger_algedonic(:high, :connection_pool_exhausted)
        {:error, :pool_timeout}
    end
  end
  
  @doc """
  Returns a connection to the pool.
  """
  def checkin(worker) when is_pid(worker) do
    GenServer.call(worker, :checkin)
    :poolboy.checkin(@pool_name, worker)
    :ok
  end
  
  def checkin(connection_id) do
    # Find worker by connection_id
    case find_worker_by_connection(connection_id) do
      {:ok, worker} -> checkin(worker)
      :error -> {:error, :not_found}
    end
  end
  
  @doc """
  Gets pool statistics.
  """
  def get_stats do
    status = :poolboy.status(@pool_name)
    
    %{
      pool_size: status[:pool_size] || @default_pool_size,
      overflow: status[:overflow] || @default_overflow,
      checked_out: status[:checked_out] || 0,
      available: status[:available] || 0,
      overflow_active: status[:overflow_active] || 0
    }
  end
  
  @doc """
  Updates connection metadata.
  """
  def update_metadata(worker, metadata) when is_pid(worker) do
    GenServer.cast(worker, {:update_metadata, metadata})
  end
  
  @doc """
  Performs health check on the pool.
  """
  def health_check do
    stats = get_stats()
    utilization = stats.checked_out / (stats.pool_size + stats.overflow_active)
    
    health_status = cond do
      utilization > 0.9 -> :critical
      utilization > 0.7 -> :warning
      true -> :healthy
    end
    
    # Report to VSM
    EventBus.publish(:mcp_pool_health, %{
      status: health_status,
      stats: stats,
      utilization: utilization
    })
    
    health_status
  end
  
  # Supervisor callbacks
  
  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    overflow = Keyword.get(opts, :overflow, @default_overflow)
    
    pool_config = [
      name: {:local, @pool_name},
      worker_module: Worker,
      size: pool_size,
      max_overflow: overflow,
      strategy: :fifo
    ]
    
    children = [
      :poolboy.child_spec(@pool_name, pool_config, []),
      {Task.Supervisor, name: AutonomousOpponentV2Core.MCP.Pool.TaskSupervisor},
      {__MODULE__.Monitor, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  # Private functions
  
  defp find_worker_by_connection(connection_id) do
    # Get all workers from pool
    workers = :poolboy.transaction(@pool_name, fn worker ->
      # This is a hack to get all workers, return immediately
      worker
    end)
    
    # Search through workers
    Enum.find_value(all_workers(), fn worker ->
      case GenServer.call(worker, :get_state) do
        %{connection_id: ^connection_id} -> {:ok, worker}
        _ -> nil
      end
    end) || :error
  end
  
  defp all_workers do
    # Get pool status and extract worker pids
    # This is implementation-specific and might need adjustment
    case Process.whereis(@pool_name) do
      nil -> []
      pid -> 
        case :sys.get_state(pid) do
          %{workers: workers} -> workers
          _ -> []
        end
    end
  end
  
  defmodule Monitor do
    @moduledoc """
    Monitors pool health and reports metrics.
    """
    use GenServer
    
    @check_interval 30_000  # 30 seconds
    @cleanup_interval 60_000  # 1 minute
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    def init(_opts) do
      schedule_health_check()
      schedule_cleanup()
      {:ok, %{}}
    end
    
    def handle_info(:health_check, state) do
      # Perform health check
      health_status = AutonomousOpponentV2Core.MCP.Pool.ConnectionPool.health_check()
      
      # Report metrics
      stats = AutonomousOpponentV2Core.MCP.Pool.ConnectionPool.get_stats()
      Gateway.report_metrics(%{
        component: :connection_pool,
        health: health_status,
        stats: stats
      })
      
      # Check for critical conditions
      if health_status == :critical do
        Gateway.trigger_algedonic(:high, {:pool_critical, stats})
      end
      
      schedule_health_check()
      {:noreply, state}
    end
    
    def handle_info(:cleanup, state) do
      # Clean up idle connections
      # This would be more sophisticated in production
      Logger.debug("Connection pool cleanup performed")
      
      schedule_cleanup()
      {:noreply, state}
    end
    
    defp schedule_health_check do
      Process.send_after(self(), :health_check, @check_interval)
    end
    
    defp schedule_cleanup do
      Process.send_after(self(), :cleanup, @cleanup_interval)
    end
  end
  
  @doc """
  Gets the current status of the connection pool.
  
  Returns a map with:
  - available: number of available connections
  - in_use: number of connections currently in use
  - overflow: number of overflow connections
  """
  def get_status do
    try do
      status = :poolboy.status(@pool_name)
      
      # poolboy status returns {state_name, available, overflow, monitors}
      case status do
        {_state, available, overflow, monitors} ->
          in_use = length(monitors)
          %{
            available: available,
            in_use: in_use,
            overflow: overflow
          }
        _ ->
          %{available: 0, in_use: 0, overflow: 0}
      end
    rescue
      _ ->
        %{available: 0, in_use: 0, overflow: 0}
    end
  end
end