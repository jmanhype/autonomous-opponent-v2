defmodule AutonomousOpponentV2Core.EventBus.ClusterBenchmark do
  @moduledoc """
  Performance benchmarks for EventBus clustering.
  
  Run with: mix run test/autonomous_opponent_v2_core/event_bus/cluster_benchmark.exs
  """
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.EventBus.ClusterBridge
  
  require Logger
  
  def run do
    Logger.info("Starting EventBus Cluster Benchmarks...")
    
    # Start required services
    setup()
    
    # Run benchmarks
    benchmark_local_publish()
    benchmark_cluster_replication()
    benchmark_ordered_delivery()
    benchmark_circuit_breaker()
    benchmark_memory_usage()
    
    Logger.info("Benchmarks complete!")
  end
  
  defp setup do
    # Start EventBus and ClusterBridge
    {:ok, _} = EventBus.start_link()
    {:ok, _} = ClusterBridge.start_link()
    
    # Add some mock nodes for testing
    ClusterBridge.add_node(:"bench_node_1@localhost")
    ClusterBridge.add_node(:"bench_node_2@localhost")
    ClusterBridge.add_node(:"bench_node_3@localhost")
  end
  
  defp benchmark_local_publish do
    Logger.info("\n=== Local EventBus Publish Performance ===")
    
    # Warm up
    for _ <- 1..1000, do: EventBus.publish(:bench_event, %{data: "warmup"})
    
    # Benchmark different message sizes
    for size <- [100, 1_000, 10_000, 100_000] do
      data = :crypto.strong_rand_bytes(size) |> Base.encode64()
      
      {time, _} = :timer.tc(fn ->
        for _ <- 1..1000 do
          EventBus.publish(:bench_event, %{size: size, data: data})
        end
      end)
      
      avg_μs = time / 1000
      Logger.info("Message size #{size} bytes: #{avg_μs} μs/publish")
    end
  end
  
  defp benchmark_cluster_replication do
    Logger.info("\n=== Cluster Replication Performance ===")
    
    # Test replication with batching
    batch_sizes = [1, 10, 100, 1000]
    
    for batch_size <- batch_sizes do
      events = for i <- 1..batch_size do
        %{
          type: :bench_replicated,
          data: %{index: i, timestamp: System.system_time()},
          _from_cluster: false
        }
      end
      
      {time, _} = :timer.tc(fn ->
        for _ <- 1..div(10_000, batch_size) do
          Enum.each(events, &ClusterBridge.replicate_event/1)
        end
      end)
      
      events_per_sec = 10_000 / (time / 1_000_000)
      Logger.info("Batch size #{batch_size}: #{round(events_per_sec)} events/sec")
    end
  end
  
  defp benchmark_ordered_delivery do
    Logger.info("\n=== Ordered Delivery Overhead ===")
    
    # Create subscribers with and without ordering
    unordered_pid = spawn(fn -> receive_loop(0) end)
    ordered_pid = spawn(fn -> receive_loop(0) end)
    
    EventBus.subscribe(:bench_ordered, unordered_pid, ordered_delivery: false)
    EventBus.subscribe(:bench_ordered, ordered_pid, ordered_delivery: true)
    
    # Measure publish time with different subscriber configurations
    {unordered_time, _} = :timer.tc(fn ->
      for i <- 1..10_000 do
        EventBus.publish(:bench_ordered, %{index: i})
      end
    end)
    
    Logger.info("Publish time with ordering: #{unordered_time / 1000} ms for 10k events")
    
    # Cleanup
    Process.exit(unordered_pid, :kill)
    Process.exit(ordered_pid, :kill)
  end
  
  defp benchmark_circuit_breaker do
    Logger.info("\n=== Circuit Breaker Performance ===")
    
    # Simulate failures and measure circuit breaker response
    failing_node = :"failing_node@localhost"
    ClusterBridge.add_node(failing_node)
    
    # Force failures
    for _ <- 1..10 do
      send(ClusterBridge, {:replication_failure, failing_node})
    end
    
    # Measure performance with open circuit
    {time_with_circuit_open, _} = :timer.tc(fn ->
      for _ <- 1..1000 do
        ClusterBridge.replicate_event(%{
          type: :bench_circuit,
          data: %{test: true}
        })
      end
    end)
    
    Logger.info("Replication with circuit open: #{time_with_circuit_open / 1000} ms for 1k events")
    
    # Reset circuit
    send(ClusterBridge, {:replication_success, failing_node})
    
    # Measure with circuit closed
    {time_with_circuit_closed, _} = :timer.tc(fn ->
      for _ <- 1..1000 do
        ClusterBridge.replicate_event(%{
          type: :bench_circuit,
          data: %{test: true}
        })
      end
    end)
    
    Logger.info("Replication with circuit closed: #{time_with_circuit_closed / 1000} ms for 1k events")
    
    overhead = ((time_with_circuit_closed - time_with_circuit_open) / time_with_circuit_open) * 100
    Logger.info("Circuit breaker overhead: #{Float.round(overhead, 2)}%")
  end
  
  defp benchmark_memory_usage do
    Logger.info("\n=== Memory Usage Analysis ===")
    
    # Get baseline memory
    :erlang.garbage_collect()
    baseline = :erlang.memory(:total)
    
    # Create many subscribers
    subscribers = for i <- 1..1000 do
      pid = spawn(fn -> receive_loop(0) end)
      EventBus.subscribe(:"bench_mem_#{i}", pid)
      pid
    end
    
    # Measure memory after subscribers
    :erlang.garbage_collect()
    with_subscribers = :erlang.memory(:total)
    
    # Publish many events
    for i <- 1..10_000 do
      for j <- 1..10 do
        EventBus.publish(:"bench_mem_#{rem(i, 1000)}", %{data: "test #{j}"})
      end
    end
    
    # Final memory measurement
    :erlang.garbage_collect()
    final = :erlang.memory(:total)
    
    Logger.info("Baseline memory: #{format_bytes(baseline)}")
    Logger.info("With 1k subscribers: #{format_bytes(with_subscribers)} (+#{format_bytes(with_subscribers - baseline)})")
    Logger.info("After 100k events: #{format_bytes(final)} (+#{format_bytes(final - with_subscribers)})")
    
    # Cleanup
    Enum.each(subscribers, &Process.exit(&1, :kill))
  end
  
  defp receive_loop(count) do
    receive do
      _ -> receive_loop(count + 1)
    after
      60_000 -> count
    end
  end
  
  defp format_bytes(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{Float.round(bytes / (1024 * 1024), 2)} MB"
    end
  end
end

# Run benchmarks if called directly
if System.argv() == [] do
  AutonomousOpponentV2Core.EventBus.ClusterBenchmark.run()
end