defmodule AutonomousOpponentV2Core.WebGateway.Transport.Router do
  @moduledoc """
  Routes messages between different Web Gateway transport layers and handles
  automatic failover between transports.
  
  Implements intelligent routing based on message characteristics,
  client preferences, and transport availability.
  """
  
  use GenServer
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.WebGateway.Gateway
  alias AutonomousOpponentV2Core.WebGateway.Transport.{HTTPSSE, WebSocket}
  alias AutonomousOpponentV2Core.WebGateway.LoadBalancer.ConsistentHash
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  alias AutonomousOpponentV2Core.WebGateway.Tracing
  
  require Logger
  
  @failover_threshold 3  # Number of failures before failover
  @health_check_interval 10_000  # 10 seconds
  
  defmodule Route do
    @moduledoc """
    Represents a routing decision for a client.
    """
    defstruct [
      :client_id,
      :primary_transport,
      :fallback_transport,
      :preferences,
      :failure_count,
      :last_failure,
      :circuit_state
    ]
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Routes a message to the appropriate transport for a client.
  """
  def route_message(client_id, message, opts \\ []) do
    GenServer.call(__MODULE__, {:route, client_id, message, opts})
  end
  
  @doc """
  Registers client transport preferences.
  """
  def set_client_preferences(client_id, preferences) do
    GenServer.cast(__MODULE__, {:set_preferences, client_id, preferences})
  end
  
  @doc """
  Gets the current route for a client.
  """
  def get_route(client_id) do
    GenServer.call(__MODULE__, {:get_route, client_id})
  end
  
  @doc """
  Reports a transport failure for a client.
  """
  def report_failure(client_id, transport, reason) do
    GenServer.cast(__MODULE__, {:report_failure, client_id, transport, reason})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Start health check timer
    Process.send_after(self(), :health_check, @health_check_interval)
    
    # Subscribe to transport events
    EventBus.subscribe(:transport_status)
    EventBus.subscribe(:mcp_routing_events)
    
    # Circuit breakers will be initialized on-demand when first called
    
    state = %{
      routes: %{},
      transport_health: %{
        http_sse: :healthy,
        websocket: :healthy
      },
      stats: %{
        messages_routed: 0,
        failovers: 0,
        routing_errors: 0
      },
      message_history: [],  # List of {timestamp, message_id} tuples
      transport_stats: %{
        websocket: %{successes: 0, failures: 0},
        http_sse: %{successes: 0, failures: 0}
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:route, client_id, message, opts}, _from, state) do
    # Get or create route for client
    route = get_or_create_route(client_id, state)
    
    # Determine transport based on route and message characteristics
    transport = select_transport(route, message, opts, state)
    
    # Trace the routing operation
    result = Tracing.trace_routing(client_id, message, :auto, fn ->
      # Add tracing attribute for selected transport
      if transport, do: Tracing.add_attributes(%{selected_transport: transport})
      
      # Route the message
      case transport do
        :http_sse ->
          route_to_sse(client_id, message, opts)
          
        :websocket ->
          route_to_websocket(client_id, message, opts)
          
        :both ->
          # For broadcast scenarios
          route_to_sse(client_id, message, opts)
          route_to_websocket(client_id, message, opts)
          
        nil ->
          {:error, :no_available_transport}
      end
    end)
    
    # Track message in history
    now = System.monotonic_time(:second)
    message_id = :erlang.unique_integer([:positive])
    new_history = [{now, message_id} | state.message_history]
                  |> Enum.take(1000)  # Keep last 1000 messages
    
    # Update transport stats and general stats
    {new_stats, new_transport_stats} = case {result, transport} do
      {{:error, _}, nil} ->
        {Map.update(state.stats, :routing_errors, 1, &(&1 + 1)), state.transport_stats}
        
      {{:error, _}, transport} when transport in [:http_sse, :websocket] ->
        ts = update_in(state.transport_stats[transport].failures, &(&1 + 1))
        {Map.update(state.stats, :routing_errors, 1, &(&1 + 1)), ts}
        
      {_, transport} when transport in [:http_sse, :websocket] ->
        ts = update_in(state.transport_stats[transport].successes, &(&1 + 1))
        {Map.update(state.stats, :messages_routed, 1, &(&1 + 1)), ts}
        
      {_, :both} ->
        ts = state.transport_stats
             |> update_in([:http_sse, :successes], &(&1 + 1))
             |> update_in([:websocket, :successes], &(&1 + 1))
        {Map.update(state.stats, :messages_routed, 2, &(&1 + 2)), ts}
        
      _ ->
        {Map.update(state.stats, :messages_routed, 1, &(&1 + 1)), state.transport_stats}
    end
    
    new_state = %{state | 
      stats: new_stats,
      message_history: new_history,
      transport_stats: new_transport_stats
    }
    report_routing_metrics(new_state)
    
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:get_route, client_id}, _from, state) do
    route = Map.get(state.routes, client_id)
    {:reply, route, state}
  end

  @impl true
  def handle_call(:get_throughput, _from, state) do
    # Calculate messages per second based on recent activity
    now = System.monotonic_time(:second)
    window_start = now - 60  # 60 second window
    
    # Count messages in the last 60 seconds
    recent_messages = 
      state.message_history
      |> Enum.filter(fn {timestamp, _} -> timestamp > window_start end)
      |> length()
    
    throughput = recent_messages / 60.0
    {:reply, throughput, state}
  end

  @impl true
  def handle_call({:get_error_rate, transport}, _from, state) do
    # Calculate error rate for the transport
    transport_stats = Map.get(state.transport_stats, transport, %{
      successes: 0,
      failures: 0
    })
    
    total = transport_stats.successes + transport_stats.failures
    error_rate = if total > 0 do
      (transport_stats.failures / total) * 100
    else
      0.0
    end
    
    {:reply, {:ok, error_rate}, state}
  end
  
  @impl true
  def handle_cast({:set_preferences, client_id, preferences}, state) do
    routes = Map.update(
      state.routes,
      client_id,
      create_default_route(client_id, preferences),
      fn route -> %{route | preferences: preferences} end
    )
    
    {:noreply, %{state | routes: routes}}
  end
  
  @impl true
  def handle_cast({:report_failure, client_id, transport, reason}, state) do
    Logger.warning("Transport failure for client #{client_id} on #{transport}: #{inspect(reason)}")
    
    routes = Map.update(
      state.routes,
      client_id,
      create_default_route(client_id, %{}),
      fn route ->
        if route.primary_transport == transport do
          handle_transport_failure(route, reason, state)
        else
          route
        end
      end
    )
    
    # Update circuit breaker
    circuit_key = :"#{transport}_transport"
    CircuitBreaker.init(circuit_key)
    CircuitBreaker.record_failure(circuit_key)
    
    # Check if we need to trigger failover
    route = Map.get(routes, client_id)
    new_state = if route.failure_count >= @failover_threshold do
      perform_failover(client_id, route, state)
    else
      %{state | routes: routes}
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Check transport health
    sse_health = check_transport_health(:http_sse)
    ws_health = check_transport_health(:websocket)
    
    transport_health = %{
      http_sse: sse_health,
      websocket: ws_health
    }
    
    # Report critical failures to VSM
    if sse_health == :unhealthy && ws_health == :unhealthy do
      Gateway.trigger_algedonic(:critical, :all_transports_down)
    end
    
    # Schedule next health check
    Process.send_after(self(), :health_check, @health_check_interval)
    
    {:noreply, %{state | transport_health: transport_health}}
  end
  
  @impl true
  def handle_info({:event_bus, :transport_status, %{transport: transport, status: status}}, state) do
    transport_health = Map.put(state.transport_health, transport, status)
    {:noreply, %{state | transport_health: transport_health}}
  end
  
  # Private functions
  
  defp get_or_create_route(client_id, state) do
    Map.get_lazy(state.routes, client_id, fn ->
      create_default_route(client_id, %{})
    end)
  end
  
  defp create_default_route(client_id, preferences) do
    # Use consistent hashing to determine primary transport
    primary = ConsistentHash.get_node(client_id, [:http_sse, :websocket])
    fallback = if primary == :http_sse, do: :websocket, else: :http_sse
    
    %Route{
      client_id: client_id,
      primary_transport: primary,
      fallback_transport: fallback,
      preferences: preferences,
      failure_count: 0,
      circuit_state: :closed
    }
  end
  
  defp select_transport(route, message, _opts, state) do
    # Check message size for transport selection
    message_size = estimate_message_size(message)
    prefer_websocket = message_size > 10_000  # Prefer WebSocket for large messages
    
    # Check client preferences
    preferred = case route.preferences do
      %{transport: transport} -> transport
      _ -> nil
    end
    
    # Check transport health and circuit state
    primary_healthy = state.transport_health[route.primary_transport] == :healthy
    fallback_healthy = state.transport_health[route.fallback_transport] == :healthy
    
    cond do
      # Use preferred transport if specified and healthy
      preferred && state.transport_health[preferred] == :healthy ->
        preferred
        
      # Circuit is open, use fallback
      route.circuit_state == :open && fallback_healthy ->
        route.fallback_transport
        
      # Primary is healthy and suitable
      primary_healthy && (!prefer_websocket || route.primary_transport == :websocket) ->
        route.primary_transport
        
      # Need WebSocket but primary is SSE, check if WebSocket is healthy
      prefer_websocket && route.primary_transport == :http_sse && state.transport_health[:websocket] == :healthy ->
        :websocket
        
      # Fallback to any healthy transport
      fallback_healthy ->
        route.fallback_transport
        
      primary_healthy ->
        route.primary_transport
        
      # No healthy transports
      true ->
        nil
    end
  end
  
  defp route_to_sse(client_id, message, opts) do
    event_type = Keyword.get(opts, :event_type, "message")
    
    # Initialize circuit breaker on-demand if not exists
    CircuitBreaker.init(:http_sse_transport)
    
    CircuitBreaker.call(:http_sse_transport, fn ->
      HTTPSSE.send_event(client_id, event_type, message)
      :ok
    end)
  end
  
  defp route_to_websocket(client_id, message, opts) do
    # Initialize circuit breaker on-demand if not exists
    CircuitBreaker.init(:websocket_transport)
    
    CircuitBreaker.call(:websocket_transport, fn ->
      WebSocket.send_message(client_id, message, opts)
      :ok
    end)
  end
  
  defp handle_transport_failure(route, _reason, _state) do
    %{route |
      failure_count: route.failure_count + 1,
      last_failure: DateTime.utc_now()
    }
  end
  
  defp perform_failover(client_id, route, state) do
    Logger.info("Performing failover for client #{client_id} from #{route.primary_transport} to #{route.fallback_transport}")
    
    # Swap primary and fallback
    new_route = %{route |
      primary_transport: route.fallback_transport,
      fallback_transport: route.primary_transport,
      failure_count: 0,
      circuit_state: :open
    }
    
    # Schedule circuit reset
    Process.send_after(self(), {:reset_circuit, client_id}, 60_000)  # 1 minute
    
    routes = Map.put(state.routes, client_id, new_route)
    stats = Map.update(state.stats, :failovers, 1, &(&1 + 1))
    
    # Notify VSM of failover
    EventBus.publish(:mcp_failover, %{
      client_id: client_id,
      from: route.primary_transport,
      to: route.fallback_transport
    })
    
    %{state | routes: routes, stats: stats}
  end
  
  defp check_transport_health(transport) do
    circuit_name = :"#{transport}_transport"
    # Initialize circuit breaker on-demand if not exists
    CircuitBreaker.init(circuit_name)
    
    case CircuitBreaker.get_state(circuit_name) do
      %{state: :open} -> :unhealthy
      %{state: :half_open} -> :degraded
      %{state: :closed} -> :healthy
      _ -> :healthy  # Default to healthy if unknown
    end
  end
  
  defp estimate_message_size(message) when is_binary(message), do: byte_size(message)
  defp estimate_message_size(message), do: message |> Jason.encode!() |> byte_size()
  
  defp report_routing_metrics(state) do
    metrics = %{
      component: :transport_router,
      total_routes: map_size(state.routes),
      messages_routed: state.stats.messages_routed,
      failovers: state.stats.failovers,
      routing_errors: state.stats.routing_errors,
      transport_health: state.transport_health
    }
    
    Gateway.report_metrics(metrics)
  end
  
  @doc """
  Gets the current message throughput (messages per second).
  """
  def get_throughput do
    GenServer.call(__MODULE__, :get_throughput)
  end
  
  @doc """
  Gets the error rate for a specific transport.
  """
  def get_error_rate(transport) do
    GenServer.call(__MODULE__, {:get_error_rate, transport})
  end
  
end