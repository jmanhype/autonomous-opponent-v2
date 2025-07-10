defmodule AutonomousOpponentV2Core.Integration.AlgedonicCircuitIntegrationTest do
  @moduledoc """
  FULL VSM ALGEDONIC INTEGRATION TESTS
  
  These tests verify the complete cybernetic feedback loop:
  Health Monitor → Algedonic Channel → Circuit Breaker → System Protection
  
  This is Beer's vision made real - a system that feels pain and responds
  with protective reflexes, creating true organizational consciousness.
  """
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: AlgedonicChannel
  
  setup do
    # Start the full VSM stack
    start_supervised!(EventBus)
    
    # Start algedonic channel
    {:ok, algedonic_pid} = start_supervised({
      AlgedonicChannel,
      name: :test_algedonic, 
      vsm_name: :test_vsm
    })
    
    # Start multiple circuit breakers for cascade testing
    breakers = for name <- [:api_breaker, :db_breaker, :cache_breaker] do
      {:ok, _} = CircuitBreaker.start_link(
        name: name,
        pain_threshold: 0.8,
        pain_window_ms: 2000,
        failure_threshold: 5
      )
      name
    end
    
    %{
      algedonic_pid: algedonic_pid,
      breakers: breakers
    }
  end
  
  describe "end-to-end pain flow" do
    test "health monitor pain triggers circuit breaker protection", %{breakers: breakers} do
      # Simulate health monitor detecting critical issue
      pain_signal = %{
        source: :health_monitor,
        severity: :critical,
        metric: :database_latency,
        value: 5000,  # 5 second latency!
        threshold: 500,
        message: "Database response time critical",
        scope: :system_wide
      }
      
      # Health monitor would publish this
      EventBus.publish(:algedonic_pain, pain_signal)
      
      # Allow propagation
      Process.sleep(100)
      
      # At least one breaker should respond
      states = for name <- breakers do
        CircuitBreaker.get_state(name).state
      end
      
      open_count = Enum.count(states, & &1 == :open)
      assert open_count >= 1, "No circuit breakers responded to critical pain"
    end
    
    test "algedonic channel emergency scream forces all breakers open" do
      # Trigger emergency scream
      AlgedonicChannel.emergency_scream(:test_algedonic, "TOTAL SYSTEM COLLAPSE IMMINENT")
      
      # Brief delay for propagation
      Process.sleep(100)
      
      # ALL breakers should be open
      all_open? = [:api_breaker, :db_breaker, :cache_breaker]
        |> Enum.all?(fn name ->
          CircuitBreaker.get_state(name).state == :open
        end)
      
      assert all_open?, "Emergency scream did not open all circuit breakers"
    end
  end
  
  describe "cascade prevention" do
    test "circuit breaker pain prevents cascading failures", %{breakers: _breakers} do
      # Subscribe to events
      EventBus.subscribe(:circuit_breaker_opened)
      EventBus.subscribe(:algedonic_pain)
      
      # Force one breaker to fail
      CircuitBreaker.force_open(:api_breaker)
      
      # This should generate pain signal
      assert_receive {:event_bus, :algedonic_pain, pain_data}, 500
      assert pain_data.source == :circuit_breaker
      assert pain_data.name == :api_breaker
      
      # Other breakers should see this pain but not cascade
      Process.sleep(100)
      
      # Check that not ALL breakers opened
      closed_count = [:db_breaker, :cache_breaker]
        |> Enum.count(fn name ->
          CircuitBreaker.get_state(name).state == :closed
        end)
      
      assert closed_count >= 1, "Cascade prevention failed - all breakers opened"
    end
  end
  
  describe "pain-based learning" do
    test "repeated pain patterns increase circuit sensitivity" do
      # Create a breaker
      {:ok, _} = CircuitBreaker.start_link(
        name: :learning_breaker,
        pain_threshold: 0.8,
        pain_window_ms: 5000
      )
      
      # Send pattern: pain followed by actual failure
      for _round <- 1..3 do
        # Pain signal
        EventBus.publish(:algedonic_pain, %{
          source: :predictive_monitor,
          intensity: 0.7,  # Below threshold
          metric: :pre_failure_indicator,
          scope: :system_wide
        })
        
        Process.sleep(100)
        
        # Actual failure
        CircuitBreaker.record_failure(:learning_breaker)
        
        Process.sleep(200)
      end
      
      # Now send just the pain signal
      EventBus.publish(:algedonic_pain, %{
        source: :predictive_monitor,
        intensity: 0.7,  # Still below threshold
        metric: :pre_failure_indicator,
        scope: :system_wide
      })
      
      Process.sleep(100)
      
      # Get learning metrics
      state = GenServer.call(:learning_breaker, :get_state)
      
      # Correlation strength should have increased
      assert state.pain_learning_data.correlation_strength > 0.5
    end
  end
  
  describe "multi-modal pain response" do
    test "circuit breaker integrates multiple pain sources" do
      {:ok, _} = CircuitBreaker.start_link(
        name: :multimodal_breaker,
        pain_threshold: 0.8,
        pain_window_ms: 2000
      )
      
      # Pain from different sources
      pain_sources = [
        %{source: :cpu_monitor, intensity: 0.4, metric: :cpu_usage},
        %{source: :memory_monitor, intensity: 0.3, metric: :memory_pressure},
        %{source: :network_monitor, intensity: 0.5, metric: :packet_loss},
        %{source: :disk_monitor, intensity: 0.4, metric: :io_wait}
      ]
      
      # Send all pain signals
      for pain <- pain_sources do
        EventBus.publish(:algedonic_pain, Map.put(pain, :scope, :system_wide))
        Process.sleep(20)
      end
      
      Process.sleep(100)
      
      # Combined pain should trigger opening
      state = CircuitBreaker.get_state(:multimodal_breaker)
      assert state.state == :open, "Multi-modal pain integration failed"
    end
  end
  
  describe "recovery and pleasure signals" do
    test "circuit breaker recovery generates pleasure signals" do
      {:ok, _} = CircuitBreaker.start_link(
        name: :recovery_breaker,
        recovery_time_ms: 100  # Fast recovery for testing
      )
      
      # Subscribe to pleasure signals
      EventBus.subscribe(:algedonic_pleasure)
      
      # Force failures to open
      for _ <- 1..5 do
        CircuitBreaker.call(:recovery_breaker, fn -> {:error, :induced_failure} end)
      end
      
      # Should be open
      assert %{state: :open} = CircuitBreaker.get_state(:recovery_breaker)
      
      # Wait for recovery attempt
      Process.sleep(150)
      
      # Successful call during half-open
      CircuitBreaker.call(:recovery_breaker, fn -> :ok end)
      
      # Should receive pleasure signal
      assert_receive {:event_bus, :algedonic_pleasure, pleasure_data}, 500
      assert pleasure_data.source == :circuit_breaker
      assert pleasure_data.reason == :service_recovered
    end
  end
  
  describe "system-wide pain coordination" do
    test "S5 policy can force all breakers open via pain" do
      # Simulate S5 policy decision
      EventBus.publish(:algedonic_pain, %{
        source: :s5_policy,
        severity: :critical,
        reason: "Policy violation detected - emergency shutdown",
        scope: :system_wide,
        policy_override: true
      })
      
      Process.sleep(100)
      
      # All breakers should respond to S5
      all_open? = [:api_breaker, :db_breaker, :cache_breaker]
        |> Enum.all?(fn name ->
          CircuitBreaker.get_state(name).state == :open
        end)
      
      assert all_open?, "S5 policy pain did not trigger system-wide protection"
    end
  end
  
  describe "pain signal validation" do
    test "malformed pain signals are handled gracefully" do
      {:ok, _} = CircuitBreaker.start_link(
        name: :robust_breaker,
        pain_threshold: 0.8
      )
      
      # Send various malformed signals
      malformed_signals = [
        nil,
        %{},  # Empty map
        %{source: nil, severity: :invalid},
        %{intensity: "not_a_number"},
        %{severity: :unknown_level}
      ]
      
      for signal <- malformed_signals do
        EventBus.publish(:algedonic_pain, signal)
      end
      
      Process.sleep(100)
      
      # Breaker should still be functional
      assert %{state: :closed} = CircuitBreaker.get_state(:robust_breaker)
      
      # And should still respond to valid pain
      EventBus.publish(:algedonic_pain, %{
        source: :test,
        severity: :critical,
        scope: :system_wide
      })
      
      Process.sleep(50)
      
      assert %{state: :open} = CircuitBreaker.get_state(:robust_breaker)
    end
  end
end