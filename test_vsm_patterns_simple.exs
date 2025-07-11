# Simple VSM Pattern Test - Run this in IEx with: iex -S mix phx.server

defmodule VSMPatternTest do
  def run() do
    IO.puts("🧪 Testing VSM Pattern Publishing...")
    
    # Check VSM subsystems
    vsm_modules = [
      {"S1", AutonomousOpponentV2Core.VSM.S1.Operations},
      {"S2", AutonomousOpponentV2Core.VSM.S2.Coordination}, 
      {"S3", AutonomousOpponentV2Core.VSM.S3.Control},
      {"S4", AutonomousOpponentV2Core.VSM.S4.Intelligence},
      {"S5", AutonomousOpponentV2Core.VSM.S5.Policy}
    ]
    
    IO.puts("\n🔍 VSM Subsystem Status:")
    running = Enum.filter(vsm_modules, fn {name, module} ->
      case Process.whereis(module) do
        nil -> 
          IO.puts("❌ #{name} not running")
          false
        pid -> 
          IO.puts("✅ #{name} running (#{inspect pid})")
          true
      end
    end)
    
    if length(running) > 0 do
      # Test subscribing to pattern events
      IO.puts("\n📡 Testing EventBus subscription...")
      case AutonomousOpponentV2Core.EventBus.subscribe(:vsm_pattern_flow) do
        :ok -> 
          IO.puts("✅ Successfully subscribed to :vsm_pattern_flow")
          listen_for_patterns()
        error -> 
          IO.puts("❌ Failed to subscribe: #{inspect error}")
      end
    else
      IO.puts("❌ No VSM subsystems running")
    end
  end
  
  defp listen_for_patterns() do
    IO.puts("⏳ Listening for pattern events (5 seconds)...")
    
    receive do
      {:event, topic, data} ->
        IO.puts("🎯 Pattern event received!")
        IO.puts("   Topic: #{topic}")
        IO.puts("   Data keys: #{inspect Map.keys(data)}")
        if Map.has_key?(data, :subsystem) do
          IO.puts("   From subsystem: #{data.subsystem}")
        end
    after
      5000 ->
        IO.puts("⏰ No pattern events received in 5 seconds")
        IO.puts("   This could mean:")
        IO.puts("   - Pattern publishing isn't working")
        IO.puts("   - Health reporting cycles haven't triggered yet")
        IO.puts("   - EventBus routing issues")
    end
  end
end

VSMPatternTest.run()