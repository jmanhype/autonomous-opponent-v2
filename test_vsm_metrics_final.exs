#!/usr/bin/env elixir

# Test VSM metrics endpoints are now working correctly

# Compile the changes first
IO.puts("Compiling changes...")
System.cmd("mix", ["compile"], into: IO.stream(:stdio, :line))

IO.puts("\n=== Testing VSM Metrics Endpoints ===\n")

# Function to safely test a GenServer call
defmodule MetricsTest do
  def test_metrics(module_name, module_atom) do
    IO.puts("Testing #{module_name}:")
    
    case Process.whereis(module_atom) do
      nil ->
        IO.puts("  ✗ #{module_name} is not running")
        
      pid when is_pid(pid) ->
        try do
          # Test :get_metrics call
          metrics = GenServer.call(module_atom, :get_metrics, 5_000)
          IO.puts("  ✓ :get_metrics returned: #{inspect(metrics)}")
          
          # Check if variety_absorbed is present
          if Map.has_key?(metrics, :variety_absorbed) do
            IO.puts("  ✓ variety_absorbed: #{metrics.variety_absorbed}")
          else
            IO.puts("  ✗ variety_absorbed key missing!")
          end
        catch
          kind, error ->
            IO.puts("  ✗ Error calling :get_metrics - #{kind}: #{inspect(error)}")
        end
    end
    
    IO.puts("")
  end
end

# Test each VSM subsystem
MetricsTest.test_metrics("S1.Operations", AutonomousOpponentV2Core.VSM.S1.Operations)
MetricsTest.test_metrics("S2.Coordination", AutonomousOpponentV2Core.VSM.S2.Coordination)
MetricsTest.test_metrics("S3.Control", AutonomousOpponentV2Core.VSM.S3.Control)
MetricsTest.test_metrics("Algedonic.Channel", AutonomousOpponentV2Core.VSM.Algedonic.Channel)

IO.puts("=== Test Complete ===\n")