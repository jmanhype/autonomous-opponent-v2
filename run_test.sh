#!/bin/bash

echo "Starting IEx session and running VSM test..."

# Copy the test content
cat > /tmp/test_input.txt << 'EOF'
defmodule BrutalVSMTest do
  def test_everything() do
    IO.puts("\n🔥 BRUTAL VSM PATTERN PUBLISHING TEST 🔥")
    
    # Check EventBus first
    IO.puts("\n1️⃣ CHECKING EVENTBUS...")
    case Process.whereis(AutonomousOpponentV2Core.EventBus) do
      nil -> 
        IO.puts("❌ EventBus not running - starting core app")
        Application.ensure_all_started(:autonomous_opponent_core)
        :timer.sleep(1000)
      pid -> 
        IO.puts("✅ EventBus running: #{inspect pid}")
    end
    
    # Check VSM subsystems
    IO.puts("\n2️⃣ CHECKING VSM SUBSYSTEMS...")
    vsm_modules = [
      {"S1 Operations", AutonomousOpponentV2Core.VSM.S1.Operations},
      {"S2 Coordination", AutonomousOpponentV2Core.VSM.S2.Coordination},
      {"S3 Control", AutonomousOpponentV2Core.VSM.S3.Control},
      {"S4 Intelligence", AutonomousOpponentV2Core.VSM.S4.Intelligence},
      {"S5 Policy", AutonomousOpponentV2Core.VSM.S5.Policy}
    ]
    
    running_vsm = Enum.filter(vsm_modules, fn {name, module} ->
      case Process.whereis(module) do
        nil -> 
          IO.puts("❌ #{name} NOT RUNNING")
          false
        pid -> 
          IO.puts("✅ #{name} running: #{inspect pid}")
          true
      end
    end)
    
    IO.puts("\n📊 VSM STATUS: #{length(running_vsm)}/#{length(vsm_modules)} subsystems running")
    
    if length(running_vsm) > 0 do
      IO.puts("\n3️⃣ TESTING PATTERN SUBSCRIPTION...")
      case AutonomousOpponentV2Core.EventBus.subscribe(:vsm_pattern_flow) do
        :ok -> 
          IO.puts("✅ Subscribed to :vsm_pattern_flow")
          
          IO.puts("\n4️⃣ LISTENING FOR PATTERN EVENTS (5 seconds)...")
          receive do
            {:event, topic, data} ->
              IO.puts("🎯 PATTERN EVENT RECEIVED!")
              IO.puts("   Topic: #{topic}")
              if is_map(data) and Map.has_key?(data, :subsystem) do
                IO.puts("   From: #{data.subsystem}")
              end
          after
            5000 ->
              IO.puts("⏰ No pattern events in 5 seconds")
              IO.puts("   Checking if health reporting is working...")
              
              # Try to trigger health reports manually
              Enum.each(running_vsm, fn {name, module} ->
                try do
                  send(Process.whereis(module), :report_health)
                  IO.puts("✅ Sent :report_health to #{name}")
                rescue
                  error -> IO.puts("❌ Failed to send health report to #{name}: #{inspect error}")
                end
              end)
              
              IO.puts("   Listening for 3 more seconds after manual trigger...")
              receive do
                {:event, topic, data} ->
                  IO.puts("🎯 PATTERN EVENT AFTER MANUAL TRIGGER!")
                  IO.puts("   Topic: #{topic}")
                  IO.puts("   SUCCESS: Pattern publishing is working!")
              after
                3000 ->
                  IO.puts("💀 NO PATTERN EVENTS EVEN AFTER MANUAL TRIGGER")
                  IO.puts("   Pattern publishing implementation may be broken")
              end
          end
          
        error -> 
          IO.puts("❌ Failed to subscribe: #{inspect error}")
      end
    else
      IO.puts("💀 NO VSM SUBSYSTEMS RUNNING")
      IO.puts("   Try starting the full application:")
      IO.puts("   Application.ensure_all_started(:autonomous_opponent)")
    end
    
    IO.puts("\n🏁 TEST COMPLETE")
  end
end

BrutalVSMTest.test_everything()
EOF

# Start IEx and feed it the test
timeout 30 iex -S mix phx.server --no-start < /tmp/test_input.txt

echo "Test completed"