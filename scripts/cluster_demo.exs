#!/usr/bin/env elixir

# EventBus Cluster Demonstration Script
# 
# This script demonstrates the distributed EventBus cluster functionality
# including variety management, algedonic signals, and partition detection.
#
# Usage:
#   # Single node demo
#   mix run scripts/cluster_demo.exs
#
#   # Multi-node demo (start multiple terminals)
#   iex --name node1@localhost -S mix
#   iex --name node2@localhost -S mix
#   iex --name node3@localhost -S mix

Mix.install([
  {:autonomous_opponent_core, path: "apps/autonomous_opponent_core"}
])

defmodule ClusterDemo do
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.EventBus.Cluster
  
  def run do
    Logger.configure(level: :info)
    
    IO.puts """
    
    =====================================================
    🧠 VSM EVENTBUS CLUSTER DEMONSTRATION 🧠
    =====================================================
    
    This demonstration showcases the distributed EventBus
    implementing Stafford Beer's Viable System Model
    across multiple nodes.
    
    Current node: #{node()}
    Distributed: #{Node.alive?()}
    """
    
    if Node.alive?() do
      run_distributed_demo()
    else
      run_single_node_demo()
    end
  end
  
  defp run_single_node_demo do
    IO.puts """
    
    🔧 SINGLE NODE MODE
    
    To run the full distributed demo:
    1. Start multiple IEx sessions with different node names:
       iex --name node1@localhost -S mix
       iex --name node2@localhost -S mix
    2. Run this script in each session
    
    For now, demonstrating local functionality...
    """
    
    demonstrate_event_classification()
    demonstrate_variety_management()
    demonstrate_algedonic_signals()
  end
  
  defp run_distributed_demo do
    IO.puts """
    
    🌐 DISTRIBUTED MODE
    
    Connected nodes: #{inspect(Node.list())}
    """
    
    demonstrate_cluster_topology()
    demonstrate_event_replication()
    demonstrate_distributed_algedonic()
    demonstrate_partition_detection()
    demonstrate_variety_pressure()
    
    IO.puts """
    
    ✅ Distributed demonstration complete!
    
    Try these commands in different nodes:
    
    # Check cluster topology
    Cluster.topology()
    
    # Send algedonic scream
    Cluster.algedonic_scream(%{
      type: :pain, 
      severity: 9, 
      source: :demo,
      data: %{message: "Emergency test!"}
    })
    
    # Check variety pressure
    Cluster.variety_pressure()
    
    # Monitor partition status
    Cluster.partition_status()
    """
  end
  
  defp demonstrate_cluster_topology do
    IO.puts "\n🔍 CLUSTER TOPOLOGY"
    IO.puts String.duplicate("=", 50)
    
    topology = Cluster.topology()
    
    IO.puts "Node ID: #{topology.node_id}"
    IO.puts "Peers: #{inspect(topology.peers)}"
    IO.puts "Partition Status: #{inspect(topology.partition_status)}"
    IO.puts "Variety Pressure: #{topology.variety_pressure}"
    
    if length(topology.peers) > 0 do
      IO.puts "\nPeer States:"
      for {peer, state} <- topology.peer_states do
        IO.puts "  #{peer}: #{state.state} (#{state.events_sent} sent, #{state.events_received} received)"
      end
    end
  end
  
  defp demonstrate_event_replication do
    IO.puts "\n📡 EVENT REPLICATION"
    IO.puts String.duplicate("=", 50)
    
    # Subscribe to demo events
    EventBus.subscribe(:cluster_demo_event)
    
    IO.puts "Publishing S4 Intelligence event..."
    EventBus.publish(:pattern_detected, %{
      pattern_type: :temporal,
      confidence: 0.95,
      data: %{demo: true, timestamp: DateTime.utc_now()}
    })
    
    IO.puts "Publishing S3 Control event..."
    EventBus.publish(:resource_allocation, %{
      resource: :cpu,
      allocation: 75,
      node: node(),
      demo: true
    })
    
    IO.puts "Publishing S1 Operational event..."
    EventBus.publish(:task_execution, %{
      task_id: "demo_task_#{:rand.uniform(1000)}",
      status: :completed,
      duration_ms: 42
    })
    
    Process.sleep(1000)
    
    # Check if we received any events from other nodes
    received_count = count_pending_messages()
    IO.puts "Received #{received_count} replicated events"
  end
  
  defp demonstrate_distributed_algedonic do
    IO.puts "\n🚨 ALGEDONIC SIGNALS"
    IO.puts String.duplicate("=", 50)
    
    IO.puts "Testing pleasure signal..."
    Cluster.pleasure_signal(%{
      type: :pleasure,
      severity: 7,
      source: :demo,
      data: %{achievement: "cluster_demo_success", node: node()}
    })
    
    if length(Node.list()) > 0 do
      IO.puts "Testing emergency algedonic scream..."
      result = Cluster.algedonic_scream(%{
        type: :pain,
        severity: 8,
        source: :demo,
        data: %{
          alert: "Demonstration emergency signal",
          node: node(),
          timestamp: DateTime.utc_now()
        }
      })
      
      case result do
        {:ok, response} ->
          IO.puts "✅ Emergency scream sent!"
          IO.puts "  Confirmed nodes: #{inspect(response.confirmed_nodes)}"
          IO.puts "  Failed nodes: #{inspect(response.failed_nodes)}"
          IO.puts "  Latency: #{response.latency_ms}ms"
          
        {:error, reason} ->
          IO.puts "❌ Emergency scream failed: #{reason}"
      end
    else
      IO.puts "⚠️  No peers available for emergency scream test"
    end
    
    # Show algedonic statistics
    stats = Cluster.health_report().algedonic_stats
    IO.puts """
    
    Algedonic Statistics:
    - Screams sent: #{stats.screams_sent}
    - Screams received: #{stats.screams_received}
    - Pain signals: #{stats.pain_signals_sent}/#{stats.pain_signals_received}
    - Pleasure signals: #{stats.pleasure_signals_sent}/#{stats.pleasure_signals_received}
    """
  end
  
  defp demonstrate_partition_detection do
    IO.puts "\n🔀 PARTITION DETECTION"
    IO.puts String.duplicate("=", 50)
    
    partition_status = Cluster.partition_status()
    
    IO.puts "Strategy: #{partition_status.strategy}"
    IO.puts "Current partition: #{inspect(partition_status.current_partition)}"
    IO.puts "Nodes: #{inspect(partition_status.nodes)}"
    
    if length(partition_status.partition_history) > 0 do
      IO.puts "\nPartition History:"
      for {time, status, partitions, local} <- Enum.take(partition_status.partition_history, 3) do
        IO.puts "  #{time}: #{status} - #{inspect(partitions)} (local: #{inspect(local)})"
      end
    else
      IO.puts "No partition history (healthy cluster)"
    end
    
    # Test partition check
    check_result = Cluster.check_partitions()
    IO.puts "Manual partition check: #{inspect(check_result)}"
  end
  
  defp demonstrate_variety_pressure do
    IO.puts "\n📊 VARIETY MANAGEMENT"
    IO.puts String.duplicate("=", 50)
    
    overall_pressure = Cluster.variety_pressure()
    IO.puts "Overall variety pressure: #{Float.round(overall_pressure * 100, 1)}%"
    
    stats = Cluster.variety_stats()
    
    IO.puts "\nChannel Quotas:"
    for {channel, quota} <- stats.quotas do
      current_tokens = Map.get(stats.current_tokens, channel, quota)
      pressure = Map.get(stats.pressure_by_channel, channel, 0.0)
      
      quota_str = if quota == :unlimited, do: "∞", else: "#{quota}"
      tokens_str = if current_tokens == :unlimited, do: "∞", else: "#{current_tokens}"
      
      IO.puts "  #{channel}: #{tokens_str}/#{quota_str} (#{Float.round(pressure * 100, 1)}% pressure)"
    end
    
    if Map.get(stats, :events_throttled, %{}) |> Map.values() |> Enum.sum() > 0 do
      IO.puts "\n⚠️  Throttling detected:"
      for {channel, count} <- stats.events_throttled do
        IO.puts "  #{channel}: #{count} events throttled"
      end
    end
    
    if stats.compression_ratio > 0 do
      IO.puts "\n🗜️  Semantic compression active:"
      IO.puts "  Compression ratio: #{Float.round(stats.compression_ratio * 100, 1)}%"
      IO.puts "  Variety reduced: #{stats.total_variety_reduced} events"
    end
  end
  
  defp demonstrate_event_classification do
    IO.puts "\n🏷️  EVENT CLASSIFICATION"
    IO.puts String.duplicate("=", 50)
    
    test_events = [
      {:algedonic_pain, "Algedonic (Pain/Pleasure)"},
      {:policy_update, "S5 Policy"},
      {:pattern_detected, "S4 Intelligence"},
      {:resource_allocation, "S3 Control"},
      {:anti_oscillation, "S2 Coordination"},
      {:task_execution, "S1 Operational"},
      {:unknown_event, "General"}
    ]
    
    IO.puts "VSM Event Classification Demo:"
    
    for {event_name, description} <- test_events do
      EventBus.publish(event_name, %{demo: true, classification_test: true})
      IO.puts "  #{event_name} → #{description}"
    end
    
    Process.sleep(500)
  end
  
  defp demonstrate_variety_management do
    IO.puts "\n⚡ VARIETY MANAGEMENT"
    IO.puts String.duplicate("=", 50)
    
    # Generate some load to show variety management
    IO.puts "Generating variety load..."
    
    for i <- 1..50 do
      EventBus.publish(:load_test, %{sequence: i, load_test: true})
      if rem(i, 10) == 0 do
        IO.write(".")
      end
    end
    
    IO.puts "\nLoad generation complete."
    Process.sleep(1000)
  end
  
  defp demonstrate_algedonic_signals do
    IO.puts "\n🔴 ALGEDONIC SIGNALS"
    IO.puts String.duplicate("=", 50)
    
    IO.puts "Publishing algedonic pain signal..."
    EventBus.publish(:algedonic_pain, %{
      severity: 6,
      source: :demo,
      data: %{message: "Demonstration pain signal"}
    })
    
    IO.puts "Publishing algedonic pleasure signal..."
    EventBus.publish(:algedonic_pleasure, %{
      severity: 8,
      source: :demo,
      data: %{message: "Demonstration pleasure signal"}
    })
    
    Process.sleep(500)
  end
  
  defp count_pending_messages do
    # Count messages in process mailbox
    {:message_queue_len, count} = Process.info(self(), :message_queue_len)
    count
  end
end

# Run the demonstration
ClusterDemo.run()