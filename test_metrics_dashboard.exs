#!/usr/bin/env elixir

# Test script to verify metrics are being recorded and accessible

alias AutonomousOpponentV2Core.Core.Metrics
alias AutonomousOpponentV2Core.EventBus
alias AutonomousOpponentV2Core.VSM.S1.Operations

IO.puts("Starting metrics test...")

# Wait for system to initialize
Process.sleep(1000)

# Check if Metrics process is running
case Process.whereis(Metrics) do
  nil -> 
    IO.puts("ERROR: Metrics process not running!")
  pid -> 
    IO.puts("✓ Metrics process running: #{inspect(pid)}")
end

# Trigger some operations to generate metrics
IO.puts("\nTriggering test operations...")
for i <- 1..5 do
  EventBus.publish(:external_requests, %{
    id: "test_#{i}",
    type: :process_input,
    data: %{test: i}
  })
  Process.sleep(100)
end

# Wait for processing
Process.sleep(500)

# Check recorded metrics
IO.puts("\nChecking recorded metrics...")

# Get all metrics
try do
  all_metrics = Metrics.get_all_metrics(Metrics)
  IO.puts("Total metrics recorded: #{map_size(all_metrics)}")
  
  # Look for VSM operation metrics
  vsm_metrics = all_metrics
  |> Enum.filter(fn {{key, _}, _} -> String.starts_with?(key, "vsm.") end)
  |> Enum.into(%{})
  
  format_tags = fn
    tags when map_size(tags) == 0 -> ""
    tags ->
      inner = tags
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(",")
      "{#{inner}}"
  end
  
  IO.puts("\nVSM Metrics found:")
  Enum.each(vsm_metrics, fn {{key, tags}, value} ->
    IO.puts("  #{key}#{format_tags.(tags)} = #{value}")
  end)
  
  # Get dashboard data
  IO.puts("\nGetting VSM Dashboard data...")
  dashboard_data = Metrics.get_vsm_dashboard(Metrics)
  IO.inspect(dashboard_data, label: "Dashboard Data")
  
  # Test specific metric retrieval
  IO.puts("\nTesting specific metric retrieval...")
  success_metric = Metrics.get_metric(Metrics, "vsm.operations.success{subsystem=s1}")
  IO.puts("vsm.operations.success{subsystem=s1} = #{inspect(success_metric)}")
  
rescue
  error ->
    IO.puts("ERROR getting metrics: #{inspect(error)}")
end

# Script complete
IO.puts("\nMetrics test complete.")