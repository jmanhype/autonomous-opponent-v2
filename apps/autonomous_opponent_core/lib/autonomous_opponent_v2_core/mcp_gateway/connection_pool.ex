defmodule AutonomousOpponentV2Core.MCPGateway.ConnectionPool do
  @moduledoc """
  Connection pool for MCP Gateway connections.
  
  Manages a pool of connections for different transport types with:
  - Configurable pool sizes
  - Connection health checking
  - Automatic reconnection
  - Backpressure management
  
  ## Wisdom Preservation
  
  ### Why Connection Pooling?
  Creating connections is expensive. HTTP handshakes, WebSocket upgrades,
  TLS negotiations - all take time. A pool amortizes this cost across
  many requests, turning connection creation from O(n) to O(1).
  
  ### Pool Design
  1. **Per-Transport Pools**: Each transport type gets its own pool.
     HTTP connections differ from WebSocket connections in lifecycle.
  
  2. **Lazy Loading**: Connections are created on-demand, not eagerly.
     This prevents resource waste during low-traffic periods.
  
  3. **Health Checking**: Connections are periodically validated.
     Dead connections are pruned, keeping the pool healthy.
  
  4. **Backpressure**: When the pool is exhausted, we apply backpressure
     rather than creating unlimited connections. This prevents resource
     exhaustion under load.
  """
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Core.{Metrics, RateLimiter}
  alias AutonomousOpponentV2Core.EventBus
  
  # Connection state
  defmodule Connection do
    defstruct [
      :id,
      :transport_type,
      :pid,
      :ref,
      :created_at,
      :last_used_at,
      :use_count,
      :health_status,
      :metadata
    ]
  end
  
  # Client API
  
  def start_link(opts) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Checkout a connection from the pool
  """
  def checkout(name \\ __MODULE__, transport_type, timeout \\ 5000) do
    GenServer.call(name, {:checkout, transport_type}, timeout)
  end
  
  @doc """
  Return a connection to the pool
  """
  def checkin(name \\ __MODULE__, connection) do
    GenServer.cast(name, {:checkin, connection})
  end
  
  @doc """
  Execute a function with a pooled connection
  """
  def with_connection(name \\ __MODULE__, transport_type, fun) do
    case checkout(name, transport_type) do
      {:ok, conn} ->
        try do
          result = fun.(conn)
          checkin(name, conn)
          {:ok, result}
        rescue
          e ->
            # Mark connection as unhealthy
            GenServer.cast(name, {:mark_unhealthy, conn})
            {:error, e}
        end
        
      error ->
        error
    end
  end
  
  @doc """
  Get pool status
  """
  def status(name \\ __MODULE__) do
    GenServer.call(name, :status)
  end
  
  # Server implementation
  
  defstruct [
    :pool_size,
    :max_overflow,
    :idle_timeout,
    :health_check_interval,
    pools: %{},
    connections: %{},
    waiting: [],
    stats: %{}
  ]
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      pool_size: opts[:pool_size] || 50,
      max_overflow: opts[:max_overflow] || 10,
      idle_timeout: opts[:idle_timeout] || 60_000,
      health_check_interval: opts[:health_check_interval] || 30_000,
      pools: %{},
      connections: %{},
      waiting: [],
      stats: init_stats()
    }
    
    # Start health check timer
    Process.send_after(self(), :health_check, state.health_check_interval)
    
    # Start idle cleanup timer
    Process.send_after(self(), :cleanup_idle, state.idle_timeout)
    
    EventBus.publish(:mcp_connection_pool_started, %{
      pool_size: state.pool_size,
      max_overflow: state.max_overflow
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:checkout, transport_type}, from, state) do
    # Check rate limit
    case RateLimiter.consume(:mcp_gateway_limiter) do
      {:ok, _} ->
        checkout_connection(transport_type, from, state)
        
      {:error, :rate_limited} ->
        update_stats(state, :rate_limited)
        {:reply, {:error, :rate_limited}, state}
    end
  end
  
  def handle_call(:status, _from, state) do
    status = %{
      pools: pool_status(state),
      total_connections: map_size(state.connections),
      waiting_queue_size: length(state.waiting),
      stats: state.stats
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_cast({:checkin, connection}, state) do
    state = return_connection(connection, state)
    {:noreply, state}
  end
  
  def handle_cast({:mark_unhealthy, connection}, state) do
    state = mark_connection_unhealthy(connection, state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    state = perform_health_checks(state)
    Process.send_after(self(), :health_check, state.health_check_interval)
    {:noreply, state}
  end
  
  def handle_info(:cleanup_idle, state) do
    state = cleanup_idle_connections(state)
    Process.send_after(self(), :cleanup_idle, state.idle_timeout)
    {:noreply, state}
  end
  
  def handle_info({:connection_ready, transport_type, conn}, state) do
    # Handle async connection creation
    state = add_connection(transport_type, conn, state)
    state = process_waiting_queue(state)
    {:noreply, state}
  end
  
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Handle connection process death
    state = handle_connection_down(ref, state)
    {:noreply, state}
  end
  
  # Private functions
  
  defp init_stats do
    %{
      checkouts: 0,
      checkins: 0,
      creates: 0,
      destroys: 0,
      health_checks: 0,
      rate_limited: 0,
      timeouts: 0,
      errors: 0
    }
  end
  
  defp checkout_connection(transport_type, from, state) do
    pool = get_or_create_pool(transport_type, state)
    
    case find_available_connection(pool, state) do
      {:ok, conn} ->
        # Update connection state
        conn = %{conn | last_used_at: System.monotonic_time(:millisecond)}
        state = update_connection(conn, state)
        state = update_stats(state, :checkouts)
        
        # Record metrics
        Metrics.counter(:mcp_gateway_metrics, "connection_pool.checkout", 1, %{
          transport: transport_type
        })
        
        {:reply, {:ok, conn}, state}
        
      :none_available ->
        if can_create_connection?(pool, state) do
          # Create new connection asynchronously
          spawn_connection_creation(transport_type, state)
          state = add_to_waiting_queue(from, transport_type, state)
          {:noreply, state}
        else
          # Pool exhausted, apply backpressure
          state = update_stats(state, :timeouts)
          
          EventBus.publish(:mcp_connection_pool_exhausted, %{
            transport: transport_type,
            pool_size: pool.size,
            max_size: state.pool_size + state.max_overflow
          })
          
          {:reply, {:error, :pool_exhausted}, state}
        end
    end
  end
  
  defp get_or_create_pool(transport_type, state) do
    case Map.get(state.pools, transport_type) do
      nil ->
        pool = %{
          transport: transport_type,
          size: 0,
          available: [],
          in_use: [],
          created_at: System.monotonic_time(:millisecond)
        }
        
        Map.put(state.pools, transport_type, pool)
        pool
        
      pool ->
        pool
    end
  end
  
  defp find_available_connection(pool, state) do
    case pool.available do
      [] ->
        :none_available
        
      [conn_id | rest] ->
        case Map.get(state.connections, conn_id) do
          nil ->
            # Connection disappeared, try next
            pool = %{pool | available: rest}
            find_available_connection(pool, state)
            
          conn ->
            # Move from available to in_use
            pool = %{pool | available: rest, in_use: [conn_id | pool.in_use]}
            {:ok, conn}
        end
    end
  end
  
  defp can_create_connection?(pool, state) do
    pool.size < state.pool_size + state.max_overflow
  end
  
  defp spawn_connection_creation(transport_type, state) do
    parent = self()
    
    Task.start(fn ->
      # Create connection based on transport type
      case create_connection(transport_type) do
        {:ok, conn_pid} ->
          ref = Process.monitor(conn_pid)
          
          conn = %Connection{
            id: generate_connection_id(),
            transport_type: transport_type,
            pid: conn_pid,
            ref: ref,
            created_at: System.monotonic_time(:millisecond),
            last_used_at: System.monotonic_time(:millisecond),
            use_count: 0,
            health_status: :healthy,
            metadata: %{}
          }
          
          send(parent, {:connection_ready, transport_type, conn})
          
        {:error, reason} ->
          Logger.error("Failed to create #{transport_type} connection: #{inspect(reason)}")
      end
    end)
  end
  
  defp create_connection(:http_sse) do
    # Stub - would create actual HTTP+SSE connection
    {:ok, spawn(fn -> Process.sleep(:infinity) end)}
  end
  
  defp create_connection(:websocket) do
    # Stub - would create actual WebSocket connection
    {:ok, spawn(fn -> Process.sleep(:infinity) end)}
  end
  
  defp create_connection(_), do: {:error, :unknown_transport}
  
  defp generate_connection_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
  
  defp add_connection(transport_type, conn, state) do
    # Add to connections map
    connections = Map.put(state.connections, conn.id, conn)
    
    # Update pool
    pool = Map.get(state.pools, transport_type)
    pool = %{
      pool |
      size: pool.size + 1,
      available: [conn.id | pool.available]
    }
    
    pools = Map.put(state.pools, transport_type, pool)
    
    state = %{state | connections: connections, pools: pools}
    update_stats(state, :creates)
  end
  
  defp update_connection(conn, state) do
    connections = Map.put(state.connections, conn.id, conn)
    %{state | connections: connections}
  end
  
  defp return_connection(conn, state) do
    # Update connection stats
    conn = %{
      conn |
      use_count: conn.use_count + 1,
      last_used_at: System.monotonic_time(:millisecond)
    }
    
    # Move from in_use to available
    pool = Map.get(state.pools, conn.transport_type)
    pool = %{
      pool |
      in_use: List.delete(pool.in_use, conn.id),
      available: [conn.id | pool.available]
    }
    
    pools = Map.put(state.pools, conn.transport_type, pool)
    connections = Map.put(state.connections, conn.id, conn)
    
    state = %{state | pools: pools, connections: connections}
    update_stats(state, :checkins)
  end
  
  defp mark_connection_unhealthy(conn, state) do
    conn = %{conn | health_status: :unhealthy}
    
    # Remove from pool entirely
    pool = Map.get(state.pools, conn.transport_type)
    pool = %{
      pool |
      size: pool.size - 1,
      in_use: List.delete(pool.in_use, conn.id),
      available: List.delete(pool.available, conn.id)
    }
    
    # Stop monitoring and kill connection
    Process.demonitor(conn.ref, [:flush])
    Process.exit(conn.pid, :unhealthy)
    
    pools = Map.put(state.pools, conn.transport_type, pool)
    connections = Map.delete(state.connections, conn.id)
    
    state = %{state | pools: pools, connections: connections}
    update_stats(state, :destroys)
  end
  
  defp add_to_waiting_queue(from, transport_type, state) do
    waiting = state.waiting ++ [{from, transport_type, System.monotonic_time(:millisecond)}]
    %{state | waiting: waiting}
  end
  
  defp process_waiting_queue(state) do
    case state.waiting do
      [] ->
        state
        
      [{from, transport_type, _timestamp} | rest] ->
        # Try to fulfill waiting request
        pool = Map.get(state.pools, transport_type)
        
        case find_available_connection(pool, state) do
          {:ok, conn} ->
            GenServer.reply(from, {:ok, conn})
            process_waiting_queue(%{state | waiting: rest})
            
          :none_available ->
            state
        end
    end
  end
  
  defp perform_health_checks(state) do
    # Check health of all connections
    connections = 
      state.connections
      |> Enum.map(fn {id, conn} ->
        if connection_healthy?(conn) do
          {id, conn}
        else
          mark_connection_unhealthy(conn, state)
          nil
        end
      end)
      |> Enum.filter(& &1)
      |> Map.new()
    
    state = %{state | connections: connections}
    update_stats(state, :health_checks)
  end
  
  defp connection_healthy?(conn) do
    # Simple health check - process is alive
    Process.alive?(conn.pid)
  end
  
  defp cleanup_idle_connections(state) do
    now = System.monotonic_time(:millisecond)
    idle_threshold = now - state.idle_timeout
    
    # Find idle connections
    idle_connections = 
      state.connections
      |> Enum.filter(fn {_id, conn} ->
        conn.last_used_at < idle_threshold
      end)
    
    # Remove idle connections
    Enum.reduce(idle_connections, state, fn {_id, conn}, acc ->
      mark_connection_unhealthy(conn, acc)
    end)
  end
  
  defp handle_connection_down(ref, state) do
    # Find connection by ref
    case Enum.find(state.connections, fn {_id, conn} -> conn.ref == ref end) do
      {_id, conn} ->
        mark_connection_unhealthy(conn, state)
        
      nil ->
        state
    end
  end
  
  defp pool_status(state) do
    state.pools
    |> Enum.map(fn {transport, pool} ->
      {transport, %{
        size: pool.size,
        available: length(pool.available),
        in_use: length(pool.in_use)
      }}
    end)
    |> Map.new()
  end
  
  defp update_stats(state, stat) do
    stats = Map.update(state.stats, stat, 1, &(&1 + 1))
    %{state | stats: stats}
  end
end