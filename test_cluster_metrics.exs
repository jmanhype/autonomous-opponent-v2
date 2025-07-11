#!/usr/bin/env elixir
# Test script for distributed metrics aggregation

defmodule ClusterMetricsTest do
  @moduledoc """
  Test harness for VSM distributed metrics aggregation.
  Run this after starting multiple nodes with start_cluster_node.sh
  """
  
  def run do
    IO.puts("\n🧪 TESTING VSM DISTRIBUTED METRICS AGGREGATION\n")
    
    # Connect to other nodes
    connect_nodes()
    
    # Wait for cluster to stabilize
    Process.sleep(2000)
    
    # Generate test metrics on all nodes
    generate_test_metrics()
    
    # Test various aggregation scenarios
    test_basic_aggregation()
    test_vsm_health()
    test_time_series_queries()
    test_algedonic_signals()
    test_variety_management()
    
    IO.puts("\n✅ All tests completed!")
  end
  
  defp connect_nodes do
    IO.puts("📡 Checking cluster status...")
    
    # First check if we're already in distributed mode
    if Node.alive?() do
      IO.puts("  ✓ Running as distributed node: #{node()}")
      
      # Try to connect to other nodes if they exist
      nodes = [:"node2@127.0.0.1", :"node3@127.0.0.1"]
      
      connected = Enum.reduce(nodes, [], fn node, acc ->
        case Node.connect(node) do
          true -> 
            IO.puts("  ✓ Connected to #{node}")
            [node | acc]
          false -> 
            IO.puts("  ℹ️  Node #{node} not available")
            acc
        end
      end)
      
      if length(connected) > 0 do
        IO.puts("  Current cluster: #{inspect([node() | Node.list()])}")
      else
        IO.puts("  ⚠️  Running in single-node mode")
      end
    else
      IO.puts("  ⚠️  Not running in distributed mode - starting in single-node test mode")
    end
  end
  
  defp generate_test_metrics do
    IO.puts("\n📊 Generating test metrics on all nodes...")
    
    # Generate metrics locally
    metrics = AutonomousOpponentV2Core.Core.Metrics
    
    # VSM subsystem metrics
    metrics.record(metrics, "vsm.s1.variety_absorbed", :rand.uniform() * 1000)
    metrics.record(metrics, "vsm.s2.coordination_efficiency", :rand.uniform())
    metrics.record(metrics, "vsm.s3.resource_allocation", :rand.uniform() * 100)
    metrics.record(metrics, "vsm.s4.environmental_scan_rate", :rand.uniform() * 10)
    metrics.record(metrics, "vsm.s5.policy_decisions", :rand.uniform() * 5)
    
    # Algedonic signals
    metrics.record(metrics, "vsm.algedonic.pain", :rand.uniform() * 0.3)
    metrics.record(metrics, "vsm.algedonic.pleasure", :rand.uniform() * 0.7)
    
    # Performance metrics
    metrics.record(metrics, "latency.p95", 50 + :rand.uniform() * 100)
    metrics.record(metrics, "throughput.requests_per_sec", 1000 + :rand.uniform() * 5000)
    
    # Generate on remote nodes
    for node <- Node.list() do
      :erpc.call(node, fn ->
        m = AutonomousOpponentV2Core.Core.Metrics
        m.record(m, "vsm.s1.variety_absorbed", :rand.uniform() * 1000)
        m.record(m, "latency.p95", 50 + :rand.uniform() * 100)
      end)
    end
    
    IO.puts("  ✓ Generated metrics on #{length(Node.list()) + 1} nodes")
  end
  
  defp test_basic_aggregation do
    IO.puts("\n🔄 Testing basic cluster aggregation...")
    
    case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Aggregator) do
      nil ->
        IO.puts("  ⚠️  Cluster aggregator not running - testing local metrics instead")
        test_local_metrics()
        
      _pid ->
        case AutonomousOpponentV2Core.Metrics.Cluster.Aggregator.aggregate_cluster_metrics() do
          {:ok, metrics} ->
            IO.puts("  ✓ Aggregated #{length(metrics)} metrics across cluster")
            
            # Show sample aggregation
            sample = Enum.find(metrics, &(&1.name == "vsm.s1.variety_absorbed"))
            if sample do
              IO.puts("  Sample: #{sample.name}")
              IO.puts("    - Sum: #{sample.aggregated.sum}")
              IO.puts("    - Avg: #{sample.aggregated.avg}")
              IO.puts("    - Nodes: #{map_size(sample.node_values)}")
            end
            
          {:error, reason} ->
            IO.puts("  ✗ Aggregation failed: #{inspect(reason)}")
        end
    end
  end
  
  defp test_local_metrics do
    metrics = AutonomousOpponentV2Core.Core.Metrics
    all_metrics = metrics.get_all_metrics(metrics)
    
    IO.puts("  Local metrics count: #{map_size(all_metrics)}")
    
    # Show some sample metrics
    all_metrics
    |> Enum.take(5)
    |> Enum.each(fn {name, value} ->
      IO.puts("    - #{name}: #{value}")
    end)
  end
  
  defp test_vsm_health do
    IO.puts("\n🏥 Testing VSM health aggregation...")
    
    case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Aggregator) do
      nil ->
        IO.puts("  ⚠️  Cluster aggregator not running - skipping VSM health test")
        
      _pid ->
        case AutonomousOpponentV2Core.Metrics.Cluster.Aggregator.vsm_health() do
          {:ok, health} ->
            IO.puts("  ✓ VSM Health Status:")
            IO.puts("    - Overall: #{health.overall_health}%")
            
            Enum.each(health.subsystems, fn {subsystem, status} ->
              IO.puts("    - #{subsystem}: #{status.health}% (variety: #{status.variety_pressure})")
            end)
            
          {:error, reason} ->
            IO.puts("  ✗ Health check failed: #{inspect(reason)}")
        end
    end
  end
  
  defp test_time_series_queries do
    IO.puts("\n📈 Testing time-series queries...")
    
    case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.QueryEngine) do
      nil ->
        IO.puts("  ⚠️  Query engine not running - skipping time-series test")
        
      _pid ->
        query_engine = AutonomousOpponentV2Core.Metrics.Cluster.QueryEngine
        
        # Query last hour of latency data
        from = DateTime.add(DateTime.utc_now(), -3600, :second)
        to = DateTime.utc_now()
        
        case query_engine.query("latency.p95", :p95, from: from, to: to, window: :minute) do
          {:ok, data} ->
            IO.puts("  ✓ Retrieved #{length(data)} time windows")
            
          {:error, reason} ->
            IO.puts("  ✗ Query failed: #{inspect(reason)}")
        end
    end
  end
  
  defp test_algedonic_signals do
    IO.puts("\n⚡ Testing algedonic signal propagation...")
    
    # Simulate pain signal
    AutonomousOpponentV2Core.EventBus.publish(:algedonic_signal, %{
      type: :pain,
      intensity: 0.8,
      source: :s1_operations,
      timestamp: System.os_time(:millisecond)
    })
    
    Process.sleep(500)
    
    # Check if aggregator responded
    case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Aggregator) do
      nil ->
        IO.puts("  ⚠️  Cluster aggregator not running - testing EventBus signal dispatch only")
        IO.puts("  ✓ Algedonic signal published to EventBus")
        
      _pid ->
        case AutonomousOpponentV2Core.Metrics.Cluster.Aggregator.get_algedonic_state() do
          {:ok, state} ->
            IO.puts("  ✓ Algedonic state:")
            IO.puts("    - Pain level: #{state.pain_level}")
            IO.puts("    - Bypass active: #{state.bypass_active}")
            
          _ ->
            IO.puts("  ℹ️  Algedonic state not available")
        end
    end
  end
  
  defp test_variety_management do
    IO.puts("\n🎯 Testing variety management...")
    
    case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Aggregator) do
      nil ->
        IO.puts("  ⚠️  Cluster aggregator not running - skipping variety management test")
        
      _pid ->
        # Check variety quotas
        case AutonomousOpponentV2Core.Metrics.Cluster.Aggregator.get_variety_stats() do
          {:ok, stats} ->
            IO.puts("  ✓ Variety statistics:")
            IO.puts("    - Total absorbed: #{stats.total_absorbed}")
            IO.puts("    - Quota remaining: #{stats.quota_remaining}")
            IO.puts("    - Pressure: #{Float.round(stats.pressure * 100, 1)}%")
            
          _ ->
            IO.puts("  ℹ️  Variety stats not available")
        end
    end
  end
end

# Run the test
ClusterMetricsTest.run()