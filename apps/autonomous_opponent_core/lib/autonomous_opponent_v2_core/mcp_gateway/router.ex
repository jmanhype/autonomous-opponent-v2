defmodule AutonomousOpponentV2Core.MCPGateway.Router do
  @moduledoc """
  Gateway router with consistent hashing for load balancing.
  
  Routes MCP Gateway requests to appropriate handlers using:
  - Consistent hashing for sticky sessions
  - Load balancing across backend services
  - Circuit breaking for failing routes
  - Dynamic route registration
  
  ## Wisdom Preservation
  
  ### Why Consistent Hashing?
  Traditional round-robin loses session affinity. Consistent hashing
  ensures that the same client always routes to the same backend,
  preserving WebSocket connections and SSE streams while distributing
  load evenly.
  
  ### Hash Ring Design
  We use a virtual node approach where each backend has multiple
  positions on the hash ring. This improves distribution and handles
  node addition/removal gracefully with minimal reshuffling.
  """
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Core.{CircuitBreaker, Metrics}
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCPGateway.ConnectionPool
  
  # Route entry
  defmodule Route do
    defstruct [
      :id,
      :pattern,
      :handler,
      :transport_types,
      :metadata,
      :health_status,
      :circuit_breaker_name,
      stats: %{requests: 0, failures: 0}
    ]
  end
  
  # Client API
  
  def start_link(opts) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Register a route pattern with a handler
  """
  def register_route(name \\ __MODULE__, pattern, handler, opts \\ []) do
    GenServer.call(name, {:register_route, pattern, handler, opts})
  end
  
  @doc """
  Route a request to the appropriate handler
  """
  def route(name \\ __MODULE__, request) do
    GenServer.call(name, {:route, request})
  end
  
  @doc """
  Get router status
  """
  def status(name \\ __MODULE__) do
    GenServer.call(name, :status)
  end
  
  @doc """
  Update backend nodes for consistent hashing
  """
  def update_backends(name \\ __MODULE__, backends) do
    GenServer.call(name, {:update_backends, backends})
  end
  
  # Server implementation
  
  defstruct [
    :hash_ring_size,
    :virtual_nodes_per_backend,
    routes: %{},
    hash_ring: nil,
    backends: [],
    stats: %{}
  ]
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      hash_ring_size: opts[:hash_ring_size] || 1024,
      virtual_nodes_per_backend: opts[:virtual_nodes_per_backend] || 150,
      routes: %{},
      hash_ring: :hash_ring.new(opts[:hash_ring_size] || 1024),
      backends: [],
      stats: init_stats()
    }
    
    # Register default routes
    state = register_default_routes(state)
    
    EventBus.publish(:mcp_router_started, %{
      hash_ring_size: state.hash_ring_size
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register_route, pattern, handler, opts}, _from, state) do
    route_id = generate_route_id()
    
    # Create circuit breaker for this route
    circuit_breaker_name = :"circuit_breaker_route_#{route_id}"
    CircuitBreaker.start_link(
      name: circuit_breaker_name,
      threshold: opts[:failure_threshold] || 5,
      timeout: opts[:timeout] || 30_000
    )
    
    route = %Route{
      id: route_id,
      pattern: pattern,
      handler: handler,
      transport_types: opts[:transport_types] || [:http_sse, :websocket],
      metadata: opts[:metadata] || %{},
      health_status: :healthy,
      circuit_breaker_name: circuit_breaker_name
    }
    
    routes = Map.put(state.routes, route_id, route)
    state = %{state | routes: routes}
    
    Logger.info("Registered route: #{pattern} -> #{inspect(handler)}")
    
    EventBus.publish(:mcp_route_registered, %{
      route_id: route_id,
      pattern: pattern,
      handler: handler
    })
    
    {:reply, {:ok, route_id}, state}
  end
  
  def handle_call({:route, request}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Extract routing key from request
    routing_key = extract_routing_key(request)
    
    # Find matching route
    case find_matching_route(request, state) do
      {:ok, route} ->
        # Check circuit breaker
        case CircuitBreaker.call(route.circuit_breaker_name, fn ->
          route_to_backend(request, route, routing_key, state)
        end) do
          {:ok, response} ->
            # Update stats
            duration = System.monotonic_time(:millisecond) - start_time
            state = update_route_stats(route.id, :success, state)
            
            Metrics.histogram(:mcp_gateway_metrics, "router.request_duration", duration, %{
              route: route.pattern,
              status: "success"
            })
            
            {:reply, {:ok, response}, state}
            
          {:error, :circuit_breaker_open} ->
            state = update_route_stats(route.id, :circuit_breaker, state)
            
            EventBus.publish(:mcp_route_circuit_open, %{
              route_id: route.id,
              pattern: route.pattern
            })
            
            {:reply, {:error, :service_unavailable}, state}
            
          {:error, reason} = error ->
            state = update_route_stats(route.id, :failure, state)
            
            Logger.error("Route failed: #{inspect(reason)}")
            {:reply, error, state}
        end
        
      {:error, :no_matching_route} ->
        state = update_global_stats(:no_route, state)
        {:reply, {:error, :not_found}, state}
    end
  end
  
  def handle_call(:status, _from, state) do
    status = %{
      total_routes: map_size(state.routes),
      active_routes: count_healthy_routes(state),
      backends: length(state.backends),
      hash_ring_load: calculate_hash_ring_load(state),
      stats: state.stats,
      routes: format_route_status(state)
    }
    
    {:reply, status, state}
  end
  
  def handle_call({:update_backends, backends}, _from, state) do
    # Update consistent hash ring with new backends
    new_ring = rebuild_hash_ring(backends, state)
    
    old_count = length(state.backends)
    new_count = length(backends)
    
    Logger.info("Updated backends: #{old_count} -> #{new_count}")
    
    EventBus.publish(:mcp_backends_updated, %{
      old_backends: state.backends,
      new_backends: backends,
      reshuffled_percentage: calculate_reshuffle_percentage(state.backends, backends)
    })
    
    {:reply, :ok, %{state | backends: backends, hash_ring: new_ring}}
  end
  
  # Private functions
  
  defp init_stats do
    %{
      total_requests: 0,
      successful_routes: 0,
      failed_routes: 0,
      no_route_found: 0,
      circuit_breaker_trips: 0
    }
  end
  
  defp register_default_routes(state) do
    # Register built-in routes
    default_routes = [
      {"/api/v1/*", AutonomousOpponentV2Core.MCPGateway.Handlers.APIHandler, []},
      {"/events/*", AutonomousOpponentV2Core.MCPGateway.Handlers.EventHandler, [
        transport_types: [:http_sse, :websocket]
      ]},
      {"/health", AutonomousOpponentV2Core.MCPGateway.Handlers.HealthHandler, []}
    ]
    
    Enum.reduce(default_routes, state, fn {pattern, handler, opts}, acc ->
      {:reply, _, new_state} = 
        handle_call({:register_route, pattern, handler, opts}, self(), acc)
      new_state
    end)
  end
  
  defp extract_routing_key(request) do
    # Extract key for consistent hashing
    # Could be user ID, session ID, or IP address
    cond do
      request[:user_id] -> "user:#{request.user_id}"
      request[:session_id] -> "session:#{request.session_id}"
      request[:remote_ip] -> "ip:#{request.remote_ip}"
      true -> "default:#{:rand.uniform(1000)}"
    end
  end
  
  defp find_matching_route(request, state) do
    # Find first route that matches the request pattern
    matching_route = 
      state.routes
      |> Map.values()
      |> Enum.find(fn route ->
        matches_pattern?(request.path, route.pattern) and
        route.health_status == :healthy and
        request.transport_type in route.transport_types
      end)
    
    case matching_route do
      nil -> {:error, :no_matching_route}
      route -> {:ok, route}
    end
  end
  
  defp matches_pattern?(path, pattern) do
    # Simple pattern matching - in production would use more sophisticated matching
    cond do
      pattern == path -> true
      String.ends_with?(pattern, "*") ->
        prefix = String.trim_trailing(pattern, "*")
        String.starts_with?(path, prefix)
      true -> false
    end
  end
  
  defp route_to_backend(request, route, routing_key, state) do
    # Use consistent hashing to select backend
    case select_backend(routing_key, state) do
      {:ok, backend} ->
        # Route through connection pool
        ConnectionPool.with_connection(request.transport_type, fn conn ->
          # Call the route handler with the connection and backend
          apply(route.handler, :handle_request, [request, conn, backend])
        end)
        
      {:error, :no_backends} ->
        {:error, :no_backends_available}
    end
  end
  
  defp select_backend(_routing_key, %{backends: []}) do
    {:error, :no_backends}
  end
  
  defp select_backend(routing_key, state) do
    # Use consistent hash to find backend
    hash = :erlang.phash2(routing_key, state.hash_ring_size)
    backend_index = :hash_ring.find_node(state.hash_ring, hash)
    
    # Map ring position to actual backend
    backend = Enum.at(state.backends, rem(backend_index, length(state.backends)))
    {:ok, backend}
  end
  
  defp rebuild_hash_ring(backends, state) do
    # Create new hash ring with virtual nodes
    ring = :hash_ring.new(state.hash_ring_size)
    
    # Add each backend multiple times (virtual nodes)
    Enum.with_index(backends)
    |> Enum.each(fn {backend, index} ->
      Enum.each(1..state.virtual_nodes_per_backend, fn vnode ->
        # Create unique key for each virtual node
        key = "#{backend}:vnode:#{vnode}"
        position = :erlang.phash2(key, state.hash_ring_size)
        :hash_ring.add_node(ring, position, index)
      end)
    end)
    
    ring
  end
  
  defp calculate_reshuffle_percentage(old_backends, new_backends) do
    # Calculate what percentage of keys would move to different backends
    # This is a simplified calculation
    if old_backends == new_backends do
      0.0
    else
      # Estimate based on backend changes
      removed = length(old_backends -- new_backends)
      added = length(new_backends -- old_backends)
      total_change = removed + added
      max_backends = max(length(old_backends), length(new_backends))
      
      if max_backends > 0 do
        (total_change / max_backends) * 100
      else
        0.0
      end
    end
  end
  
  defp update_route_stats(route_id, result, state) do
    route = Map.get(state.routes, route_id)
    
    updated_stats = case result do
      :success ->
        %{route.stats | requests: route.stats.requests + 1}
        
      :failure ->
        %{route.stats | 
          requests: route.stats.requests + 1,
          failures: route.stats.failures + 1
        }
        
      :circuit_breaker ->
        route.stats
    end
    
    updated_route = %{route | stats: updated_stats}
    routes = Map.put(state.routes, route_id, updated_route)
    
    # Update global stats
    global_stats = case result do
      :success -> Map.update(state.stats, :successful_routes, 1, &(&1 + 1))
      :failure -> Map.update(state.stats, :failed_routes, 1, &(&1 + 1))
      :circuit_breaker -> Map.update(state.stats, :circuit_breaker_trips, 1, &(&1 + 1))
    end
    
    %{state | routes: routes, stats: global_stats}
  end
  
  defp update_global_stats(stat, state) do
    stats = Map.update(state.stats, stat, 1, &(&1 + 1))
    %{state | stats: stats}
  end
  
  defp count_healthy_routes(state) do
    state.routes
    |> Map.values()
    |> Enum.count(fn route -> route.health_status == :healthy end)
  end
  
  defp calculate_hash_ring_load(state) do
    # Calculate load distribution across hash ring
    if length(state.backends) > 0 do
      # Simplified - would calculate actual distribution in production
      100.0 / length(state.backends)
    else
      0.0
    end
  end
  
  defp format_route_status(state) do
    state.routes
    |> Map.values()
    |> Enum.map(fn route ->
      %{
        pattern: route.pattern,
        handler: route.handler,
        health: route.health_status,
        stats: route.stats
      }
    end)
  end
  
  defp generate_route_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end
end