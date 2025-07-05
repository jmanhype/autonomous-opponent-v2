defmodule AutonomousOpponentV2Core.WebGateway.Transport.RouterTest do
  @moduledoc """
  Tests for the Web Gateway transport router with intelligent routing and failover.
  """
  
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.WebGateway.Transport.Router
  alias AutonomousOpponentV2Core.WebGateway.Transport.{HTTPSSE, WebSocket}
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Subscribe to relevant events
    EventBus.subscribe(:mcp_failover)
    EventBus.subscribe(:vsm_s4_metrics)
    
    # Ensure router is started
    case Process.whereis(Router) do
      nil -> {:ok, _pid} = Router.start_link()
      _pid -> :ok
    end
    
    # Ensure transports are started
    unless Process.whereis(HTTPSSE), do: HTTPSSE.start_link()
    unless Process.whereis(WebSocket), do: WebSocket.start_link()
    
    # Reset circuit breakers if they exist
    if Process.whereis(AutonomousOpponentV2Core.Core.CircuitBreaker) do
      CircuitBreaker.reset(:http_sse_transport)
      CircuitBreaker.reset(:websocket_transport)
    end
    
    :ok
  end
  
  describe "message routing" do
    test "routes message to available transport" do
      client_id = "router_client_#{:rand.uniform(1000)}"
      
      # Register connections on both transports
      {:ok, _} = HTTPSSE.register_connection(self(), client_id)
      {:ok, _} = WebSocket.register_connection(self(), client_id)
      
      # Route a message
      assert Router.route_message(client_id, %{test: "data"}) == :ok
      
      # Should receive on one of the transports
      assert_receive msg when elem(msg, 0) in [:sse_event, :ws_send], 1000
    end
    
    test "routes based on message size preference" do
      client_id = "size_client_#{:rand.uniform(1000)}"
      
      # Set up both transports
      {:ok, _} = HTTPSSE.register_connection(self(), client_id)
      {:ok, _} = WebSocket.register_connection(self(), client_id)
      
      # Small message - can go to either
      Router.route_message(client_id, %{small: "data"})
      
      # Large message - should prefer WebSocket
      large_data = String.duplicate("x", 15_000)
      Router.route_message(client_id, %{large: large_data})
      
      # Should receive WebSocket message for large data
      assert_receive {:ws_send, _}, 1000
    end
    
    test "respects client transport preferences" do
      client_id = "pref_client_#{:rand.uniform(1000)}"
      
      # Set preference for SSE
      Router.set_client_preferences(client_id, %{transport: :http_sse})
      
      # Register both transports
      {:ok, _} = HTTPSSE.register_connection(self(), client_id)
      {:ok, _} = WebSocket.register_connection(self(), client_id)
      
      # Route message
      Router.route_message(client_id, %{test: "data"})
      
      # Should go to SSE
      assert_receive {:sse_event, _}, 1000
    end
    
    test "handles routing to non-existent client" do
      assert {:error, :no_available_transport} = 
        Router.route_message("non_existent", %{test: "data"})
    end
  end
  
  describe "client preferences" do
    test "stores and retrieves client preferences" do
      client_id = "pref_store_#{:rand.uniform(1000)}"
      prefs = %{transport: :websocket, compression: true}
      
      Router.set_client_preferences(client_id, prefs)
      
      route = Router.get_route(client_id)
      assert route.preferences == prefs
    end
    
    test "creates default route for new client" do
      client_id = "new_client_#{:rand.uniform(1000)}"
      
      route = Router.get_route(client_id)
      assert route.client_id == client_id
      assert route.primary_transport in [:http_sse, :websocket]
      assert route.fallback_transport in [:http_sse, :websocket]
      assert route.primary_transport != route.fallback_transport
    end
  end
  
  describe "failure handling and failover" do
    test "tracks transport failures" do
      client_id = "fail_client_#{:rand.uniform(1000)}"
      
      # Get initial route
      route = Router.get_route(client_id)
      initial_primary = route.primary_transport
      
      # Report failures
      Router.report_failure(client_id, initial_primary, :connection_error)
      Router.report_failure(client_id, initial_primary, :timeout)
      
      # Check failure count increased
      route = Router.get_route(client_id)
      assert route.failure_count == 2
    end
    
    test "performs failover after threshold failures" do
      client_id = "failover_client_#{:rand.uniform(1000)}"
      
      # Get initial route
      route = Router.get_route(client_id)
      initial_primary = route.primary_transport
      initial_fallback = route.fallback_transport
      
      # Report failures up to threshold
      for _ <- 1..3 do
        Router.report_failure(client_id, initial_primary, :repeated_failure)
      end
      
      # Should receive failover event
      assert_receive {:event_bus, :mcp_failover, event}
      assert event.client_id == client_id
      assert event.from == initial_primary
      assert event.to == initial_fallback
      
      # Check route was swapped
      route = Router.get_route(client_id)
      assert route.primary_transport == initial_fallback
      assert route.fallback_transport == initial_primary
      assert route.failure_count == 0
      assert route.circuit_state == :open
    end
    
    test "updates circuit breaker on failures" do
      client_id = "circuit_client_#{:rand.uniform(1000)}"
      transport = :http_sse
      
      # Report multiple failures
      for _ <- 1..5 do
        Router.report_failure(client_id, transport, :circuit_test)
      end
      
      # Circuit breaker should record failures
      state = CircuitBreaker.get_state(:http_sse_transport)
      assert state in [:open, :half_open]
    end
  end
  
  describe "health monitoring" do
    test "monitors transport health status" do
      # Publish transport status update
      EventBus.publish(:transport_status, %{
        transport: :websocket,
        status: :degraded
      })
      
      :timer.sleep(50)
      
      # Check health was updated
      state = :sys.get_state(Router)
      assert state.transport_health.websocket == :degraded
    end
    
    test "routes around unhealthy transports" do
      client_id = "health_client_#{:rand.uniform(1000)}"
      
      # Mark WebSocket as unhealthy
      EventBus.publish(:transport_status, %{
        transport: :websocket,
        status: :unhealthy
      })
      
      :timer.sleep(50)
      
      # Set client preference for WebSocket
      Router.set_client_preferences(client_id, %{transport: :websocket})
      
      # Register only SSE (WebSocket is unhealthy)
      {:ok, _} = HTTPSSE.register_connection(self(), client_id)
      
      # Route message - should go to SSE despite preference
      Router.route_message(client_id, %{test: "data"})
      
      assert_receive {:sse_event, _}, 1000
    end
  end
  
  describe "metrics reporting" do
    test "reports routing metrics to VSM" do
      # Route some messages
      client_id = "metrics_client_#{:rand.uniform(1000)}"
      Router.route_message(client_id, %{test: "data"})
      
      # Trigger health check to force metrics report
      send(Router, :health_check)
      
      assert_receive {:event_bus, :vsm_s4_metrics, metrics}
      assert metrics.source == :web_gateway
      assert metrics.metrics.component == :transport_router
      assert is_integer(metrics.metrics.messages_routed)
      assert is_map(metrics.metrics.transport_health)
    end
  end
  
  describe "circuit breaker integration" do
    test "respects open circuit breaker" do
      client_id = "open_circuit_#{:rand.uniform(1000)}"
      
      # Force circuit breaker open
      for _ <- 1..10 do
        CircuitBreaker.record_failure(:http_sse_transport)
      end
      
      # Set route to use SSE
      Router.set_client_preferences(client_id, %{transport: :http_sse})
      
      # Register both transports
      {:ok, _} = HTTPSSE.register_connection(self(), client_id)
      {:ok, _} = WebSocket.register_connection(self(), client_id)
      
      # Get route - should avoid open circuit
      route = Router.get_route(client_id)
      
      # Route message - should use fallback
      Router.route_message(client_id, %{test: "data"})
      
      # Should receive on WebSocket (fallback)
      assert_receive {:ws_send, _}, 1000
    end
  end
end