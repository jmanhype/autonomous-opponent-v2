defmodule AutonomousOpponentV2Core.AMCP.Goldrush.VSMPatternExamples do
  @moduledoc """
  Examples demonstrating how to use the VSM Pattern Library for detecting
  various failure modes in the Autonomous Opponent system.
  
  This module provides practical examples of:
  - Pattern detection in action
  - Event simulation for each pattern type
  - Integration with the VSM subsystems
  - Algedonic response handling
  """
  
  alias AutonomousOpponentV2Core.AMCP.Goldrush.{PatternRegistry, VSMPatternLibrary}
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Clock
  require Logger
  
  # ============================================================================
  # CYBERNETIC PATTERN EXAMPLES
  # ============================================================================
  
  @doc """
  Simulates a variety overflow condition where S1 operations are overwhelmed.
  
  This is the most critical VSM failure mode - when environmental variety
  exceeds the system's ability to absorb it.
  """
  def simulate_variety_overflow do
    Logger.info("Simulating variety overflow condition...")
    
    # Generate high-variety events
    for i <- 1..100 do
      event = %{
        type: :s1_operations,
        event_id: "overflow_#{i}",
        variety_ratio: 1.5 + (i * 0.01),  # Increasing variety
        s1_variety_buffer: 800 + (i * 5),  # Buffer filling up
        processing_latency: 500 + (i * 10),  # Increasing latency
        message_queue_length: 5_000 + (i * 100),  # Queue growing
        timestamp: Clock.now()
      }
      
      # This would trigger pattern detection
      EventBus.publish(:vsm_events, event)
      
      # Small delay to simulate time progression
      Process.sleep(10)
    end
    
    Logger.info("Variety overflow simulation complete - check algedonic signals!")
  end
  
  @doc """
  Simulates control loop oscillation in S3.
  
  This occurs when control adjustments create unstable feedback loops,
  causing the system to oscillate between states.
  """
  def simulate_control_oscillation do
    Logger.info("Simulating control loop oscillation...")
    
    # Generate oscillating control values
    base_value = 50.0
    amplitude = 30.0
    frequency = 0.6  # Hz
    
    for i <- 1..60 do
      # Calculate oscillating value
      time = i / 10.0  # 0.1 second intervals
      oscillating_value = base_value + amplitude * :math.sin(2 * :math.pi * frequency * time)
      
      event = %{
        type: :s3_control,
        control_parameter: :resource_allocation,
        current_value: oscillating_value,
        setpoint: base_value,
        frequency: frequency,
        amplitude: amplitude / base_value,
        control_changes_per_minute: 12,
        timestamp: Clock.now()
      }
      
      EventBus.publish(:vsm_events, event)
      Process.sleep(100)  # 100ms between updates
    end
    
    Logger.info("Control oscillation simulation complete")
  end
  
  @doc """
  Simulates a metasystemic cascade failure.
  
  This catastrophic failure propagates upward through the VSM hierarchy,
  starting from S1 and cascading through S2, S3, S4, to S5.
  """
  def simulate_metasystemic_cascade do
    Logger.info("Simulating metasystemic cascade failure...")
    
    # Stage 1: S1 failure
    EventBus.publish(:vsm_events, %{
      type: :subsystem_failure,
      subsystem: :s1,
      failure_rate: 0.75,
      operations_affected: 150,
      timestamp: Clock.now()
    })
    
    Process.sleep(1000)
    
    # Stage 2: S2 fails due to S1
    EventBus.publish(:vsm_events, %{
      type: :subsystem_failure,
      subsystem: :s2,
      failure_rate: 0.72,
      cause: :s1_overload,
      coordination_lost: true,
      timestamp: Clock.now()
    })
    
    Process.sleep(500)
    
    # Stage 3: S3 fails due to S2
    EventBus.publish(:vsm_events, %{
      type: :subsystem_failure,
      subsystem: :s3,
      failure_rate: 0.70,
      cause: :s2_coordination_loss,
      control_compromised: true,
      timestamp: Clock.now()
    })
    
    Logger.info("CASCADE ALERT: System-wide failure imminent!")
  end
  
  # ============================================================================
  # INTEGRATION PATTERN EXAMPLES
  # ============================================================================
  
  @doc """
  Simulates EventBus message overflow affecting VSM.
  
  This occurs when V1 EventBus publishes events faster than VSM can process.
  """
  def simulate_eventbus_overflow do
    Logger.info("Simulating EventBus → VSM overflow...")
    
    # Burst of events from EventBus
    Task.async(fn ->
      for i <- 1..2000 do
        EventBus.publish(:high_frequency_events, %{
          id: i,
          type: :sensor_reading,
          value: :rand.uniform(100),
          timestamp: Clock.now()
        })
        
        # Very small delay to create sustained high rate
        if rem(i, 100) == 0, do: Process.sleep(1)
      end
    end)
    
    # Monitor S1 buffer
    for _ <- 1..10 do
      Process.sleep(100)
      
      event = %{
        type: :v1_integration,
        component: :event_bus,
        eventbus_publish_rate: 1500,
        s1_buffer_utilization: 0.85 + :rand.uniform() * 0.1,
        process_mailbox_size: 8_000 + :rand.uniform(4_000),
        timestamp: Clock.now()
      }
      
      EventBus.publish(:vsm_events, event)
    end
    
    Logger.info("EventBus overflow simulation complete")
  end
  
  @doc """
  Simulates CircuitBreaker pain feedback loop.
  
  This occurs when circuit breaker trips generate pain signals that
  cause more load, leading to more trips.
  """
  def simulate_circuit_breaker_pain_loop do
    Logger.info("Simulating CircuitBreaker pain feedback loop...")
    
    for cycle <- 1..5 do
      # Circuit opens due to failures
      EventBus.publish(:vsm_events, %{
        type: :circuit_breaker_event,
        action: :opened,
        circuit: :api_endpoint,
        failure_count: 10 + cycle * 2,
        pain_triggered: true,
        timestamp: Clock.now()
      })
      
      Process.sleep(200)
      
      # Pain signal generated
      EventBus.publish(:algedonic_signals, %{
        type: :pain,
        source: :circuit_breaker,
        intensity: 0.8 + cycle * 0.02,
        trigger: :circuit_open,
        timestamp: Clock.now()
      })
      
      Process.sleep(200)
      
      # System responds with more load (attempting recovery)
      EventBus.publish(:vsm_events, %{
        type: :system_response,
        action: :increase_load,
        reason: :pain_response,
        additional_requests: 50 * cycle,
        timestamp: Clock.now()
      })
      
      Process.sleep(500)
    end
    
    Logger.info("Circuit breaker pain loop simulation complete")
  end
  
  # ============================================================================
  # TECHNICAL PATTERN EXAMPLES
  # ============================================================================
  
  @doc """
  Simulates GenServer mailbox overflow.
  
  This Elixir-specific pattern occurs when a process receives messages
  faster than it can process them.
  """
  def simulate_genserver_overflow do
    Logger.info("Simulating GenServer mailbox overflow...")
    
    # Create a slow processor
    {:ok, slow_process} = GenServer.start_link(__MODULE__, :slow_processor)
    
    # Flood it with messages
    Task.async(fn ->
      for i <- 1..20_000 do
        GenServer.cast(slow_process, {:process, i})
      end
    end)
    
    # Monitor the process
    for _ <- 1..10 do
      Process.sleep(500)
      
      info = Process.info(slow_process, [:message_queue_len, :memory])
      
      event = %{
        type: :technical_monitoring,
        process: :s1_operations,
        message_queue_len: info[:message_queue_len],
        process_memory: info[:memory],
        memory_mb: info[:memory] / 1_048_576,
        timestamp: Clock.now()
      }
      
      EventBus.publish(:vsm_events, event)
      
      if info[:message_queue_len] > 10_000 do
        Logger.warning("CRITICAL: Process mailbox overflow detected!")
      end
    end
    
    GenServer.stop(slow_process)
    Logger.info("GenServer overflow simulation complete")
  end
  
  # ============================================================================
  # DISTRIBUTED PATTERN EXAMPLES
  # ============================================================================
  
  @doc """
  Simulates CRDT divergence during network partition.
  
  This distributed pattern occurs when CRDT nodes cannot sync due to
  network issues, causing state divergence.
  """
  def simulate_crdt_divergence do
    Logger.info("Simulating CRDT divergence...")
    
    # Simulate nodes diverging
    for minute <- 1..5 do
      for node <- [:node1, :node2, :node3] do
        event = %{
          type: :distributed_monitoring,
          pattern: :crdt_sync,
          node: node,
          sync_failures: minute * 2,
          vector_clock_drift: minute * 15,  # seconds
          merge_conflicts: minute * 5,
          last_successful_sync: "#{minute * 30}s ago",
          timestamp: Clock.now()
        }
        
        EventBus.publish(:vsm_events, event)
      end
      
      Process.sleep(1000)
    end
    
    Logger.info("CRDT divergence simulation complete")
  end
  
  @doc """
  Simulates distributed algedonic storm.
  
  This occurs when pain signals cascade across distributed nodes,
  overwhelming the algedonic channels.
  """
  def simulate_algedonic_storm do
    Logger.info("Simulating distributed algedonic storm...")
    
    nodes = [:alpha, :beta, :gamma, :delta]
    
    # Initial pain signal
    EventBus.publish(:algedonic_signals, %{
      type: :pain,
      source: :alpha,
      intensity: 0.9,
      reason: :critical_failure,
      timestamp: Clock.now()
    })
    
    # Storm propagation
    for round <- 1..10 do
      pain_rate = 20 * round  # Escalating rate
      
      for node <- nodes do
        for _ <- 1..pain_rate do
          EventBus.publish(:algedonic_signals, %{
            type: :pain,
            source: node,
            intensity: 0.7 + :rand.uniform() * 0.3,
            propagated_from: Enum.random(nodes),
            storm_round: round,
            timestamp: Clock.now()
          })
        end
      end
      
      # Monitor storm intensity
      event = %{
        type: :distributed_monitoring,
        pattern: :algedonic_storm,
        pain_signal_rate: pain_rate * length(nodes),
        affected_nodes: nodes,
        cascade_risk: :extreme,
        timestamp: Clock.now()
      }
      
      EventBus.publish(:vsm_events, event)
      Process.sleep(100)
    end
    
    Logger.info("Algedonic storm simulation complete - emergency protocols should be active!")
  end
  
  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================
  
  @doc """
  Runs all pattern simulations with delays between each.
  """
  def run_all_simulations do
    simulations = [
      &simulate_variety_overflow/0,
      &simulate_control_oscillation/0,
      &simulate_metasystemic_cascade/0,
      &simulate_eventbus_overflow/0,
      &simulate_circuit_breaker_pain_loop/0,
      &simulate_genserver_overflow/0,
      &simulate_crdt_divergence/0,
      &simulate_algedonic_storm/0
    ]
    
    Logger.info("Starting comprehensive VSM pattern simulation suite...")
    
    for {simulation, index} <- Enum.with_index(simulations, 1) do
      Logger.info("Running simulation #{index} of #{length(simulations)}")
      simulation.()
      Process.sleep(3000)  # 3 second pause between simulations
    end
    
    Logger.info("All simulations complete!")
  end
  
  @doc """
  Monitors pattern detection results in real-time.
  """
  def monitor_patterns(duration_seconds \\ 60) do
    Logger.info("Monitoring VSM patterns for #{duration_seconds} seconds...")
    
    # Subscribe to pattern detection events
    EventBus.subscribe(:pattern_matches)
    
    end_time = System.os_time(:second) + duration_seconds
    
    monitor_loop(end_time)
  end
  
  defp monitor_loop(end_time) do
    if System.os_time(:second) < end_time do
      receive do
        {:event_bus, %{type: :pattern_match} = match} ->
          Logger.info("PATTERN DETECTED: #{inspect(match)}")
          
        {:event_bus, %{type: :algedonic_signal} = signal} ->
          Logger.warning("ALGEDONIC SIGNAL: #{inspect(signal)}")
          
        _ ->
          :ok
      after
        1000 ->
          :ok
      end
      
      monitor_loop(end_time)
    else
      Logger.info("Monitoring complete")
    end
  end
  
  # GenServer callbacks for slow processor simulation
  def init(:slow_processor) do
    {:ok, %{processed: 0}}
  end
  
  def handle_cast({:process, _item}, state) do
    # Simulate slow processing
    Process.sleep(10)
    {:noreply, %{state | processed: state.processed + 1}}
  end
end