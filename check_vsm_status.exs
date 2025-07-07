#!/usr/bin/env elixir

# Check if VSM subsystems are currently running

require Logger

defmodule VSMStatusChecker do
  def check do
    Logger.info("Checking VSM subsystem status...")
    
    subsystems = [
      {AutonomousOpponentV2Core.VSM.S1.Operations, "S1 Operations"},
      {AutonomousOpponentV2Core.VSM.S1ExternalOperations, "S1 External"},
      {AutonomousOpponentV2Core.VSM.S2.Coordination, "S2 Coordination"},
      {AutonomousOpponentV2Core.VSM.S3.Control, "S3 Control"},
      {AutonomousOpponentV2Core.VSM.S4.Intelligence, "S4 Intelligence"},
      {AutonomousOpponentV2Core.VSM.S5.Policy, "S5 Policy"},
      {AutonomousOpponentV2Core.VSM.Algedonic.Channel, "Algedonic Channel"},
      {AutonomousOpponentV2Core.EventBus, "EventBus"},
      {AutonomousOpponentV2Core.Core.HybridLogicalClock, "HLC"},
      {AutonomousOpponentV2Core.Core.RateLimiter, "Rate Limiter"}
    ]
    
    running_count = 0
    total_count = length(subsystems)
    
    Logger.info("\n=== VSM Subsystem Status ===")
    Enum.each(subsystems, fn {module, name} ->
      case Process.whereis(module) do
        nil ->
          Logger.error("✗ #{name} - NOT RUNNING")
          
        pid when is_pid(pid) ->
          if Process.alive?(pid) do
            Logger.info("✓ #{name} - Running (PID: #{inspect(pid)})")
            running_count = running_count + 1
          else
            Logger.error("✗ #{name} - Process dead")
          end
      end
    end)
    
    # Check channels
    Logger.info("\n=== VSM Channel Status ===")
    channel_types = [:s1_to_s2, :s2_to_s3, :s3_to_s4, :s4_to_s5, :s3_to_s1, :s5_to_all]
    
    channel_count = 0
    Enum.each(channel_types, fn channel_type ->
      case Process.whereis(:"vsm_channel_#{channel_type}") do
        nil ->
          Logger.error("✗ Channel #{channel_type} - NOT ESTABLISHED")
          
        pid when is_pid(pid) ->
          Logger.info("✓ Channel #{channel_type} - Established (PID: #{inspect(pid)})")
          channel_count = channel_count + 1
      end
    end)
    
    # Try to interact with VSM
    Logger.info("\n=== Testing VSM Interaction ===")
    
    # Try to get S1 operational state
    try do
      state = AutonomousOpponentV2Core.VSM.S1.Operations.get_operational_state()
      Logger.info("✓ S1 Operational State retrieved:")
      Logger.info("  Load: #{Float.round(state.load, 2)}")
      Logger.info("  Health: #{Float.round(state.health, 2)}")
      Logger.info("  Processed: #{state.processed_count} requests")
    rescue
      e ->
        Logger.error("✗ Failed to get S1 state: #{inspect(e)}")
    end
    
    # Try to get S2 coordination state
    try do
      state = AutonomousOpponentV2Core.VSM.S2.Coordination.get_coordination_state()
      Logger.info("✓ S2 Coordination State retrieved:")
      Logger.info("  Active Units: #{state.active_units}")
      Logger.info("  Resource Utilization: #{Float.round(state.resource_utilization, 2)}")
      Logger.info("  Oscillation Risk: #{Float.round(state.oscillation_risk, 2)}")
    rescue
      e ->
        Logger.error("✗ Failed to get S2 state: #{inspect(e)}")
    end
    
    # Try to get Algedonic state
    try do
      state = AutonomousOpponentV2Core.VSM.Algedonic.Channel.get_hedonic_state()
      Logger.info("✓ Algedonic State retrieved:")
      Logger.info("  Current Balance: #{Float.round(state.current_balance, 2)}")
      Logger.info("  In Pain: #{state.in_pain}")
      Logger.info("  In Pleasure: #{state.in_pleasure}")
    rescue
      e ->
        Logger.error("✗ Failed to get Algedonic state: #{inspect(e)}")
    end
    
    Logger.info("\n=== Summary ===")
    Logger.info("VSM appears to be #{if running_count > 5, do: "OPERATIONAL", else: "NOT OPERATIONAL"}")
    Logger.info("Subsystems running: #{running_count}/#{total_count}")
    Logger.info("Channels established: #{channel_count}/#{length(channel_types)}")
  end
end

VSMStatusChecker.check()