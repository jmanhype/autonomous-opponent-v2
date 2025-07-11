#!/usr/bin/env elixir

# Minimal test for WebSocket connection counting
# Starts only the necessary components

# First, let's test the WebSocket counting functionality in isolation
defmodule WebSocketCountingTest do
  def run do
    IO.puts("🧪 Testing WebSocket Connection Counting (Minimal)\n")
    
    # 1. Test ETS table operations
    IO.puts("1️⃣  Testing ETS table operations...")
    test_ets_operations()
    
    # 2. Test connection tracking logic
    IO.puts("\n2️⃣  Testing connection tracking logic...")
    test_connection_tracking()
    
    # 3. Test aggregation logic
    IO.puts("\n3️⃣  Testing aggregation logic...")
    test_aggregation()
    
    IO.puts("\n✅ All tests passed!")
  end
  
  defp test_ets_operations do
    table = :test_connections
    
    # Create table
    :ets.new(table, [:public, :named_table, :set, {:write_concurrency, true}])
    IO.puts("  ✓ Created ETS table")
    
    # Test update_counter with default
    count1 = :ets.update_counter(table, {"topic1", :node1}, 1, {{"topic1", :node1}, 0})
    assert count1 == 1, "First increment should return 1"
    IO.puts("  ✓ First increment: #{count1}")
    
    # Test increment existing
    count2 = :ets.update_counter(table, {"topic1", :node1}, 1, {{"topic1", :node1}, 0})
    assert count2 == 2, "Second increment should return 2"
    IO.puts("  ✓ Second increment: #{count2}")
    
    # Test decrement
    count3 = :ets.update_counter(table, {"topic1", :node1}, -1, {{"topic1", :node1}, 0})
    assert count3 == 1, "Decrement should return 1"
    IO.puts("  ✓ Decrement: #{count3}")
    
    # Test multiple topics
    :ets.update_counter(table, {"topic2", :node1}, 5, {{"topic2", :node1}, 0})
    :ets.update_counter(table, {"topic1", :node2}, 3, {{"topic1", :node2}, 0})
    
    all = :ets.tab2list(table)
    assert length(all) == 3, "Should have 3 entries"
    IO.puts("  ✓ Multiple entries: #{length(all)} entries")
    
    # Cleanup
    :ets.delete(table)
  end
  
  defp test_connection_tracking do
    # Simulate PatternsChannel logic
    table = :pattern_channel_connections
    :ets.new(table, [:public, :named_table, :set, {:write_concurrency, true}])
    
    # Simulate channel joins
    topics = ["patterns:stream", "patterns:stats", "patterns:vsm"]
    nodes = [:node1@host, :node2@host, :node3@host]
    
    # Create random connections
    Enum.each(topics, fn topic ->
      Enum.each(nodes, fn node ->
        count = :rand.uniform(5)
        Enum.each(1..count, fn _ ->
          :ets.update_counter(table, {topic, node}, 1, {{topic, node}, 0})
        end)
      end)
    end)
    
    # Get stats
    connections = :ets.tab2list(table)
    total = Enum.reduce(connections, 0, fn {_, count}, acc -> acc + count end)
    
    IO.puts("  ✓ Created #{total} connections across #{length(connections)} topic/node pairs")
    
    # Test stats generation
    stats = generate_connection_stats(table)
    IO.puts("  ✓ Generated stats with #{map_size(stats.connections)} topics")
    
    # Cleanup
    :ets.delete(table)
  end
  
  defp test_aggregation do
    # Test the aggregation logic from PatternAggregator
    node_stats = [
      %{
        node: :node1@host,
        connections: %{
          "patterns:stream" => %{node1@host: 10},
          "patterns:stats" => %{node1@host: 5}
        },
        total: 15
      },
      %{
        node: :node2@host,
        connections: %{
          "patterns:stream" => %{node2@host: 8},
          "patterns:stats" => %{node2@host: 3},
          "patterns:vsm" => %{node2@host: 4}
        },
        total: 15
      }
    ]
    
    aggregated = aggregate_connection_stats(node_stats)
    
    assert aggregated.total_connections == 30, "Total should be 30"
    assert aggregated.cluster_size == 2, "Cluster size should be 2"
    assert map_size(aggregated.topics) == 3, "Should have 3 topics"
    
    IO.puts("  ✓ Aggregated #{aggregated.total_connections} connections")
    IO.puts("  ✓ #{aggregated.cluster_size} nodes in cluster")
    IO.puts("  ✓ #{map_size(aggregated.topics)} unique topics")
  end
  
  defp generate_connection_stats(table) do
    connections = :ets.tab2list(table)
    
    stats = Enum.reduce(connections, %{}, fn {{topic, node}, count}, acc ->
      Map.update(acc, topic, %{node => count}, fn existing ->
        Map.put(existing, node, count)
      end)
    end)
    
    total = connections
    |> Enum.map(fn {_, count} -> count end)
    |> Enum.sum()
    
    %{
      connections: stats,
      total: total,
      node: node(),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp aggregate_connection_stats(node_stats) do
    initial = %{
      by_topic: %{},
      by_node: %{},
      total: 0
    }
    
    aggregated = Enum.reduce(node_stats, initial, fn node_stat, acc ->
      node = node_stat.node
      
      acc = put_in(acc.by_node[node], %{
        connections: node_stat.connections,
        total: node_stat.total
      })
      
      Enum.reduce(node_stat.connections, acc, fn {topic, node_counts}, acc ->
        topic_total = node_counts
        |> Map.values()
        |> Enum.sum()
        
        acc
        |> update_in([:by_topic, topic], fn existing ->
          Map.merge(existing || %{}, node_counts, fn _k, v1, v2 -> v1 + v2 end)
        end)
        |> update_in([:total], &(&1 + topic_total))
      end)
    end)
    
    topic_totals = aggregated.by_topic
    |> Enum.map(fn {topic, node_counts} ->
      total = node_counts
      |> Map.values()
      |> Enum.sum()
      
      {topic, %{
        nodes: node_counts,
        total: total
      }}
    end)
    |> Map.new()
    
    %{
      topics: topic_totals,
      nodes: aggregated.by_node,
      total_connections: aggregated.total,
      cluster_size: length(node_stats),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp assert(condition, message) do
    if condition do
      :ok
    else
      raise "Assertion failed: #{message}"
    end
  end
end

# Run the test
WebSocketCountingTest.run()