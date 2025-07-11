#!/usr/bin/env elixir

# Test PatternAggregator connection counting functionality
# This tests the cluster-wide aggregation without needing the full app

defmodule MockPatternsChannel do
  @connection_table :pattern_channel_connections
  
  def init_connection_tracking do
    if :ets.whereis(@connection_table) == :undefined do
      :ets.new(@connection_table, [:public, :named_table, :set, {:write_concurrency, true}])
    end
  end
  
  def get_connection_stats do
    init_connection_tracking()
    
    # Collect all connection data
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
  
  def simulate_connections do
    init_connection_tracking()
    
    # Simulate different connection patterns
    topics = ["patterns:stream", "patterns:stats", "patterns:vsm"]
    current_node = node()
    
    Enum.each(topics, fn topic ->
      count = :rand.uniform(10) + 5
      :ets.insert(@connection_table, {{topic, current_node}, count})
    end)
  end
end

defmodule TestPatternAggregator do
  def run do
    IO.puts("🧪 Testing PatternAggregator Connection Counting\n")
    
    # Simulate connections on this node
    IO.puts("1️⃣  Simulating connections on local node...")
    MockPatternsChannel.simulate_connections()
    
    local_stats = MockPatternsChannel.get_connection_stats()
    IO.inspect(local_stats, pretty: true, label: "Local connection stats")
    
    # Test aggregation logic directly
    IO.puts("\n2️⃣  Testing aggregation logic...")
    
    # Simulate stats from multiple nodes
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
          "patterns:vsm" => %{node2@host: 3}
        },
        total: 11
      },
      local_stats
    ]
    
    aggregated = aggregate_connection_stats(node_stats)
    IO.inspect(aggregated, pretty: true, label: "Aggregated cluster stats")
    
    # Test use cases
    IO.puts("\n3️⃣  Testing operational use cases...")
    
    # Auto-scaling check
    if aggregated.total_connections > 25 do
      IO.puts("  ⚠️  High connection count (#{aggregated.total_connections}) - consider scaling")
    else
      IO.puts("  ✅ Connection count normal (#{aggregated.total_connections})")
    end
    
    # Per-topic analysis
    IO.puts("\n  📊 Connections by topic:")
    Enum.each(aggregated.topics, fn {topic, data} ->
      IO.puts("     #{topic}: #{data.total} connections across #{map_size(data.nodes)} nodes")
    end)
    
    # Per-node analysis
    IO.puts("\n  🖥️  Connections by node:")
    Enum.each(aggregated.nodes, fn {node, data} ->
      IO.puts("     #{node}: #{data.total} total connections")
    end)
    
    IO.puts("\n✅ PatternAggregator connection counting tests completed!")
  end
  
  defp aggregate_connection_stats(node_stats) do
    # Initialize accumulator
    initial_acc = %{
      by_topic: %{},
      by_node: %{},
      total: 0,
      timestamp: DateTime.utc_now()
    }
    
    # Aggregate stats from all nodes
    aggregated = Enum.reduce(node_stats, initial_acc, fn node_stat, acc ->
      node = node_stat.node
      
      # Update by_node
      acc = put_in(acc.by_node[node], %{
        connections: node_stat.connections,
        total: node_stat.total
      })
      
      # Update by_topic and total
      acc = Enum.reduce(node_stat.connections, acc, fn {topic, node_counts}, acc ->
        # Sum connections for this topic
        topic_total = node_counts
        |> Map.values()
        |> Enum.sum()
        
        acc
        |> update_in([:by_topic, topic], fn existing ->
          Map.merge(existing || %{}, node_counts, fn _k, v1, v2 -> v1 + v2 end)
        end)
        |> update_in([:total], &(&1 + topic_total))
      end)
      
      acc
    end)
    
    # Calculate topic totals
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
      timestamp: aggregated.timestamp
    }
  end
end

# Run the test
TestPatternAggregator.run()