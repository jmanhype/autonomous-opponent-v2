defmodule AutonomousOpponent.Core.MetricsIntegrationTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponent.Core.{Metrics, CircuitBreaker, RateLimiter}
  alias AutonomousOpponent.EventBus
  
  @moduletag :integration
  @moduletag :metrics
  
  setup do
    # Start EventBus if not already started
    case Process.whereis(AutonomousOpponent.EventBus) do
      nil -> {:ok, _} = EventBus.start_link()
      _ -> :ok
    end
    
    # Start metrics system
    metrics_name = :"metrics_integration_#{System.unique_integer()}"
    {:ok, metrics_pid} = Metrics.start_link(
      name: metrics_name,
      persist_interval_ms: 60_000
    )
    
    # Start circuit breaker
    breaker_name = :"breaker_#{System.unique_integer()}"
    {:ok, breaker_pid} = CircuitBreaker.start_link(
      name: breaker_name,
      failure_threshold: 3,
      recovery_time_ms: 1000
    )
    
    # Start rate limiter
    limiter_name = :"limiter_#{System.unique_integer()}"
    {:ok, limiter_pid} = RateLimiter.start_link(
      name: limiter_name,
      bucket_size: 10,
      refill_rate: 5
    )
    
    on_exit(fn ->
      for pid <- [metrics_pid, breaker_pid, limiter_pid] do
        if Process.alive?(pid), do: GenServer.stop(pid)
      end
    end)
    
    {:ok, 
      metrics: metrics_name,
      breaker: breaker_name,
      limiter: limiter_name
    }
  end
  
  describe "Circuit Breaker integration" do
    test "metrics track circuit breaker state changes", %{metrics: metrics, breaker: breaker} do
      # Cause circuit breaker to open by failing multiple times
      failing_function = fn -> raise "Test failure" end
      
      # Fail 3 times to open the circuit
      for _ <- 1..3 do
        {:error, _} = CircuitBreaker.call(breaker, failing_function)
      end
      
      # Give EventBus time to propagate
      Process.sleep(50)
      
      # Check metrics
      all_metrics = Metrics.get_all_metrics(metrics)
      
      # Should have recorded circuit breaker opened event
      opened_metrics = Enum.filter(all_metrics, fn
        {"circuit_breaker.opened" <> _, count} -> count > 0
        _ -> false
      end)
      
      assert length(opened_metrics) > 0
      
      # Should have recorded algedonic pain from circuit breaker
      pain_metrics = Enum.filter(all_metrics, fn
        {"vsm.algedonic.pain" <> _, _} -> true
        _ -> false
      end)
      
      assert length(pain_metrics) > 0
    end
    
    test "dashboard shows circuit breaker health", %{metrics: metrics, breaker: breaker} do
      # Trigger some circuit breaker activity
      success_function = fn -> {:ok, "success"} end
      failing_function = fn -> raise "Test failure" end
      
      # Some successes
      for _ <- 1..5 do
        {:ok, _} = CircuitBreaker.call(breaker, success_function)
      end
      
      # Some failures
      for _ <- 1..2 do
        {:error, _} = CircuitBreaker.call(breaker, failing_function)
      end
      
      Process.sleep(50)
      
      # Get dashboard
      dashboard = Metrics.get_vsm_dashboard(metrics)
      
      # Should reflect system health based on circuit breaker activity
      assert dashboard.system_health in [:excellent, :good, :fair, :poor]
      assert is_number(dashboard.algedonic_balance)
    end
  end
  
  describe "Rate Limiter integration" do
    test "metrics track rate limiting events", %{metrics: metrics, limiter: limiter} do
      # Consume tokens until rate limited
      results = for _ <- 1..15 do
        RateLimiter.consume(limiter, 1)
      end
      
      # Should have some successes and some rate limited
      allowed_count = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      limited_count = Enum.count(results, fn
        {:error, :rate_limited} -> true
        _ -> false
      end)
      
      assert allowed_count > 0
      assert limited_count > 0
      
      Process.sleep(50)
      
      # Check metrics
      all_metrics = Metrics.get_all_metrics(metrics)
      
      # Should have rate limiter metrics
      allowed_metrics = Enum.filter(all_metrics, fn
        {"rate_limiter.allowed" <> _, _} -> true
        _ -> false
      end)
      
      limited_metrics = Enum.filter(all_metrics, fn
        {"rate_limiter.limited" <> _, _} -> true
        _ -> false
      end)
      
      assert length(allowed_metrics) > 0
      assert length(limited_metrics) > 0
    end
    
    test "VSM subsystem rate limiting tracked separately", %{metrics: metrics, limiter: limiter} do
      # Test different subsystems
      for subsystem <- [:s1, :s2, :s3, :s4, :s5] do
        for _ <- 1..5 do
          RateLimiter.consume_for_subsystem(limiter, subsystem, 1)
        end
      end
      
      Process.sleep(50)
      
      # Get variety metrics
      variety_metrics = Metrics.get_variety_metrics(limiter)
      
      # Each subsystem should have recorded activity
      assert variety_metrics.s1 > 0
      assert variety_metrics.s2 > 0
      assert variety_metrics.s3 > 0
      assert variety_metrics.s4 > 0
      assert variety_metrics.s5 > 0
    end
  end
  
  describe "Combined system metrics" do
    test "algedonic balance reflects overall system health", %{
      metrics: metrics,
      breaker: breaker,
      limiter: limiter
    } do
      # Simulate mixed system activity
      
      # Some successful operations (pleasure)
      success_function = fn -> {:ok, "success"} end
      for _ <- 1..10 do
        {:ok, _} = CircuitBreaker.call(breaker, success_function)
      end
      
      # Some rate limit allowances
      for _ <- 1..5 do
        RateLimiter.consume(limiter, 1)
      end
      
      Process.sleep(50)
      
      # Get initial balance
      dashboard1 = Metrics.get_vsm_dashboard(metrics)
      initial_balance = dashboard1.algedonic_balance
      
      # Now cause some pain
      failing_function = fn -> raise "Test failure" end
      for _ <- 1..5 do
        {:error, _} = CircuitBreaker.call(breaker, failing_function)
      end
      
      # Exhaust rate limiter
      for _ <- 1..20 do
        RateLimiter.consume(limiter, 1)
      end
      
      Process.sleep(50)
      
      # Balance should have decreased
      dashboard2 = Metrics.get_vsm_dashboard(metrics)
      final_balance = dashboard2.algedonic_balance
      
      assert final_balance < initial_balance
    end
    
    test "alerts trigger on system degradation", %{
      metrics: metrics,
      breaker: breaker,
      limiter: limiter
    } do
      # Cause multiple circuit breakers to open
      failing_function = fn -> raise "Test failure" end
      
      # Open the circuit
      for _ <- 1..5 do
        {:error, _} = CircuitBreaker.call(breaker, failing_function)
      end
      
      # Cause high rate limiting
      for _ <- 1..150 do
        RateLimiter.consume(limiter, 1)
      end
      
      Process.sleep(100)
      
      # Check alerts
      alerts = Metrics.check_alerts(metrics)
      
      # Should have triggered some alerts
      assert length(alerts) > 0
      
      # Should include rate limiting alert
      assert Enum.any?(alerts, fn alert ->
        alert.alert == :high_rate_limiting
      end)
    end
  end
  
  describe "performance under load" do
    @tag :performance
    test "metrics system handles high event volume", %{
      metrics: metrics,
      breaker: breaker,
      limiter: limiter
    } do
      # Spawn concurrent workers
      tasks = for i <- 1..10 do
        Task.async(fn ->
          for j <- 1..100 do
            # Mix of operations
            case rem(j, 3) do
              0 ->
                # Circuit breaker call
                fun = if rem(j, 5) == 0 do
                  fn -> raise "Test failure" end
                else
                  fn -> {:ok, j} end
                end
                CircuitBreaker.call(breaker, fun)
                
              1 ->
                # Rate limiter call
                RateLimiter.consume(limiter, 1)
                
              2 ->
                # Direct metric
                Metrics.vsm_metric(metrics, Enum.random([:s1, :s2, :s3, :s4, :s5]), 
                                 "test_metric", j)
            end
          end
        end)
      end
      
      # Wait for completion
      Enum.each(tasks, &Task.await/1)
      
      Process.sleep(100)
      
      # System should have recorded all activity
      all_metrics = Metrics.get_all_metrics(metrics)
      assert length(all_metrics) > 0
      
      # Dashboard should still be responsive
      dashboard = Metrics.get_vsm_dashboard(metrics)
      assert is_map(dashboard)
      assert Map.has_key?(dashboard, :system_health)
      
      # Prometheus export should work
      prometheus_text = Metrics.prometheus_format(metrics)
      assert is_binary(prometheus_text)
      assert byte_size(prometheus_text) > 0
    end
  end
end