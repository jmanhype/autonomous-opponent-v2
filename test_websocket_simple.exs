#!/usr/bin/env elixir

# Simple test for WebSocket connection counting functionality
# Tests the ETS table operations directly

defmodule SimpleWebSocketTest do
  @connection_table :pattern_channel_connections
  
  def run do
    IO.puts("Testing WebSocket connection counting...")
    
    # Initialize the table
    init_connection_tracking()
    
    # Test 1: Add connections
    IO.puts("\n1. Testing connection increments:")
    increment_connection("patterns:stream", node())
    increment_connection("patterns:stream", node())
    increment_connection("patterns:stats", node())
    increment_connection("patterns:vsm", node())
    
    # Show current state
    show_connections()
    
    # Test 2: Get stats
    IO.puts("\n2. Testing get_connection_stats:")
    stats = get_connection_stats()
    IO.inspect(stats, pretty: true, label: "Connection stats")
    
    # Test 3: Decrement connections
    IO.puts("\n3. Testing connection decrements:")
    decrement_connection("patterns:stream", node())
    
    # Show state after decrement
    show_connections()
    
    # Test 4: Multiple nodes simulation
    IO.puts("\n4. Simulating multiple nodes:")
    other_node = :"node2@host"
    increment_connection("patterns:stream", other_node)
    increment_connection("patterns:stream", other_node)
    increment_connection("patterns:stats", other_node)
    
    # Show multi-node state
    show_connections()
    
    # Test 5: Aggregate across nodes
    IO.puts("\n5. Testing aggregation:")
    aggregated = aggregate_connection_stats()
    IO.inspect(aggregated, pretty: true, label: "Aggregated stats")
    
    IO.puts("\n✅ WebSocket connection counting tests completed!")
  end
  
  defp init_connection_tracking do
    if :ets.whereis(@connection_table) == :undefined do
      :ets.new(@connection_table, [:public, :named_table, :set, {:write_concurrency, true}])
      IO.puts("Created ETS table: #{@connection_table}")
    else
      IO.puts("ETS table already exists: #{@connection_table}")
    end
  end
  
  defp increment_connection(topic, node) do
    count = :ets.update_counter(@connection_table, {topic, node}, 1, {{topic, node}, 0})
    IO.puts("  #{topic} @ #{node} -> #{count}")
  end
  
  defp decrement_connection(topic, node) do
    count = :ets.update_counter(@connection_table, {topic, node}, -1, {{topic, node}, 0})
    IO.puts("  #{topic} @ #{node} -> #{count}")
  end
  
  defp show_connections do
    connections = :ets.tab2list(@connection_table)
    IO.puts("\nCurrent connections:")
    Enum.each(connections, fn {{topic, node}, count} ->
      IO.puts("  #{topic} @ #{node}: #{count}")
    end)
  end
  
  defp get_connection_stats do
    connections = :ets.tab2list(@connection_table)
    
    # Group by topic
    stats = Enum.reduce(connections, %{}, fn {{topic, node}, count}, acc ->
      Map.update(acc, topic, %{node => count}, fn existing ->
        Map.put(existing, node, count)
      end)
    end)
    
    # Calculate totals
    total_connections = connections
    |> Enum.map(fn {_, count} -> count end)
    |> Enum.sum()
    
    %{
      connections: stats,
      total: total_connections,
      node: node(),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp aggregate_connection_stats do
    connections = :ets.tab2list(@connection_table)
    
    # Group by topic and sum across nodes
    by_topic = Enum.reduce(connections, %{}, fn {{topic, _node}, count}, acc ->
      Map.update(acc, topic, count, &(&1 + count))
    end)
    
    # Group by node
    by_node = Enum.reduce(connections, %{}, fn {{_topic, node}, count}, acc ->
      Map.update(acc, node, count, &(&1 + count))
    end)
    
    total = connections
    |> Enum.map(fn {_, count} -> count end)
    |> Enum.sum()
    
    %{
      by_topic: by_topic,
      by_node: by_node,
      total_connections: total,
      unique_nodes: by_node |> Map.keys() |> length()
    }
  end
end

# Run the test
SimpleWebSocketTest.run()