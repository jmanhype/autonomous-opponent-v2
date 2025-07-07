#!/usr/bin/env elixir

# Simple VSM startup test script
# This tests if the VSM subsystems can start without the full application

require Logger

defmodule VSMStartupTest do
  def run do
    Logger.info("Testing VSM subsystem startup...")
    
    # Start minimal dependencies
    Application.ensure_all_started(:logger)
    Application.ensure_all_started(:telemetry)
    
    # Start the EventBus first (required by VSM)
    Logger.info("Starting EventBus...")
    case AutonomousOpponentV2Core.EventBus.start_link(name: AutonomousOpponentV2Core.EventBus) do
      {:ok, _pid} -> Logger.info("✓ EventBus started")
      {:error, reason} -> Logger.error("✗ EventBus failed: #{inspect(reason)}")
    end
    
    # Start HLC for timestamps
    Logger.info("Starting Hybrid Logical Clock...")
    case AutonomousOpponentV2Core.Core.HybridLogicalClock.start_link([]) do
      {:ok, _pid} -> Logger.info("✓ HLC started")
      {:error, reason} -> Logger.error("✗ HLC failed: #{inspect(reason)}")
    end
    
    # Start Rate Limiter (required by S1)
    Logger.info("Starting Rate Limiter...")
    case AutonomousOpponentV2Core.Core.RateLimiter.start_link(
      name: AutonomousOpponentV2Core.Core.RateLimiter,
      max_tokens: 100,
      refill_rate: 10,
      refill_interval: 1000
    ) do
      {:ok, _pid} -> Logger.info("✓ Rate Limiter started")
      {:error, reason} -> Logger.error("✗ Rate Limiter failed: #{inspect(reason)}")
    end
    
    # Initialize Circuit Breaker (required by S1)
    Logger.info("Initializing Circuit Breaker...")
    AutonomousOpponentV2Core.Core.CircuitBreaker.init()
    AutonomousOpponentV2Core.Core.CircuitBreaker.register(:s1_circuit_breaker, 
      failure_threshold: 5,
      recovery_time_ms: 30_000,
      timeout_ms: 5_000
    )
    Logger.info("✓ Circuit Breaker initialized")
    
    # Register S1 rate limiter
    AutonomousOpponentV2Core.Core.RateLimiter.register(:s1_rate_limiter,
      max_tokens: 50,
      refill_rate: 10,
      refill_interval: 1000
    )
    
    # Now try to start the VSM Supervisor
    Logger.info("\nStarting VSM Supervisor...")
    case AutonomousOpponentV2Core.VSM.Supervisor.start_link([]) do
      {:ok, pid} -> 
        Logger.info("✓ VSM Supervisor started with PID: #{inspect(pid)}")
        
        # Wait for viability
        Process.sleep(3000)
        
        # Check subsystem status
        check_subsystems()
        
      {:error, reason} -> 
        Logger.error("✗ VSM Supervisor failed: #{inspect(reason)}")
    end
  end
  
  defp check_subsystems do
    Logger.info("\nChecking VSM subsystems...")
    
    subsystems = [
      {AutonomousOpponentV2Core.VSM.S1.Operations, "S1 Operations"},
      {AutonomousOpponentV2Core.VSM.S1ExternalOperations, "S1 External"},
      {AutonomousOpponentV2Core.VSM.S2.Coordination, "S2 Coordination"},
      {AutonomousOpponentV2Core.VSM.S3.Control, "S3 Control"},
      {AutonomousOpponentV2Core.VSM.S4.Intelligence, "S4 Intelligence"},
      {AutonomousOpponentV2Core.VSM.S5.Policy, "S5 Policy"},
      {AutonomousOpponentV2Core.VSM.Algedonic.Channel, "Algedonic Channel"}
    ]
    
    Enum.each(subsystems, fn {module, name} ->
      case Process.whereis(module) do
        nil ->
          Logger.error("✗ #{name} - NOT RUNNING")
          
        pid when is_pid(pid) ->
          if Process.alive?(pid) do
            Logger.info("✓ #{name} - Running (#{inspect(pid)})")
          else
            Logger.error("✗ #{name} - Process dead")
          end
      end
    end)
    
    # Check channels
    Logger.info("\nChecking VSM channels...")
    channel_types = [:s1_to_s2, :s2_to_s3, :s3_to_s4, :s4_to_s5, :s3_to_s1, :s5_to_all]
    
    Enum.each(channel_types, fn channel_type ->
      case Process.whereis(:"vsm_channel_#{channel_type}") do
        nil ->
          Logger.error("✗ Channel #{channel_type} - NOT ESTABLISHED")
          
        pid when is_pid(pid) ->
          Logger.info("✓ Channel #{channel_type} - Established (#{inspect(pid)})")
      end
    end)
  end
end

# Run the test
VSMStartupTest.run()

# Keep script alive to observe
Process.sleep(10000)