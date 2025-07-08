#!/usr/bin/env elixir

# Simple test script to verify VSM metrics endpoints are working

IO.puts("=== Testing VSM Metrics Endpoints ===\n")

# Test that we can call the controller's private function
# We'll simulate what the controller does

alias AutonomousOpponentV2Core.VSM.{S1, S2, S3}

defmodule TestHelper do
  def get_variety_metric(subsystem) do
    # Map short names to full module names
    full_module = case subsystem do
      S1 -> AutonomousOpponentV2Core.VSM.S1.Operations
      S2 -> AutonomousOpponentV2Core.VSM.S2.Coordination  
      S3 -> AutonomousOpponentV2Core.VSM.S3.Control
      _ -> subsystem
    end
    
    case GenServer.whereis(full_module) do
      nil -> 
        IO.puts("#{inspect(full_module)} is not running")
        0
      pid when is_pid(pid) ->
        try do
          # S1 has specific variety metrics endpoint
          if full_module == AutonomousOpponentV2Core.VSM.S1.Operations do
            metrics = GenServer.call(full_module, :get_variety_metrics, 5_000)
            value = metrics.variety_ratio * 100  # Convert to percentage for consistency
            IO.puts("S1 variety ratio: #{value}%")
            value
          else
            # S2 and S3 don't have variety metrics, use state instead
            state = GenServer.call(full_module, :get_state, 5_000)
            # Extract variety from state if available, otherwise return a default
            value = case full_module do
              AutonomousOpponentV2Core.VSM.S2.Coordination ->
                # S2 tracks coordination events
                Map.get(state, :events_coordinated, 0) / 10.0
              AutonomousOpponentV2Core.VSM.S3.Control ->
                # S3 tracks control commands
                Map.get(state, :commands_issued, 0) / 10.0
              _ ->
                0
            end
            IO.puts("#{inspect(subsystem)} variety metric: #{value}")
            value
          end
        catch
          error -> 
            IO.puts("Error calling #{inspect(full_module)}: #{inspect(error)}")
            0
        end
    end
  end
end

# Test each subsystem
IO.puts("Testing S1 variety metric:")
TestHelper.get_variety_metric(S1)

IO.puts("\nTesting S2 variety metric:")
TestHelper.get_variety_metric(S2)

IO.puts("\nTesting S3 variety metric:")
TestHelper.get_variety_metric(S3)

IO.puts("\n=== Test Complete ===")