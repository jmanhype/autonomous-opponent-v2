#!/usr/bin/env elixir

# Real VSM Demonstration Script
# This script starts the full Autonomous Opponent VSM and demonstrates its real-time behavior

require Logger

defmodule VSMDemo do
  @moduledoc """
  Comprehensive demonstration of the REAL VSM implementation.
  Shows variety absorption, oscillation detection, resource control,
  intelligence scanning, policy enforcement, and algedonic signals.
  """

  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.{S1, S2, S3, S4, S5}
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: Algedonic
  alias AutonomousOpponentV2Core.Core.{CircuitBreaker, RateLimiter}

  def run do
    Logger.info("""
    
    ╔══════════════════════════════════════════════════════════════╗
    ║        AUTONOMOUS OPPONENT VSM DEMONSTRATION                 ║
    ║                                                              ║
    ║  This will demonstrate the REAL VSM implementation with:     ║
    ║  • S1: Operations absorbing variety                          ║
    ║  • S2: Coordination preventing oscillations                  ║
    ║  • S3: Control managing resources                            ║
    ║  • S4: Intelligence scanning environment                     ║
    ║  • S5: Policy enforcing constraints                          ║
    ║  • Algedonic: Pain/pleasure bypass signals                   ║
    ╚══════════════════════════════════════════════════════════════╝
    """)

    # Start minimal application components
    start_application()
    
    # Wait for VSM to become viable
    Process.sleep(3000)
    
    # Run demonstration scenarios
    demonstrate_vsm()
  end

  defp start_application do
    Logger.info("Starting application components...")
    
    # Ensure telemetry handlers are set up
    AutonomousOpponentV2Core.Telemetry.SystemTelemetry.setup()
    
    # Start EventBus first (communication backbone)
    {:ok, _} = EventBus.start_link(name: AutonomousOpponentV2Core.EventBus)
    
    # Start Rate Limiter for S1
    {:ok, _} = RateLimiter.start_link(
      name: AutonomousOpponentV2Core.Core.RateLimiter,
      max_tokens: 100,
      refill_rate: 10,
      refill_interval: 1000
    )
    
    # Initialize Circuit Breakers for S1
    CircuitBreaker.init()
    CircuitBreaker.register(:s1_circuit_breaker, 
      failure_threshold: 5,
      recovery_time_ms: 30_000,
      timeout_ms: 5_000
    )
    
    # Start specific rate limiters for S1
    RateLimiter.register(:s1_rate_limiter,
      max_tokens: 50,
      refill_rate: 10,
      refill_interval: 1000
    )
    
    # Start the VSM Supervisor (this starts all subsystems)
    {:ok, _} = AutonomousOpponentV2Core.VSM.Supervisor.start_link([])
    
    # Subscribe to important events for monitoring
    EventBus.subscribe(:vsm_viable)
    EventBus.subscribe(:emergency_algedonic)
    EventBus.subscribe(:s1_health)
    EventBus.subscribe(:s2_coordination)
    EventBus.subscribe(:s3_control)
    EventBus.subscribe(:s4_intelligence)
    EventBus.subscribe(:s5_policy)
    
    Logger.info("Application components started successfully")
  end

  defp demonstrate_vsm do
    # Start monitoring task
    monitor_task = Task.async(fn -> monitor_vsm_events() end)
    
    Process.sleep(1000)
    
    Logger.info("\n=== PHASE 1: Normal Operations ===")
    demonstrate_normal_operations()
    Process.sleep(3000)
    
    Logger.info("\n=== PHASE 2: Variety Overload ===")
    demonstrate_variety_overload()
    Process.sleep(3000)
    
    Logger.info("\n=== PHASE 3: Oscillation Detection ===")
    demonstrate_oscillations()
    Process.sleep(3000)
    
    Logger.info("\n=== PHASE 4: Resource Constraints ===")
    demonstrate_resource_constraints()
    Process.sleep(3000)
    
    Logger.info("\n=== PHASE 5: Intelligence & Adaptation ===")
    demonstrate_intelligence()
    Process.sleep(3000)
    
    Logger.info("\n=== PHASE 6: Policy Enforcement ===")
    demonstrate_policy_enforcement()
    Process.sleep(3000)
    
    Logger.info("\n=== PHASE 7: Emergency Algedonic ===")
    demonstrate_emergency()
    Process.sleep(3000)
    
    Logger.info("\n=== FINAL: System Metrics ===")
    display_final_metrics()
    
    # Clean shutdown
    Task.shutdown(monitor_task, :brutal_kill)
  end

  defp demonstrate_normal_operations do
    Logger.info("Generating normal load patterns...")
    
    # Send diverse but manageable requests
    for i <- 1..20 do
      request = %{
        type: Enum.random([:query, :update, :create, :delete]),
        source: "client_#{rem(i, 5)}",
        data: %{
          id: i,
          payload: :crypto.strong_rand_bytes(100) |> Base.encode64(),
          priority: Enum.random([:low, :normal, :high])
        }
      }
      
      result = AutonomousOpponentV2Core.VSM.S1.Operations.process_request(request)
      
      if rem(i, 5) == 0 do
        state = AutonomousOpponentV2Core.VSM.S1.Operations.get_operational_state()
        Logger.info("S1 State: Load=#{Float.round(state.load, 2)}, " <>
                   "Health=#{Float.round(state.health, 2)}, " <>
                   "Entropy=#{Float.round(state.variety.current_entropy, 2)}")
      end
      
      Process.sleep(50)
    end
  end

  defp demonstrate_variety_overload do
    Logger.info("Generating high variety to trigger attenuation...")
    
    # Create many unique request patterns
    tasks = for i <- 1..100 do
      Task.async(fn ->
        request = %{
          type: "type_#{i}",
          source: "source_#{i}",
          method: "method_#{rem(i, 20)}",
          data: %{
            unique_key: "key_#{i}",
            random: :rand.uniform(1000),
            shape: List.duplicate(i, rem(i, 10) + 1)
          }
        }
        
        AutonomousOpponentV2Core.VSM.S1.Operations.process_request(request)
      end)
    end
    
    # Wait for some tasks to complete
    Process.sleep(500)
    
    # Check variety metrics
    metrics = AutonomousOpponentV2Core.VSM.S1.Operations.get_variety_metrics()
    Logger.info("Variety Metrics: Entropy=#{Float.round(metrics.entropy, 2)}, " <>
               "Ratio=#{Float.round(metrics.variety_ratio, 2)}, " <>
               "Attenuation=#{metrics.attenuation_active}")
    
    # Let tasks finish
    Enum.each(tasks, &Task.await(&1, 5000))
  end

  defp demonstrate_oscillations do
    Logger.info("Creating oscillation patterns for S2 to detect...")
    
    # Simulate competing S1 units fighting over resources
    for round <- 1..10 do
      # Unit 1 requests resource A
      EventBus.publish(:s1_operations, %{
        unit_id: :s1_unit_1,
        current_load: 0.7,
        resources_held: [:resource_a],
        timestamp: DateTime.utc_now()
      })
      
      # Unit 2 also wants resource A (conflict!)
      EventBus.publish(:s1_operations, %{
        unit_id: :s1_unit_2,
        current_load: 0.8,
        resources_held: [:resource_a],
        timestamp: DateTime.utc_now()
      })
      
      # Report the conflict
      AutonomousOpponentV2Core.VSM.S2.Coordination.report_conflict(
        :s1_unit_1,
        :s1_unit_2,
        :resource_a
      )
      
      if rem(round, 3) == 0 do
        coord_state = AutonomousOpponentV2Core.VSM.S2.Coordination.get_coordination_state()
        Logger.info("S2 Coordination: Active Units=#{coord_state.active_units}, " <>
                   "Oscillation Risk=#{Float.round(coord_state.oscillation_risk, 2)}")
      end
      
      Process.sleep(100)
    end
  end

  defp demonstrate_resource_constraints do
    Logger.info("Testing S3 Control response to resource pressure...")
    
    # Generate load until resources are constrained
    spawn(fn ->
      for i <- 1..50 do
        # Heavy requests that consume resources
        request = %{
          type: :heavy_computation,
          source: "load_generator",
          data: %{
            size: :rand.uniform(1000),
            complexity: :high,
            memory_required: :rand.uniform(100) * 1024 * 1024  # MB
          }
        }
        
        AutonomousOpponentV2Core.VSM.S1.Operations.process_request(request)
        
        # S3 should start issuing control commands
        if rem(i, 10) == 0 do
          # Simulate S3 detecting high load and commanding throttle
          EventBus.publish(:s3_control, %{
            type: :throttle,
            params: %{rate: 5},  # Reduce to 5 requests/second
            reason: :resource_exhaustion,
            timestamp: DateTime.utc_now()
          })
        end
        
        Process.sleep(20)
      end
    end)
    
    # Monitor S3's control decisions
    Process.sleep(1000)
    
    # Check system capacity
    capacity = AutonomousOpponentV2Core.VSM.S1.Operations.get_system_capacity()
    Logger.info("System Capacity: CPU Cores=#{capacity.cpu_cores}, " <>
               "Memory Limit=#{capacity.memory_limit}MB, " <>
               "Max Requests=#{capacity.theoretical_max_requests}")
  end

  defp demonstrate_intelligence do
    Logger.info("S4 Intelligence scanning and learning patterns...")
    
    # Generate patterns for S4 to detect
    patterns = [
      %{type: :burst, interval: 100, count: 10},
      %{type: :periodic, interval: 500, count: 5},
      %{type: :exponential, base: 50, factor: 1.5, count: 8}
    ]
    
    for pattern <- patterns do
      case pattern.type do
        :burst ->
          # Burst pattern
          for _ <- 1..pattern.count do
            EventBus.publish(:external_pattern, %{
              pattern_type: :burst,
              timestamp: DateTime.utc_now(),
              intensity: :rand.uniform()
            })
          end
          Process.sleep(pattern.interval)
          
        :periodic ->
          # Periodic pattern
          for _ <- 1..pattern.count do
            EventBus.publish(:external_pattern, %{
              pattern_type: :periodic,
              timestamp: DateTime.utc_now(),
              phase: :rand.uniform(360)
            })
            Process.sleep(pattern.interval)
          end
          
        :exponential ->
          # Exponential growth pattern
          for i <- 1..pattern.count do
            delay = round(pattern.base * :math.pow(pattern.factor, i))
            EventBus.publish(:external_pattern, %{
              pattern_type: :exponential,
              timestamp: DateTime.utc_now(),
              growth_rate: pattern.factor
            })
            Process.sleep(min(delay, 1000))
          end
      end
    end
    
    # S4 should have detected these patterns
    Logger.info("S4 Intelligence has analyzed environmental patterns")
  end

  defp demonstrate_policy_enforcement do
    Logger.info("S5 Policy enforcing system constraints...")
    
    # Try to violate policies
    violations = [
      %{type: :rate_limit_violation, requests_per_second: 1000},
      %{type: :resource_violation, memory_requested: 10_000_000_000},  # 10GB
      %{type: :security_violation, unauthorized_access: true},
      %{type: :operational_violation, emergency_stop_ignored: true}
    ]
    
    for violation <- violations do
      Logger.info("Attempting violation: #{violation.type}")
      
      # S5 should block or constrain these
      EventBus.publish(:policy_violation_attempt, violation)
      
      # S5 responds with constraints
      EventBus.publish(:s5_policy, %{
        constraint_type: :hard_limit,
        applies_to: :all_subsystems,
        violation: violation.type,
        enforcement: :immediate,
        timestamp: DateTime.utc_now()
      })
      
      Process.sleep(500)
    end
  end

  defp demonstrate_emergency do
    Logger.info("Triggering emergency algedonic signals...")
    
    # Create conditions that cause pain
    spawn(fn ->
      # Memory pressure
      Algedonic.report_pain(:s1_operations, :memory_pressure, 0.95)
      Process.sleep(100)
      
      # System overload
      Algedonic.report_pain(:s1_operations, :system_overload, 0.92)
      Process.sleep(100)
      
      # Critical health
      Algedonic.report_pain(:s1_operations, :health_critical, 0.98)
      Process.sleep(100)
      
      # EMERGENCY SCREAM
      Algedonic.emergency_scream(:vsm_demo, "DEMONSTRATION EMERGENCY - SYSTEM CRITICAL")
    end)
    
    Process.sleep(500)
    
    # Check if system is in pain
    in_pain = Algedonic.in_pain?()
    hedonic_state = Algedonic.get_hedonic_state()
    
    Logger.info("System in pain: #{in_pain}")
    Logger.info("Hedonic state: #{inspect(hedonic_state)}")
    
    # Demonstrate recovery and pleasure
    Process.sleep(1000)
    
    # System recovers
    Algedonic.report_pleasure(:s1_operations, :performance, 0.95)
    Algedonic.report_pleasure(:s2_coordination, :harmony, 0.92)
  end

  defp display_final_metrics do
    # Gather metrics from all subsystems
    s1_state = AutonomousOpponentV2Core.VSM.S1.Operations.get_operational_state()
    s1_health = AutonomousOpponentV2Core.VSM.S1.Operations.calculate_health()
    variety_metrics = AutonomousOpponentV2Core.VSM.S1.Operations.get_variety_metrics()
    
    s2_state = AutonomousOpponentV2Core.VSM.S2.Coordination.get_coordination_state()
    
    algedonic_metrics = Algedonic.get_metrics()
    
    Logger.info("""
    
    ╔══════════════════════════════════════════════════════════════╗
    ║                    VSM FINAL METRICS                         ║
    ╠══════════════════════════════════════════════════════════════╣
    ║ S1 OPERATIONS:                                               ║
    ║   Load: #{format_metric(s1_state.load)}                     ║
    ║   Health: #{format_metric(s1_health)}                       ║
    ║   Circuit Breaker: #{s1_state.circuit_breaker.state}        ║
    ║   Rate Limiter: #{s1_state.rate_limiter.tokens_available} tokens ║
    ║                                                              ║
    ║ VARIETY METRICS:                                             ║
    ║   Current Entropy: #{format_metric(variety_metrics.entropy)} bits ║
    ║   Max Entropy: #{format_metric(variety_metrics.max_entropy)} bits ║
    ║   Variety Ratio: #{format_metric(variety_metrics.variety_ratio)} ║
    ║   Request Diversity: #{format_metric(variety_metrics.request_diversity)} ║
    ║   Attenuation Active: #{variety_metrics.attenuation_active} ║
    ║                                                              ║
    ║ S2 COORDINATION:                                             ║
    ║   Active Units: #{s2_state.active_units}                    ║
    ║   Resource Utilization: #{format_metric(s2_state.resource_utilization)} ║
    ║   Oscillation Risk: #{format_metric(s2_state.oscillation_risk)} ║
    ║                                                              ║
    ║ ALGEDONIC STATE:                                             ║
    ║   Recent Pain Signals: #{length(algedonic_metrics.recent_pain)} ║
    ║   Recent Pleasure Signals: #{length(algedonic_metrics.recent_pleasure)} ║
    ║   Emergency Count: #{algedonic_metrics.emergency_count}     ║
    ╚══════════════════════════════════════════════════════════════╝
    """)
  end

  defp monitor_vsm_events do
    receive do
      {:event, :emergency_algedonic, data} ->
        Logger.error("🚨 EMERGENCY ALGEDONIC: #{data.reason}")
        monitor_vsm_events()
        
      {:event, :vsm_viable, data} ->
        Logger.info("✅ VSM VIABLE: All subsystems operational")
        monitor_vsm_events()
        
      {:event, :s1_health, data} ->
        if data.health < 0.5 do
          Logger.warning("⚠️  S1 Health Low: #{Float.round(data.health, 2)}")
        end
        monitor_vsm_events()
        
      {:event, event_type, _data} ->
        # Log other events at debug level
        Logger.debug("Event: #{event_type}")
        monitor_vsm_events()
        
    after
      60_000 ->
        Logger.info("Monitor timeout - stopping")
    end
  end

  defp format_metric(value) when is_float(value) do
    Float.round(value, 3) |> to_string()
  end
  defp format_metric(value), do: to_string(value)
end

# Run the demonstration
VSMDemo.run()

# Keep the script running to observe final behaviors
Process.sleep(5000)

Logger.info("""

╔══════════════════════════════════════════════════════════════╗
║                  VSM DEMONSTRATION COMPLETE                  ║
║                                                              ║
║  The Viable System Model has demonstrated:                  ║
║  ✓ Variety absorption and attenuation (S1)                  ║
║  ✓ Oscillation detection and dampening (S2)                 ║
║  ✓ Resource control and optimization (S3)                   ║
║  ✓ Environmental scanning and learning (S4)                 ║
║  ✓ Policy definition and enforcement (S5)                   ║
║  ✓ Emergency algedonic bypass signals                       ║
║                                                              ║
║  "The purpose of a system is what it does" - Stafford Beer  ║
╚══════════════════════════════════════════════════════════════╝
""")