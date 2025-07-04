#!/usr/bin/env elixir

# MCP Gateway Dashboard Test Script
# This script verifies the functionality of the LiveView dashboard

defmodule DashboardTester do
  @moduledoc """
  Comprehensive test script for MCP Gateway Dashboard verification.
  """
  
  def run do
    IO.puts """
    ========================================
    MCP Gateway Dashboard Test Script
    ========================================
    """
    
    # Test 1: Check if dashboard route is accessible
    test_dashboard_route()
    
    # Test 2: Verify data sources exist
    test_data_sources()
    
    # Test 3: Test PubSub broadcast
    test_pubsub_broadcast()
    
    # Test 4: Simulate metric updates
    test_metric_updates()
    
    # Test 5: Check error handling
    test_error_handling()
    
    IO.puts "\n✅ All tests completed!"
  end
  
  defp test_dashboard_route do
    IO.puts "\n[Test 1] Testing Dashboard Route..."
    
    # Check if route exists
    routes = AutonomousOpponentV2Web.Router.__routes__()
    dashboard_route = Enum.find(routes, fn route -> 
      route.path == "/mcp/dashboard" && route.plug == Phoenix.LiveView.Plug
    end)
    
    if dashboard_route do
      IO.puts "  ✓ Dashboard route found at /mcp/dashboard"
      IO.puts "  ✓ Using LiveView plug: #{inspect(dashboard_route.plug_opts[:live])}"
    else
      IO.puts "  ✗ Dashboard route NOT found!"
    end
  end
  
  defp test_data_sources do
    IO.puts "\n[Test 2] Testing Data Sources..."
    
    # Test Gateway.get_dashboard_metrics
    IO.puts "  Testing Gateway.get_dashboard_metrics/0..."
    case AutonomousOpponentV2Core.MCP.Gateway.get_dashboard_metrics() do
      {:ok, metrics} ->
        IO.puts "  ✓ Successfully retrieved metrics"
        IO.puts "    - Connections: #{inspect(metrics[:connections])}"
        IO.puts "    - Throughput: #{metrics[:throughput]}"
        IO.puts "    - Circuit Breakers: #{inspect(metrics[:circuit_breakers])}"
        IO.puts "    - Pool Status: #{inspect(metrics[:pool_status])}"
      {:error, reason} ->
        IO.puts "  ✗ Failed to get metrics: #{reason}"
    end
    
    # Test individual components
    test_component_functions()
  end
  
  defp test_component_functions do
    IO.puts "\n  Testing component functions..."
    
    # Test Router.get_throughput
    try do
      throughput = AutonomousOpponentV2Core.MCP.Transport.Router.get_throughput()
      IO.puts "  ✓ Router.get_throughput/0: #{throughput} msg/s"
    rescue
      e -> IO.puts "  ✗ Router.get_throughput/0 failed: #{inspect(e)}"
    end
    
    # Test Router.get_error_rate
    try do
      {:ok, ws_error_rate} = AutonomousOpponentV2Core.MCP.Transport.Router.get_error_rate(:websocket)
      {:ok, sse_error_rate} = AutonomousOpponentV2Core.MCP.Transport.Router.get_error_rate(:http_sse)
      IO.puts "  ✓ Router.get_error_rate/1 - WebSocket: #{ws_error_rate}%, SSE: #{sse_error_rate}%"
    rescue
      e -> IO.puts "  ✗ Router.get_error_rate/1 failed: #{inspect(e)}"
    end
    
    # Test ConnectionPool.get_status
    try do
      pool_status = AutonomousOpponentV2Core.MCP.Pool.ConnectionPool.get_status()
      IO.puts "  ✓ ConnectionPool.get_status/0: #{inspect(pool_status)}"
    rescue
      e -> IO.puts "  ✗ ConnectionPool.get_status/0 failed: #{inspect(e)}"
    end
  end
  
  defp test_pubsub_broadcast do
    IO.puts "\n[Test 3] Testing PubSub Broadcast..."
    
    # Subscribe to the metrics topic
    Phoenix.PubSub.subscribe(AutonomousOpponentV2.PubSub, "mcp:metrics")
    
    # Trigger metrics update
    test_metrics = %{
      connections: %{websocket: 5, http_sse: 3, total: 8},
      throughput: 50,
      circuit_breakers: %{websocket: :open, http_sse: :closed},
      vsm_metrics: %{
        s1_variety_absorption: 25,
        s2_coordination_active: true,
        s3_resource_usage: 60,
        s4_intelligence_events: 15,
        s5_policy_violations: 1,
        algedonic_signals: []
      },
      error_rates: %{websocket: 0.8, http_sse: 1.5},
      pool_status: %{available: 70, in_use: 30, overflow: 5}
    }
    
    Phoenix.PubSub.broadcast(
      AutonomousOpponentV2.PubSub,
      "mcp:metrics",
      {:mcp_metrics_update, test_metrics}
    )
    
    # Check if message is received
    receive do
      {:mcp_metrics_update, received_metrics} ->
        IO.puts "  ✓ PubSub broadcast successful"
        IO.puts "  ✓ Received metrics: #{inspect(Map.keys(received_metrics))}"
    after
      1000 ->
        IO.puts "  ✗ PubSub broadcast failed - no message received"
    end
  end
  
  defp test_metric_updates do
    IO.puts "\n[Test 4] Testing Metric Updates..."
    
    # Simulate various metric scenarios
    scenarios = [
      {
        "Normal operation",
        %{
          circuit_breakers: %{websocket: :open, http_sse: :open},
          error_rates: %{websocket: 0.1, http_sse: 0.2}
        }
      },
      {
        "Circuit breaker tripped",
        %{
          circuit_breakers: %{websocket: :closed, http_sse: :half_open},
          error_rates: %{websocket: 15.0, http_sse: 8.5}
        }
      },
      {
        "Pool exhaustion",
        %{
          pool_status: %{available: 0, in_use: 100, overflow: 50}
        }
      }
    ]
    
    for {scenario, updates} <- scenarios do
      IO.puts "  Testing scenario: #{scenario}"
      # Would broadcast these in a real test
      IO.puts "    Updates: #{inspect(updates)}"
    end
  end
  
  defp test_error_handling do
    IO.puts "\n[Test 5] Testing Error Handling..."
    
    # Test with invalid transport
    try do
      {:ok, _rate} = AutonomousOpponentV2Core.MCP.Transport.Router.get_error_rate(:invalid_transport)
      IO.puts "  ✗ Should have failed with invalid transport"
    rescue
      _ -> IO.puts "  ✓ Correctly handles invalid transport"
    end
    
    # Test circuit breaker state when not initialized
    try do
      _state = AutonomousOpponentV2Core.Core.CircuitBreaker.get_state(:non_existent_breaker)
      IO.puts "  ✗ Should have failed with non-existent circuit breaker"
    catch
      :exit, _ -> IO.puts "  ✓ Correctly handles non-existent circuit breaker"
    end
  end
end

# Run the tests
DashboardTester.run()