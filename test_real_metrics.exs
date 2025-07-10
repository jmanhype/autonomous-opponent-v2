#!/usr/bin/env elixir
# Test script to verify real metrics integration

alias AutonomousOpponentV2Core.Core.Metrics
alias AutonomousOpponentV2Core.VSM.S1

IO.puts("Testing Real Metrics Integration...")
IO.puts("===================================\n")

# Check if Metrics is running
case Process.whereis(Metrics) do
  nil ->
    IO.puts("❌ Core.Metrics is not running!")
  pid ->
    IO.puts("✅ Core.Metrics is running at #{inspect(pid)}")
    
    # Record some test metrics
    IO.puts("\nRecording test metrics...")
    
    # Simulate S1 operations
    for i <- 1..10 do
      Metrics.counter(Metrics, "vsm.operations.success", 1, %{subsystem: :s1})
      Metrics.histogram(Metrics, "vsm.operation_duration", :rand.uniform(100), %{subsystem: :s1})
      Process.sleep(100)
    end
    
    # Record some variety flow
    Metrics.variety_flow(Metrics, :s1, 150.0, 120.0)
    
    # Record VSM metrics
    Metrics.vsm_metric(Metrics, :s1, "entropy", 7.5)
    Metrics.vsm_metric(Metrics, :s1, "variety_ratio", 0.75)
    
    # Record an algedonic signal
    Metrics.algedonic_signal(Metrics, :pleasure, 0.8, :test_script)
    
    IO.puts("✅ Test metrics recorded")
    
    # Get dashboard data
    IO.puts("\nFetching VSM dashboard data...")
    dashboard_data = Metrics.get_vsm_dashboard(Metrics)
    
    IO.puts("\nDashboard Data:")
    IO.puts("---------------")
    IO.inspect(dashboard_data, pretty: true, limit: :infinity)
    
    # Get specific metric
    IO.puts("\nGetting specific metric (vsm.operations.success)...")
    case Metrics.get_metric(Metrics, "vsm.operations.success{subsystem=s1}") do
      nil -> IO.puts("❌ No data for operations success metric")
      value -> IO.puts("✅ Operations success count: #{value}")
    end
    
    # Check S1 health
    IO.puts("\nChecking S1 Operations health...")
    case Process.whereis(S1.Operations) do
      nil ->
        IO.puts("❌ S1.Operations is not running")
      pid ->
        IO.puts("✅ S1.Operations is running at #{inspect(pid)}")
        try do
          health = S1.Operations.calculate_health()
          IO.puts("✅ S1 Health Score: #{Float.round(health * 100, 2)}%")
        rescue
          e ->
            IO.puts("❌ Error getting S1 health: #{inspect(e)}")
        end
    end
end

IO.puts("\n✅ Test completed!")