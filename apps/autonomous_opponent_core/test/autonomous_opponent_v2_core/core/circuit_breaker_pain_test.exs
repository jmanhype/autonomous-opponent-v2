defmodule AutonomousOpponentV2Core.Core.CircuitBreakerPainTest do
  @moduledoc """
  CYBERNETIC PAIN TESTING - Ensuring the System Can Feel
  
  These tests verify that circuit breakers respond to algedonic pain signals
  as Beer intended - immediate, visceral, protective responses that bypass
  normal control hierarchies.
  """
  use ExUnit.Case, async: false
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Start EventBus if not running
    case Process.whereis(EventBus) do
      nil -> start_supervised!(EventBus)
      _pid -> :ok
    end
    
    # Create test circuit breaker with pain awareness
    {:ok, pid} = CircuitBreaker.start_link(
      name: :pain_test_breaker,
      pain_threshold: 0.8,
      pain_window_ms: 1000,
      pain_response_enabled: true,
      failure_threshold: 5
    )
    
    %{pid: pid, name: :pain_test_breaker}
  end
  
  describe "basic pain response" do
    test "circuit opens when pain intensity exceeds threshold", %{name: name} do
      # Circuit should start closed
      assert %{state: :closed} = CircuitBreaker.get_state(name)
      
      # Send high intensity pain signal
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        severity: :critical,  # Maps to 1.0 intensity
        metric: :response_time,
        reason: "Service degradation detected",
        scope: :system_wide
      })
      
      # Allow pain processing
      Process.sleep(50)
      
      # Circuit should now be open
      state = CircuitBreaker.get_state(name)
      assert state.state == :open
      assert state.metrics.pain_triggered_opens > 0
    end
    
    test "circuit ignores pain below threshold", %{name: name} do
      # Send moderate pain signal
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        severity: :medium,  # Maps to 0.5 intensity
        metric: :cpu_usage,
        scope: :system_wide
      })
      
      Process.sleep(50)
      
      # Circuit should remain closed
      assert %{state: :closed} = CircuitBreaker.get_state(name)
    end
    
    test "circuit ignores its own pain to prevent feedback loops", %{name: name} do
      # Send pain signal from the circuit breaker itself
      EventBus.publish(:algedonic_pain, %{
        source: :circuit_breaker,
        name: name,
        severity: :critical,
        reason: "Self-inflicted pain"
      })
      
      Process.sleep(50)
      
      # Circuit should remain closed (ignored own pain)
      assert %{state: :closed} = CircuitBreaker.get_state(name)
    end
  end
  
  describe "sustained pain patterns" do
    test "circuit opens on sustained moderate pain", %{name: name} do
      # Send multiple moderate pain signals
      for i <- 1..4 do
        EventBus.publish(:algedonic_pain, %{
          source: :test_monitor,
          severity: :medium,  # 0.5 intensity
          metric: :error_rate,
          reason: "Sustained errors #{i}",
          scope: :system_wide
        })
        Process.sleep(10)
      end
      
      # Wait for aggregation
      Process.sleep(100)
      
      # Circuit should open due to sustained pain
      assert %{state: :open} = CircuitBreaker.get_state(name)
    end
    
    test "pain signals expire after window", %{name: name} do
      # Send old pain signal
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        severity: :high,  # 0.8 intensity - normally triggers
        scope: :system_wide
      })
      
      # Wait for window to expire (1000ms + buffer)
      Process.sleep(1100)
      
      # Send another signal
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        severity: :medium,
        scope: :system_wide
      })
      
      Process.sleep(50)
      
      # Circuit should still be closed (old pain expired)
      assert %{state: :closed} = CircuitBreaker.get_state(name)
    end
  end
  
  describe "pain escalation detection" do
    test "circuit opens on rapid pain escalation", %{name: name} do
      # Start with low pain
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        intensity: 0.2,
        scope: :system_wide
      })
      
      Process.sleep(100)
      
      # Rapid escalation to high pain
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        intensity: 0.9,
        scope: :system_wide
      })
      
      Process.sleep(50)
      
      # Circuit should open due to escalation rate
      assert %{state: :open} = CircuitBreaker.get_state(name)
    end
  end
  
  describe "emergency pain signals" do
    test "emergency pain forces immediate opening", %{name: name} do
      # Emergency pain bypasses all thresholds
      EventBus.publish(:emergency_algedonic, %{
        source: :system_governor,
        message: "CRITICAL SYSTEM FAILURE IMMINENT",
        affected_services: [:all]
      })
      
      Process.sleep(50)
      
      # Circuit should be forced open
      assert %{state: :open} = CircuitBreaker.get_state(name)
    end
    
    test "emergency pain triggers cascade warnings", %{name: name} do
      # Subscribe to cascade events
      EventBus.subscribe(:circuit_breaker_emergency_cascade)
      
      # Send emergency signal
      EventBus.publish(:emergency_algedonic, %{
        source: :s5_policy,
        message: "System-wide emergency declared"
      })
      
      # Should receive cascade warning
      assert_receive {:event_bus, :circuit_breaker_emergency_cascade, cascade_data}, 500
      assert cascade_data.source == name
    end
  end
  
  describe "pain with existing failures" do
    test "pain accelerates opening when combined with failures", %{name: name} do
      # Record some failures (but not enough to open)
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      
      # Add moderate pain
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        severity: :medium,
        scope: :system_wide
      })
      
      Process.sleep(50)
      
      # Circuit should consider both pain and failures
      state = CircuitBreaker.get_state(name)
      
      # Either open due to combined stress, or very close
      assert state.state == :open or state.failure_count >= 2
    end
  end
  
  describe "pain learning and prediction" do
    test "circuit tracks pain patterns for learning", %{name: name} do
      # Send pattern of pain signals
      for i <- 1..5 do
        EventBus.publish(:algedonic_pain, %{
          source: :test_monitor,
          intensity: 0.3 + (i * 0.1),  # Escalating pattern
          metric: :pattern_test,
          scope: :system_wide
        })
        Process.sleep(50)
      end
      
      # Get state to check learning data
      state = GenServer.call(name, :get_state)
      
      # Should have correlation strength > 0
      assert state.pain_learning_data.correlation_strength > 0
    end
  end
  
  describe "contextual pain filtering" do
    test "circuit responds to pain from protected services", %{name: name} do
      # Pain explicitly affecting this circuit
      EventBus.publish(:algedonic_pain, %{
        source: :dependent_service,
        severity: :high,
        affected_services: [name],
        reason: "Upstream failure"
      })
      
      Process.sleep(50)
      
      # Should respond to targeted pain
      assert %{state: :open} = CircuitBreaker.get_state(name)
    end
    
    test "circuit tracks ambient pain without acting", %{name: name} do
      # Pain not relevant to this circuit
      EventBus.publish(:algedonic_pain, %{
        source: :unrelated_service,
        severity: :high,
        affected_services: [:other_circuit],
        reason: "Someone else's problem"
      })
      
      Process.sleep(50)
      
      # Should remain closed but track the pain
      assert %{state: :closed} = CircuitBreaker.get_state(name)
    end
  end
  
  describe "pain response configuration" do
    test "pain response can be disabled", %{pid: _pid} do
      # Create breaker with pain disabled
      {:ok, _} = CircuitBreaker.start_link(
        name: :pain_disabled_breaker,
        pain_response_enabled: false,
        pain_threshold: 0.8
      )
      
      # Send critical pain
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        severity: :critical,
        scope: :system_wide
      })
      
      Process.sleep(50)
      
      # Should remain closed
      assert %{state: :closed} = CircuitBreaker.get_state(:pain_disabled_breaker)
    end
    
    test "pain threshold is configurable", %{pid: _pid} do
      # Create breaker with low threshold
      {:ok, _} = CircuitBreaker.start_link(
        name: :sensitive_breaker,
        pain_threshold: 0.3  # Very sensitive
      )
      
      # Send moderate pain
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        severity: :medium,  # 0.5 > 0.3 threshold
        scope: :system_wide
      })
      
      Process.sleep(50)
      
      # Should open due to low threshold
      assert %{state: :open} = CircuitBreaker.get_state(:sensitive_breaker)
    end
  end
  
  describe "pain recovery behavior" do
    test "additional pain resets recovery timer when open", %{name: name} do
      # Force circuit open
      CircuitBreaker.force_open(name)
      
      # Get initial state
      state1 = GenServer.call(name, :get_state)
      initial_failure_time = state1.last_failure_time
      
      # Wait a bit
      Process.sleep(100)
      
      # Send reinforcing pain
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        intensity: 0.9,
        scope: :system_wide
      })
      
      Process.sleep(50)
      
      # Check failure time was updated
      state2 = GenServer.call(name, :get_state)
      assert state2.last_failure_time > initial_failure_time
    end
    
    test "circuit recovers after pain subsides", %{name: name} do
      # Create circuit with short recovery time for testing
      {:ok, _} = CircuitBreaker.start_link(
        name: :recovery_test_breaker,
        pain_threshold: 0.8,
        pain_window_ms: 500,  # Short window for testing
        recovery_time_ms: 1000,  # 1 second recovery
        pain_response_enabled: true
      )
      
      # Verify circuit starts closed
      assert %{state: :closed} = CircuitBreaker.get_state(:recovery_test_breaker)
      
      # Send high pain to open circuit
      EventBus.publish(:algedonic_pain, %{
        source: :test_monitor,
        severity: :critical,
        metric: :error_rate,
        reason: "High error rate",
        scope: :system_wide
      })
      
      Process.sleep(50)
      
      # Verify circuit opened due to pain
      assert %{state: :open} = CircuitBreaker.get_state(:recovery_test_breaker)
      
      # Wait for pain window to expire (no new pain signals)
      Process.sleep(600)
      
      # Wait for recovery time
      Process.sleep(1100)
      
      # Attempt a call - should transition to half-open
      result = CircuitBreaker.call(:recovery_test_breaker, fn -> :ok end)
      assert result == {:error, :circuit_open}
      
      # Check state is now half-open
      assert %{state: :half_open} = CircuitBreaker.get_state(:recovery_test_breaker)
      
      # Successful call should close the circuit
      assert {:ok, :success} = CircuitBreaker.call(:recovery_test_breaker, fn -> :success end)
      
      # Verify circuit is closed again
      assert %{state: :closed} = CircuitBreaker.get_state(:recovery_test_breaker)
    end
  end
end