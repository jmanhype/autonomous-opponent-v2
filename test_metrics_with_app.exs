#!/usr/bin/env elixir
# Test script that starts the application to verify real metrics

Mix.install([
  {:autonomous_opponent_core, path: "./apps/autonomous_opponent_core", runtime: false}
])

# Start the application
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)

IO.puts("Testing Real Metrics Integration with Full App...")
IO.puts("===============================================\n")

# Give the system a moment to start
Process.sleep(1000)

alias AutonomousOpponentV2Core.Core.Metrics
alias AutonomousOpponentV2Core.VSM.S1

# Check if Metrics is running
case Process.whereis(Metrics) do
  nil ->
    IO.puts("❌ Core.Metrics is not running!")
  pid ->
    IO.puts("✅ Core.Metrics is running at #{inspect(pid)}")
    
    # Test the dashboard fetch method (what dashboard_live uses)
    IO.puts("\nTesting dashboard data fetch...")
    dashboard_data = try do
      Metrics.get_vsm_dashboard(Metrics)
    rescue
      e -> 
        IO.puts("Error: #{inspect(e)}")
        nil
    end
    
    if dashboard_data do
      IO.puts("✅ Successfully fetched dashboard data")
      IO.puts("\nInitial Dashboard State:")
      IO.inspect(dashboard_data, pretty: true)
    end
    
    # Simulate some S1 operations to generate real metrics
    IO.puts("\nSimulating S1 operations...")
    case Process.whereis(S1.Operations) do
      nil ->
        IO.puts("❌ S1.Operations not running")
      s1_pid ->
        IO.puts("✅ S1.Operations running at #{inspect(s1_pid)}")
        
        # Send some test requests to S1
        for i <- 1..5 do
          request = %{
            type: :test_request,
            id: "test-#{i}",
            data: %{value: :rand.uniform(100)},
            timestamp: DateTime.utc_now()
          }
          
          result = GenServer.call(S1.Operations, {:process, request})
          IO.puts("  Request #{i}: #{inspect(result)}")
          Process.sleep(200)
        end
    end
    
    # Give metrics time to propagate
    Process.sleep(500)
    
    # Fetch updated dashboard data
    IO.puts("\nFetching updated dashboard data...")
    updated_data = Metrics.get_vsm_dashboard(Metrics)
    
    IO.puts("\nUpdated Dashboard State:")
    IO.inspect(updated_data, pretty: true)
    
    # Test specific metric retrieval
    IO.puts("\nTesting specific metric retrieval...")
    metrics_to_check = [
      "vsm.operations.success{subsystem=s1}",
      "vsm.operations.failure{subsystem=s1}",
      "vsm.operations.rejected{subsystem=s1}",
      "vsm.s1.load",
      "vsm.algedonic.balance"
    ]
    
    for metric_name <- metrics_to_check do
      value = Metrics.get_metric(Metrics, metric_name)
      if value do
        IO.puts("  ✅ #{metric_name}: #{value}")
      else
        IO.puts("  ⚠️  #{metric_name}: no data")
      end
    end
end

IO.puts("\n✅ Test completed!")