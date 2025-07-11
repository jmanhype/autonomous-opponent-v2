#!/usr/bin/env elixir

# Test script for WebSocket connection counting
# Usage: mix run test_websocket_connections.exs

defmodule WebSocketConnectionTest do
  @moduledoc """
  Tests the WebSocket connection counting feature.
  """
  
  require Logger
  
  def run do
    Logger.info("Starting WebSocket connection counting test...")
    
    # Ensure the connection tracking table is initialized
    AutonomousOpponentV2Web.PatternsChannel.init_connection_tracking()
    
    # Simulate connections
    simulate_connections()
    
    # Get local stats
    local_stats = AutonomousOpponentV2Web.PatternsChannel.get_connection_stats()
    Logger.info("Local connection stats: #{inspect(local_stats, pretty: true)}")
    
    # Test cluster aggregation (if PatternAggregator is running)
    test_cluster_aggregation()
    
    Logger.info("WebSocket connection counting test completed!")
  end
  
  defp simulate_connections do
    Logger.info("Simulating WebSocket connections...")
    
    # Get the connection table
    table = :pattern_channel_connections
    
    # Simulate connections to different topics
    topics = ["patterns:stream", "patterns:stats", "patterns:vsm"]
    current_node = node()
    
    Enum.each(topics, fn topic ->
      # Simulate 5-15 connections per topic
      count = :rand.uniform(10) + 5
      
      Logger.info("Simulating #{count} connections to #{topic}")
      
      # Update the counter as if connections were made
      :ets.update_counter(table, {topic, current_node}, count, {{topic, current_node}, 0})
    end)
    
    # Show current table contents
    all_connections = :ets.tab2list(table)
    Logger.info("Current connections in ETS: #{inspect(all_connections, pretty: true)}")
  end
  
  defp test_cluster_aggregation do
    case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator) do
      nil ->
        Logger.warning("PatternAggregator not running - skipping cluster aggregation test")
        
      _pid ->
        Logger.info("Testing cluster-wide connection aggregation...")
        
        case AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator.get_cluster_connection_stats() do
          {:ok, stats} ->
            Logger.info("Cluster connection stats:")
            Logger.info("  Total connections: #{stats.total_connections}")
            Logger.info("  Cluster size: #{stats.cluster_size}")
            Logger.info("  Topics: #{inspect(stats.topics, pretty: true)}")
            Logger.info("  Nodes: #{inspect(stats.nodes, pretty: true)}")
            
          {:error, reason} ->
            Logger.error("Failed to get cluster stats: #{reason}")
        end
    end
  end
end

# Run the test
WebSocketConnectionTest.run()