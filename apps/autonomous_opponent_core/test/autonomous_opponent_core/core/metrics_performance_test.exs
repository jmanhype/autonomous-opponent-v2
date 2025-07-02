defmodule AutonomousOpponent.Core.MetricsPerformanceTest do
  use ExUnit.Case, async: false

  alias AutonomousOpponent.Core.Metrics

  @moduletag :performance
  @moduletag :metrics

  setup do
    # Start metrics with minimal persistence to focus on performance
    metrics_name = :"metrics_perf_#{System.unique_integer()}"

    {:ok, pid} =
      Metrics.start_link(
        name: metrics_name,
        # 5 minutes to avoid I/O during tests
        persist_interval_ms: 300_000
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    {:ok, metrics_name: metrics_name}
  end

  describe "metric recording performance" do
    test "counter performance - 100k operations", %{metrics_name: metrics} do
      start_time = System.monotonic_time(:millisecond)

      # Record 100,000 counter increments
      for i <- 1..100_000 do
        Metrics.counter(metrics, "perf.counter", 1, %{batch: rem(i, 1000)})
      end

      # Allow processing
      Process.sleep(500)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should complete in under 2 seconds
      assert duration < 2000, "Counter recording took #{duration}ms, expected < 2000ms"

      # Calculate throughput
      throughput = 100_000 / (duration / 1000)
      IO.puts("Counter throughput: #{round(throughput)} ops/sec")
    end

    test "gauge performance - 50k operations", %{metrics_name: metrics} do
      start_time = System.monotonic_time(:millisecond)

      # Record 50,000 gauge updates
      for i <- 1..50_000 do
        Metrics.gauge(metrics, "perf.gauge.#{rem(i, 100)}", i)
      end

      Process.sleep(300)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should complete in under 1 second
      assert duration < 1000, "Gauge recording took #{duration}ms, expected < 1000ms"
    end

    test "histogram performance - 25k operations", %{metrics_name: metrics} do
      start_time = System.monotonic_time(:millisecond)

      # Record 25,000 histogram values
      for i <- 1..25_000 do
        value = :rand.uniform() * 10
        Metrics.histogram(metrics, "perf.histogram", value, %{type: rem(i, 10)})
      end

      Process.sleep(300)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Histograms are more complex, allow 1.5 seconds
      assert duration < 1500, "Histogram recording took #{duration}ms, expected < 1500ms"
    end

    test "mixed workload performance", %{metrics_name: metrics} do
      start_time = System.monotonic_time(:millisecond)

      # Simulate realistic mixed workload
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            for j <- 1..1000 do
              case rem(j, 4) do
                0 ->
                  Metrics.counter(metrics, "mixed.requests", 1, %{worker: i})

                1 ->
                  Metrics.gauge(metrics, "mixed.memory", j * 1024, %{worker: i})

                2 ->
                  Metrics.histogram(metrics, "mixed.latency", :rand.uniform() * 100, %{worker: i})

                3 ->
                  Metrics.vsm_metric(
                    metrics,
                    Enum.random([:s1, :s2, :s3, :s4, :s5]),
                    "operations",
                    j
                  )
              end
            end
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, &Task.await/1)
      Process.sleep(100)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # 10 workers × 1000 ops each = 10k total ops
      assert duration < 500, "Mixed workload took #{duration}ms, expected < 500ms"

      # Verify data integrity
      all_metrics = Metrics.get_all_metrics(metrics)
      assert length(all_metrics) > 0
    end
  end

  describe "VSM metrics performance" do
    test "variety flow calculations", %{metrics_name: metrics} do
      start_time = System.monotonic_time(:millisecond)

      # Simulate variety flow for all subsystems
      for _ <- 1..1000 do
        for subsystem <- [:s1, :s2, :s3, :s4, :s5] do
          absorbed = :rand.uniform(1000)
          generated = :rand.uniform(800)
          Metrics.variety_flow(metrics, subsystem, absorbed, generated)
        end
      end

      Process.sleep(200)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # 5000 variety calculations
      assert duration < 300, "Variety flow took #{duration}ms, expected < 300ms"
    end

    test "algedonic signal processing", %{metrics_name: metrics} do
      start_time = System.monotonic_time(:millisecond)

      # Simulate algedonic signals
      for i <- 1..10_000 do
        type = if rem(i, 2) == 0, do: :pain, else: :pleasure
        intensity = :rand.uniform(10)
        source = Enum.random(["circuit_breaker", "rate_limiter", "vsm_s1", "vsm_s2"])

        Metrics.algedonic_signal(metrics, type, intensity, source)
      end

      Process.sleep(200)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert duration < 400, "Algedonic processing took #{duration}ms, expected < 400ms"
    end
  end

  describe "query performance" do
    test "Prometheus export with large dataset", %{metrics_name: metrics} do
      # Generate substantial dataset
      for i <- 1..100 do
        Metrics.counter(metrics, "export.counter.#{i}", i * 10)
        Metrics.gauge(metrics, "export.gauge.#{i}", i * 100)
        Metrics.histogram(metrics, "export.histogram.#{i}", :rand.uniform() * i)
      end

      Process.sleep(100)

      # Time the export
      start_time = System.monotonic_time(:millisecond)
      prometheus_text = Metrics.prometheus_format(metrics)
      end_time = System.monotonic_time(:millisecond)

      duration = end_time - start_time

      # Export should be fast even with many metrics
      assert duration < 50, "Prometheus export took #{duration}ms, expected < 50ms"
      assert byte_size(prometheus_text) > 0
    end

    test "dashboard query performance", %{metrics_name: metrics} do
      # Generate realistic dashboard data
      for subsystem <- [:s1, :s2, :s3, :s4, :s5] do
        for i <- 1..100 do
          Metrics.vsm_metric(metrics, subsystem, "metric_#{i}", i)
          Metrics.variety_flow(metrics, subsystem, i * 10, i * 8)
        end
      end

      Process.sleep(100)

      # Time dashboard query
      start_time = System.monotonic_time(:millisecond)
      dashboard = Metrics.get_vsm_dashboard(metrics)
      end_time = System.monotonic_time(:millisecond)

      duration = end_time - start_time

      # Dashboard aggregation should be fast
      assert duration < 20, "Dashboard query took #{duration}ms, expected < 20ms"
      assert is_map(dashboard)
      assert Map.has_key?(dashboard, :subsystems)
    end

    test "alert checking performance", %{metrics_name: metrics} do
      # Generate metrics that might trigger alerts
      Metrics.algedonic_signal(metrics, :pain, 60, "test")

      for i <- 1..200 do
        Metrics.counter(metrics, "rate_limiter.limited", 1)
      end

      Process.sleep(100)

      # Time alert checking
      start_time = System.monotonic_time(:millisecond)
      alerts = Metrics.check_alerts(metrics)
      end_time = System.monotonic_time(:millisecond)

      duration = end_time - start_time

      # Alert checking should be fast
      assert duration < 10, "Alert checking took #{duration}ms, expected < 10ms"
      assert is_list(alerts)
    end
  end

  describe "memory efficiency" do
    @tag :memory
    test "memory usage under sustained load", %{metrics_name: metrics} do
      # Get initial memory
      :erlang.garbage_collect()
      {:memory, initial_memory} = Process.info(Process.whereis(metrics), :memory)

      # Generate sustained load
      for batch <- 1..100 do
        for i <- 1..100 do
          Metrics.counter(metrics, "memory.test", 1, %{batch: batch, item: i})
        end

        # Small delay to simulate real traffic
        Process.sleep(10)
      end

      # Force GC and check memory
      :erlang.garbage_collect(Process.whereis(metrics))
      {:memory, final_memory} = Process.info(Process.whereis(metrics), :memory)

      memory_growth = final_memory - initial_memory
      memory_growth_mb = memory_growth / 1_048_576

      IO.puts("Memory growth: #{Float.round(memory_growth_mb, 2)} MB")

      # Memory growth should be reasonable (< 10MB for 10k metrics)
      assert memory_growth_mb < 10, "Excessive memory growth: #{memory_growth_mb} MB"
    end
  end

  describe "concurrency stress test" do
    @tag :stress
    test "handles extreme concurrency", %{metrics_name: metrics} do
      # Spawn many concurrent processes
      process_count = 100
      ops_per_process = 100

      start_time = System.monotonic_time(:millisecond)

      tasks =
        for p <- 1..process_count do
          Task.async(fn ->
            for i <- 1..ops_per_process do
              # Random metric operations
              case :rand.uniform(5) do
                1 ->
                  Metrics.counter(metrics, "stress.counter", 1, %{proc: p})

                2 ->
                  Metrics.gauge(metrics, "stress.gauge", i, %{proc: p})

                3 ->
                  Metrics.histogram(metrics, "stress.histogram", :rand.uniform() * 100)

                4 ->
                  Metrics.variety_flow(
                    metrics,
                    Enum.random([:s1, :s2, :s3, :s4, :s5]),
                    :rand.uniform(100),
                    :rand.uniform(80)
                  )

                5 ->
                  Metrics.algedonic_signal(
                    metrics,
                    Enum.random([:pain, :pleasure]),
                    :rand.uniform(10),
                    "stress_test"
                  )
              end
            end
          end)
        end

      # Wait for all tasks
      results = Task.yield_many(tasks, 5000)

      successful =
        Enum.count(results, fn {_task, res} ->
          match?({:ok, _}, res)
        end)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # All tasks should complete
      assert successful == process_count,
             "Only #{successful}/#{process_count} tasks completed"

      # Should handle 10k operations in reasonable time
      total_ops = process_count * ops_per_process
      throughput = total_ops / (duration / 1000)

      IO.puts("Concurrency test: #{total_ops} ops in #{duration}ms")
      IO.puts("Throughput: #{round(throughput)} ops/sec")

      assert duration < 3000, "Stress test took too long: #{duration}ms"
    end
  end
end
