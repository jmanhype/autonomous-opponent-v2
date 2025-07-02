defmodule AutonomousOpponent.Core.MetricsTest do
  use ExUnit.Case, async: false
  alias AutonomousOpponent.Core.Metrics
  alias AutonomousOpponent.EventBus

  setup do
    # Ensure clean state before each test
    if Process.whereis(Metrics) do
      GenServer.stop(Metrics)
    end
    
    # Start metrics system
    {:ok, _pid} = Metrics.start_link()
    
    # Subscribe to relevant events for testing
    EventBus.subscribe(:metric_threshold_violated)
    EventBus.subscribe(:algedonic_pain)
    EventBus.subscribe(:algedonic_pleasure)
    
    :ok
  end

  describe "counter metrics" do
    test "increments counter values" do
      Metrics.counter(:test_counter, 1)
      Metrics.counter(:test_counter, 2)
      
      # Give time for async cast
      Process.sleep(10)
      
      assert {:counter, 3} = Metrics.get(:test_counter)
    end

    test "supports labeled counters" do
      Metrics.counter(:http_requests, 1, %{method: "GET", status: 200})
      Metrics.counter(:http_requests, 1, %{method: "GET", status: 200})
      Metrics.counter(:http_requests, 1, %{method: "POST", status: 201})
      
      Process.sleep(10)
      
      assert {:counter, 2} = Metrics.get(:http_requests, %{method: "GET", status: 200})
      assert {:counter, 1} = Metrics.get(:http_requests, %{method: "POST", status: 201})
    end

    test "rejects negative counter values" do
      assert_raise FunctionClauseError, fn ->
        Metrics.counter(:test_counter, -1)
      end
    end
  end

  describe "gauge metrics" do
    test "stores current gauge value" do
      Metrics.gauge(:temperature, 20.5)
      Metrics.gauge(:temperature, 21.0)
      
      Process.sleep(10)
      
      assert {:gauge, 21.0} = Metrics.get(:temperature)
    end

    test "supports labeled gauges" do
      Metrics.gauge(:cpu_usage, 45.2, %{core: 1})
      Metrics.gauge(:cpu_usage, 67.8, %{core: 2})
      
      Process.sleep(10)
      
      assert {:gauge, 45.2} = Metrics.get(:cpu_usage, %{core: 1})
      assert {:gauge, 67.8} = Metrics.get(:cpu_usage, %{core: 2})
    end

    test "allows negative gauge values" do
      Metrics.gauge(:account_balance, -100.50)
      
      Process.sleep(10)
      
      assert {:gauge, -100.50} = Metrics.get(:account_balance)
    end
  end

  describe "histogram metrics" do
    test "collects histogram samples" do
      Metrics.histogram(:request_duration, 100)
      Metrics.histogram(:request_duration, 150)
      Metrics.histogram(:request_duration, 200)
      
      Process.sleep(10)
      
      assert {:histogram, samples} = Metrics.get(:request_duration)
      assert length(samples) == 3
      
      # Samples should be in reverse chronological order
      values = Enum.map(samples, &elem(&1, 1))
      assert values == [200, 150, 100]
    end

    test "supports labeled histograms" do
      Metrics.histogram(:query_time, 50, %{database: "users"})
      Metrics.histogram(:query_time, 75, %{database: "orders"})
      
      Process.sleep(10)
      
      assert {:histogram, samples1} = Metrics.get(:query_time, %{database: "users"})
      assert {:histogram, samples2} = Metrics.get(:query_time, %{database: "orders"})
      
      assert length(samples1) == 1
      assert length(samples2) == 1
    end

    test "enforces sliding window on samples" do
      # This test would need to mock time to properly test sliding window
      # For now, just verify samples are limited
      for i <- 1..1100 do
        Metrics.histogram(:large_histogram, i)
      end
      
      Process.sleep(50)
      
      assert {:histogram, samples} = Metrics.get(:large_histogram)
      assert length(samples) <= 1000  # Should be capped at 1000
    end
  end

  describe "VSM-specific metrics" do
    test "records variety absorbed metrics" do
      Metrics.vsm_metric(:variety_absorbed, 0.75, :s1)
      Metrics.vsm_metric(:variety_absorbed, 0.82, :s3)
      
      Process.sleep(10)
      
      assert {:gauge, 0.75} = Metrics.get(:vsm_variety_absorbed_ratio, %{subsystem: :s1})
      assert {:gauge, 0.82} = Metrics.get(:vsm_variety_absorbed_ratio, %{subsystem: :s3})
    end

    test "records variety generated metrics" do
      Metrics.vsm_metric(:variety_generated, 0.90, :s2)
      
      Process.sleep(10)
      
      assert {:gauge, 0.90} = Metrics.get(:vsm_variety_generated_ratio, %{subsystem: :s2})
    end

    test "records algedonic signals" do
      Metrics.vsm_metric(:algedonic_signal, 0.8, :s5, %{type: :pain})
      
      Process.sleep(10)
      
      assert {:histogram, samples} = Metrics.get(:vsm_algedonic_signals, 
                                                %{subsystem: :s5, type: :pain})
      assert length(samples) == 1
    end

    test "records loop latency" do
      Metrics.vsm_metric(:loop_latency, 45, :s3_star)
      
      Process.sleep(10)
      
      assert {:histogram, samples} = Metrics.get(:vsm_loop_latency_ms, 
                                                %{subsystem: :s3_star})
      assert length(samples) == 1
    end

    test "validates VSM subsystem" do
      assert_raise FunctionClauseError, fn ->
        Metrics.vsm_metric(:variety_absorbed, 0.5, :invalid_subsystem)
      end
    end
  end

  describe "algedonic signals" do
    test "records pain signals" do
      Metrics.algedonic(:pain, :high, %{source: :test})
      
      Process.sleep(10)
      
      assert {:histogram, samples} = Metrics.get(:algedonic_signals, 
                                                %{type: :pain, severity: :high, source: :test})
      assert length(samples) == 1
      assert elem(hd(samples), 1) == 1.0  # High severity = 1.0
    end

    test "records pleasure signals" do
      Metrics.algedonic(:pleasure, :medium, %{source: :test})
      
      Process.sleep(10)
      
      assert {:histogram, samples} = Metrics.get(:algedonic_signals, 
                                                %{type: :pleasure, severity: :medium, source: :test})
      assert length(samples) == 1
      assert elem(hd(samples), 1) == 0.6  # Medium severity = 0.6
    end

    test "publishes algedonic events to EventBus" do
      Metrics.algedonic(:pain, :low, %{source: :test_component})
      
      assert_receive {:event, :algedonic_pain, data}, 1000
      assert data.source == :test_component
      assert data.severity == :low
      assert data.value == 0.3
    end

    test "supports numeric severity values" do
      Metrics.algedonic(:neutral, 0.5, %{source: :test})
      
      Process.sleep(10)
      
      assert {:histogram, samples} = Metrics.get(:algedonic_signals, 
                                                %{type: :neutral, severity: 0.5, source: :test})
      assert elem(hd(samples), 1) == 0.5
    end
  end

  describe "Prometheus export" do
    test "exports counters in Prometheus format" do
      Metrics.counter(:test_total, 42)
      Process.sleep(10)
      
      output = Metrics.export(:prometheus)
      assert output =~ "# TYPE test_total counter"
      assert output =~ "test_total 42"
    end

    test "exports gauges in Prometheus format" do
      Metrics.gauge(:test_gauge, 3.14)
      Process.sleep(10)
      
      output = Metrics.export(:prometheus)
      assert output =~ "# TYPE test_gauge gauge"
      assert output =~ "test_gauge 3.14"
    end

    test "exports histograms in Prometheus format" do
      Metrics.histogram(:test_histogram, 50)
      Metrics.histogram(:test_histogram, 100)
      Metrics.histogram(:test_histogram, 200)
      Process.sleep(10)
      
      output = Metrics.export(:prometheus)
      assert output =~ "# TYPE test_histogram histogram"
      assert output =~ "test_histogram_bucket"
      assert output =~ "test_histogram_sum"
      assert output =~ "test_histogram_count 3"
    end

    test "formats labels correctly" do
      Metrics.counter(:labeled_metric, 1, %{env: "test", region: "us-east"})
      Process.sleep(10)
      
      output = Metrics.export(:prometheus)
      assert output =~ ~s(labeled_metric{env="test",region="us-east"} 1)
    end
  end

  describe "thresholds and alerting" do
    test "triggers alert when gauge exceeds max threshold" do
      Metrics.set_threshold(:temperature, :max, 30.0)
      Process.sleep(10)
      
      Metrics.gauge(:temperature, 35.0)
      
      assert_receive {:event, :metric_threshold_violated, data}, 1000
      assert data.metric == :temperature
      assert data.value == 35.0
      assert data.threshold == 30.0
      assert data.violation_type == {:above_max, 30.0}
    end

    test "triggers alert when gauge falls below min threshold" do
      Metrics.set_threshold(:battery_level, :min, 20.0)
      Process.sleep(10)
      
      Metrics.gauge(:battery_level, 15.0)
      
      assert_receive {:event, :metric_threshold_violated, data}, 1000
      assert data.metric == :battery_level
      assert data.value == 15.0
      assert data.threshold == 20.0
      assert data.violation_type == {:below_min, 20.0}
    end

    test "generates algedonic pain on threshold violation" do
      Metrics.set_threshold(:error_rate, :max, 0.05)
      Process.sleep(10)
      
      Metrics.gauge(:error_rate, 0.10)
      
      assert_receive {:event, :algedonic_pain, data}, 1000
      assert data.source == :metrics
      assert data.metric == :error_rate
      assert data.severity == :high  # Above max = high severity
    end

    test "respects labeled thresholds" do
      Metrics.set_threshold(:cpu_usage, :max, 80.0, %{server: "web1"})
      Process.sleep(10)
      
      # Should not trigger - different label
      Metrics.gauge(:cpu_usage, 90.0, %{server: "web2"})
      Process.sleep(10)
      refute_receive {:event, :metric_threshold_violated, _}, 100
      
      # Should trigger - matching label
      Metrics.gauge(:cpu_usage, 90.0, %{server: "web1"})
      assert_receive {:event, :metric_threshold_violated, data}, 1000
      assert data.labels == %{server: "web1"}
    end
  end

  describe "dashboard data" do
    test "returns comprehensive dashboard data" do
      # Setup some metrics
      Metrics.counter(:requests, 100)
      Metrics.gauge(:vsm_variety_absorbed_ratio, 0.75, %{subsystem: :s1})
      Metrics.gauge(:vsm_health_score, 0.9, %{subsystem: :s1})
      Metrics.algedonic(:pleasure, :high, %{source: :test})
      
      Process.sleep(50)
      
      data = Metrics.dashboard_data()
      
      assert is_integer(data.uptime_ms)
      assert data.uptime_ms > 0
      assert data.metrics_count > 0
      assert is_float(data.vsm_health)
      assert is_float(data.algedonic_balance)
      assert is_list(data.recent_alerts)
      assert is_map(data.subsystem_status)
      
      # Check subsystem status
      assert data.subsystem_status[:s1].variety_absorbed == 0.75
      assert data.subsystem_status[:s1].health_score == 0.9
      assert data.subsystem_status[:s1].status == :healthy
    end

    test "calculates VSM health correctly" do
      # Set variety absorption for all subsystems
      for subsystem <- [:s1, :s2, :s3, :s3_star, :s4, :s5] do
        Metrics.gauge(:vsm_variety_absorbed_ratio, 0.8, %{subsystem: subsystem})
      end
      
      Process.sleep(50)
      
      data = Metrics.dashboard_data()
      assert_in_delta data.vsm_health, 0.8, 0.01
    end

    test "calculates algedonic balance" do
      # Add 3 pain and 1 pleasure signal
      Metrics.algedonic(:pain, :high, %{})
      Metrics.algedonic(:pain, :medium, %{})  
      Metrics.algedonic(:pain, :low, %{})
      Metrics.algedonic(:pleasure, :high, %{})
      
      Process.sleep(50)
      
      data = Metrics.dashboard_data()
      # Balance should be negative (more pain than pleasure)
      assert data.algedonic_balance < 0
    end
  end

  describe "integration with CircuitBreaker events" do
    test "tracks circuit breaker state changes" do
      EventBus.publish(:circuit_breaker_state_change, %{
        name: :test_breaker,
        from: :closed,
        to: :open
      })
      
      Process.sleep(50)
      
      assert {:counter, 1} = Metrics.get(:circuit_breaker_transitions_total, 
                                        %{circuit_breaker: :test_breaker, 
                                          from_state: :closed, 
                                          to_state: :open})
      assert {:gauge, 2} = Metrics.get(:circuit_breaker_state, %{name: :test_breaker})
    end
  end

  describe "integration with RateLimiter events" do
    test "tracks rate limit violations" do
      EventBus.publish(:rate_limit_exceeded, %{
        name: :api_limiter,
        reason: "too_many_requests"
      })
      
      Process.sleep(50)
      
      assert {:counter, 1} = Metrics.get(:rate_limit_violations_total,
                                        %{limiter: :api_limiter, 
                                          reason: "too_many_requests"})
      
      # Should generate algedonic pain
      assert_receive {:event, :algedonic_pain, data}, 1000
      assert data.source == :rate_limiter
      assert data.limiter == :api_limiter
    end
  end

  describe "VSM message tracking" do
    test "tracks VSM message flow" do
      EventBus.publish(:vsm_message, %{
        from: :s1,
        to: :s2,
        type: "production_report",
        latency_ms: 25
      })
      
      Process.sleep(50)
      
      assert {:counter, 1} = Metrics.get(:vsm_messages_total,
                                        %{from: :s1, to: :s2, 
                                          message_type: "production_report"})
      
      assert {:histogram, samples} = Metrics.get(:vsm_message_latency_ms,
                                                %{from: :s1, to: :s2, 
                                                  message_type: "production_report"})
      assert length(samples) == 1
      assert elem(hd(samples), 1) == 25
    end
  end

  describe "telemetry integration" do
    test "emits telemetry events for metrics" do
      ref = :telemetry_test.attach_event_handlers(self(), [
        [:autonomous_opponent, :metrics, :test_metric]
      ])
      
      Metrics.counter(:test_metric, 5, %{test: true})
      
      assert_receive {:telemetry_event, [:autonomous_opponent, :metrics, :test_metric], 
                      measurements, metadata}
      assert measurements.value == 5
      assert metadata.test == true
      assert metadata.type == :counter
      
      :telemetry.detach(ref)
    end
  end

  describe "performance tests" do
    @tag :performance
    test "handles high volume of metrics efficiently" do
      start_time = System.monotonic_time(:millisecond)
      
      # Record 10,000 metrics
      for i <- 1..10_000 do
        Metrics.counter(:perf_counter, 1, %{batch: div(i, 100)})
        
        if rem(i, 3) == 0 do
          Metrics.gauge(:perf_gauge, :rand.uniform() * 100, %{sensor: rem(i, 10)})
        end
        
        if rem(i, 5) == 0 do
          Metrics.histogram(:perf_histogram, :rand.uniform() * 1000, %{endpoint: rem(i, 5)})
        end
      end
      
      # Allow async processing
      Process.sleep(100)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete in under 1 second
      assert duration < 1000, "High volume metrics took too long: #{duration}ms"
      
      # Verify some metrics were recorded
      assert {:counter, count} = Metrics.get(:perf_counter, %{batch: 1})
      assert count == 100
    end

    @tag :performance
    test "export remains fast with many metrics" do
      # Create diverse metrics
      for i <- 1..100 do
        Metrics.counter(:"counter_#{i}", i)
        Metrics.gauge(:"gauge_#{i}", i * 1.5)
        Metrics.histogram(:"histogram_#{i}", i * 10)
      end
      
      Process.sleep(100)
      
      start_time = System.monotonic_time(:millisecond)
      output = Metrics.export(:prometheus)
      end_time = System.monotonic_time(:millisecond)
      
      duration = end_time - start_time
      
      # Export should be fast even with many metrics
      assert duration < 100, "Export took too long: #{duration}ms"
      assert String.length(output) > 1000  # Should have substantial output
    end
  end

  # Helper module for telemetry testing
  defmodule :telemetry_test do
    def attach_event_handlers(test_pid, events) do
      ref = make_ref()
      
      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end
      
      :telemetry.attach(ref, events, handler, nil)
      ref
    end
  end
end