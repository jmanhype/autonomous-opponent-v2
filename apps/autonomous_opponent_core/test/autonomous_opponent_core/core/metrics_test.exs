defmodule AutonomousOpponent.Core.MetricsTest do
  use ExUnit.Case, async: false
  alias AutonomousOpponent.Core.Metrics
  alias AutonomousOpponent.EventBus

  @moduletag :metrics

  setup do
    # Start a unique metrics instance for each test
    metrics_name = :"metrics_#{System.unique_integer()}"

    {:ok, pid} =
      Metrics.start_link(
        name: metrics_name,
        persist_interval_ms: 60_000,
        persist_path: "tmp/test_metrics"
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    {:ok, metrics_name: metrics_name}
  end

  describe "basic metric recording" do
    test "records counter metrics", %{metrics_name: metrics} do
      Metrics.counter(metrics, "test.counter", 1)
      Metrics.counter(metrics, "test.counter", 2)

      # Allow async cast to process
      Process.sleep(10)

      all_metrics = Metrics.get_all_metrics(metrics)
      assert {"test.counter", 3} in all_metrics
    end

    test "records gauge metrics", %{metrics_name: metrics} do
      Metrics.gauge(metrics, "test.gauge", 42)
      Metrics.gauge(metrics, "test.gauge", 100)

      Process.sleep(10)

      all_metrics = Metrics.get_all_metrics(metrics)
      assert {"test.gauge", 100} in all_metrics
    end

    test "records histogram metrics", %{metrics_name: metrics} do
      Metrics.histogram(metrics, "test.histogram", 10)
      Metrics.histogram(metrics, "test.histogram", 20)
      Metrics.histogram(metrics, "test.histogram", 30)

      Process.sleep(10)

      all_metrics = Metrics.get_all_metrics(metrics)

      {_key, histogram} =
        Enum.find(all_metrics, fn
          {"test.histogram", %{count: _}} -> true
          _ -> false
        end)

      assert histogram.count == 3
      assert histogram.sum == 60
      assert histogram.min == 10
      assert histogram.max == 30
    end

    test "records summary metrics", %{metrics_name: metrics} do
      for i <- 1..10, do: Metrics.summary(metrics, "test.summary", i)

      Process.sleep(10)

      all_metrics = Metrics.get_all_metrics(metrics)

      {_key, summary} =
        Enum.find(all_metrics, fn
          {"test.summary", %{count: _}} -> true
          _ -> false
        end)

      assert summary.count == 10
      assert summary.sum == 55
      assert length(summary.values) == 10
    end

    test "handles metrics with tags", %{metrics_name: metrics} do
      Metrics.counter(metrics, "test.tagged", 1, %{env: "test", region: "us-east"})
      Metrics.counter(metrics, "test.tagged", 1, %{env: "prod", region: "us-east"})

      Process.sleep(10)

      all_metrics = Metrics.get_all_metrics(metrics)

      # Should have two different metrics due to different tags
      tagged_metrics =
        Enum.filter(all_metrics, fn
          {"test.tagged" <> _, _} -> true
          _ -> false
        end)

      assert length(tagged_metrics) == 2
    end
  end

  describe "VSM-specific metrics" do
    test "records VSM subsystem metrics", %{metrics_name: metrics} do
      Metrics.vsm_metric(metrics, :s1, "operations_count", 100, :counter)
      Metrics.vsm_metric(metrics, :s2, "coordination_latency", 25, :gauge)
      Metrics.vsm_metric(metrics, :s3, "control_effectiveness", 0.85, :gauge)
      Metrics.vsm_metric(metrics, :s4, "patterns_detected", 5, :counter)
      Metrics.vsm_metric(metrics, :s5, "policies_active", 3, :gauge)

      Process.sleep(10)

      all_metrics = Metrics.get_all_metrics(metrics)

      # Verify S1 metric
      assert Enum.any?(all_metrics, fn
               {"vsm.operations_count" <> _, 100} -> true
               _ -> false
             end)

      # Verify S5 metric
      assert Enum.any?(all_metrics, fn
               {"vsm.policies_active" <> _, 3} -> true
               _ -> false
             end)
    end

    test "records variety flow metrics", %{metrics_name: metrics} do
      Metrics.variety_flow(metrics, :s1, 100, 80)
      Metrics.variety_flow(metrics, :s2, 80, 60)

      Process.sleep(10)

      all_metrics = Metrics.get_all_metrics(metrics)

      # Check variety absorbed
      assert Enum.any?(all_metrics, fn
               {"vsm.variety_absorbed" <> rest, 100} -> String.contains?(rest, "s1")
               _ -> false
             end)

      # Check variety generated
      assert Enum.any?(all_metrics, fn
               {"vsm.variety_generated" <> rest, 80} -> String.contains?(rest, "s1")
               _ -> false
             end)

      # Check attenuation calculation
      assert Enum.any?(all_metrics, fn
               {"vsm.variety_attenuation" <> rest, value} ->
                 String.contains?(rest, "s1") && abs(value - 0.8) < 0.01

               _ ->
                 false
             end)
    end

    test "records algedonic signals", %{metrics_name: metrics} do
      Metrics.algedonic_signal(metrics, :pain, 5, "circuit_breaker")
      Metrics.algedonic_signal(metrics, :pleasure, 3, "performance")
      Metrics.algedonic_signal(metrics, :pain, 2, "rate_limiter")

      Process.sleep(10)

      all_metrics = Metrics.get_all_metrics(metrics)

      # Check pain signals
      assert Enum.any?(all_metrics, fn
               {"vsm.algedonic.pain" <> _, 5} -> true
               _ -> false
             end)

      # Check pleasure signals
      assert Enum.any?(all_metrics, fn
               {"vsm.algedonic.pleasure" <> _, 3} -> true
               _ -> false
             end)

      # Check algedonic balance (should be -4: -5 + 3 - 2)
      assert {"vsm.algedonic.balance", -4} in all_metrics
    end
  end

  describe "Prometheus format export" do
    test "exports metrics in Prometheus format", %{metrics_name: metrics} do
      Metrics.counter(metrics, "http_requests_total", 42)
      Metrics.gauge(metrics, "memory_usage_bytes", 1024)

      Process.sleep(10)

      prometheus_text = Metrics.prometheus_format(metrics)

      assert prometheus_text =~ "http_requests_total 42"
      assert prometheus_text =~ "memory_usage_bytes 1024"
    end

    test "exports histograms with buckets", %{metrics_name: metrics} do
      for value <- [0.001, 0.01, 0.1, 1, 10],
          do: Metrics.histogram(metrics, "request_duration", value)

      Process.sleep(10)

      prometheus_text = Metrics.prometheus_format(metrics)

      assert prometheus_text =~ "request_duration_bucket"
      assert prometheus_text =~ "request_duration_count 5"
      assert prometheus_text =~ "request_duration_sum"
      assert prometheus_text =~ ~s(le="0.005")
      assert prometheus_text =~ ~s(le="+Inf")
    end
  end

  describe "VSM dashboard" do
    test "builds VSM dashboard data", %{metrics_name: metrics} do
      # Add some metrics
      Metrics.vsm_metric(metrics, :s1, "test", 1)
      Metrics.vsm_metric(metrics, :s2, "test", 2)
      Metrics.variety_flow(metrics, :s1, 100, 80)
      Metrics.algedonic_signal(metrics, :pleasure, 5, "test")

      Process.sleep(10)

      dashboard = Metrics.get_vsm_dashboard(metrics)

      assert Map.has_key?(dashboard, :subsystems)
      assert Map.has_key?(dashboard, :variety_flow)
      assert Map.has_key?(dashboard, :algedonic_balance)
      assert Map.has_key?(dashboard, :cybernetic_loops)
      assert Map.has_key?(dashboard, :system_health)

      assert dashboard.algedonic_balance == 5
      assert dashboard.variety_flow.total_absorbed > 0
    end
  end

  describe "alerting" do
    test "checks alert conditions", %{metrics_name: metrics} do
      # Trigger an alert condition
      Metrics.algedonic_signal(metrics, :pain, 60, "test")

      Process.sleep(10)

      alerts = Metrics.check_alerts(metrics)

      # Should trigger algedonic_severe_pain alert
      assert Enum.any?(alerts, fn alert ->
               alert.alert == :algedonic_severe_pain
             end)
    end

    test "no alerts when conditions not met", %{metrics_name: metrics} do
      # Add metrics that don't trigger alerts
      Metrics.algedonic_signal(metrics, :pleasure, 10, "test")

      Process.sleep(10)

      alerts = Metrics.check_alerts(metrics)
      assert alerts == []
    end
  end

  describe "persistence" do
    test "persists metrics to disk", %{metrics_name: metrics} do
      # Add some metrics
      Metrics.counter(metrics, "persist.test", 42)

      Process.sleep(10)

      # Manually trigger persistence
      assert :ok = Metrics.persist(metrics)

      # Check that persistence file was created
      persist_path = "tmp/test_metrics"
      {:ok, files} = File.ls(persist_path)
      assert Enum.any?(files, &String.starts_with?(&1, "metrics_"))
    end
  end

  describe "EventBus integration" do
    test "records circuit breaker events", %{metrics_name: metrics} do
      # Subscribe metrics to events (normally done in init)
      EventBus.subscribe(:circuit_breaker_opened)
      EventBus.subscribe(:circuit_breaker_closed)

      # Publish events
      EventBus.publish(:circuit_breaker_opened, %{name: "test_breaker"})
      EventBus.publish(:circuit_breaker_closed, %{name: "test_breaker"})

      Process.sleep(50)

      all_metrics = Metrics.get_all_metrics(metrics)

      opened_metrics =
        Enum.filter(all_metrics, fn
          {"circuit_breaker.opened" <> _, _} -> true
          _ -> false
        end)

      closed_metrics =
        Enum.filter(all_metrics, fn
          {"circuit_breaker.closed" <> _, _} -> true
          _ -> false
        end)

      # Metrics module should record these events
      assert length(opened_metrics) > 0
      assert length(closed_metrics) > 0
    end

    test "records rate limiter events", %{metrics_name: metrics} do
      EventBus.subscribe(:rate_limit_allowed)
      EventBus.subscribe(:rate_limited)

      EventBus.publish(:rate_limit_allowed, %{
        name: "test_limiter",
        scope: :global,
        tokens_remaining: 99
      })

      EventBus.publish(:rate_limited, %{name: "test_limiter", severity: :medium})

      Process.sleep(50)

      all_metrics = Metrics.get_all_metrics(metrics)

      allowed_metrics =
        Enum.filter(all_metrics, fn
          {"rate_limiter.allowed" <> _, _} -> true
          _ -> false
        end)

      limited_metrics =
        Enum.filter(all_metrics, fn
          {"rate_limiter.limited" <> _, _} -> true
          _ -> false
        end)

      assert length(allowed_metrics) > 0
      assert length(limited_metrics) > 0
    end
  end

  describe "performance characteristics" do
    @tag :performance
    test "handles high volume of metrics efficiently", %{metrics_name: metrics} do
      # Record 10,000 metrics
      start_time = System.monotonic_time(:millisecond)

      for i <- 1..10_000 do
        Metrics.counter(metrics, "perf.test", 1, %{batch: div(i, 100)})
      end

      # Wait for all to process
      Process.sleep(100)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should process 10k metrics in under 200ms
      assert duration < 200

      # Verify metrics were recorded
      all_metrics = Metrics.get_all_metrics(metrics)

      perf_metrics =
        Enum.filter(all_metrics, fn
          {"perf.test" <> _, _} -> true
          _ -> false
        end)

      # Should have 100 different metric keys (one per batch)
      assert length(perf_metrics) == 100
    end

    test "concurrent metric recording", %{metrics_name: metrics} do
      # Spawn 100 processes each recording 100 metrics
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            for j <- 1..100 do
              Metrics.counter(metrics, "concurrent.test", 1, %{process: i, iteration: j})
            end
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, &Task.await/1)

      Process.sleep(100)

      # Verify all metrics were recorded
      all_metrics = Metrics.get_all_metrics(metrics)

      concurrent_metrics =
        Enum.filter(all_metrics, fn
          {"concurrent.test" <> _, _} -> true
          _ -> false
        end)

      # Should have recorded all unique combinations
      assert length(concurrent_metrics) > 0
    end
  end
end
