#!/usr/bin/env elixir

# Test script to verify VSM pattern publishing is working
IO.puts("🧪 Testing VSM Pattern Publishing Implementation...")

# Check if EventBus is running
case Process.whereis(AutonomousOpponentV2Core.EventBus) do
  nil -> 
    IO.puts("❌ EventBus not running - starting application first")
    Application.ensure_all_started(:autonomous_opponent_core)
  pid -> 
    IO.puts("✅ EventBus running at #{inspect pid}")
end

# Subscribe to pattern topics
pattern_topics = [
  :vsm_s1_patterns,
  :vsm_s2_patterns, 
  :vsm_s3_patterns,
  :vsm_s4_patterns,
  :vsm_s5_patterns,
  :vsm_pattern_flow
]

IO.puts("\n📡 Subscribing to pattern topics...")
Enum.each(pattern_topics, fn topic ->
  case AutonomousOpponentV2Core.EventBus.subscribe(topic) do
    :ok -> IO.puts("✅ Subscribed to #{topic}")
    error -> IO.puts("❌ Failed to subscribe to #{topic}: #{inspect error}")
  end
end)

# Check VSM subsystem processes
IO.puts("\n🔍 Checking VSM subsystem status...")
vsm_processes = [
  {"S1 Operations", AutonomousOpponentV2Core.VSM.S1.Operations},
  {"S2 Coordination", AutonomousOpponentV2Core.VSM.S2.Coordination},
  {"S3 Control", AutonomousOpponentV2Core.VSM.S3.Control},
  {"S4 Intelligence", AutonomousOpponentV2Core.VSM.S4.Intelligence},
  {"S5 Policy", AutonomousOpponentV2Core.VSM.S5.Policy}
]

running_subsystems = Enum.filter(vsm_processes, fn {name, module} ->
  case Process.whereis(module) do
    nil -> 
      IO.puts("❌ #{name} not running")
      false
    pid -> 
      IO.puts("✅ #{name} running at #{inspect pid}")
      true
  end
end)

IO.puts("\n📊 Status Summary:")
IO.puts("Running subsystems: #{length(running_subsystems)}/#{length(vsm_processes)}")

if length(running_subsystems) > 0 do
  IO.puts("\n⏳ Listening for pattern events for 10 seconds...")
  
  # Listen for events
  receive_loop = fn loop_fn ->
    receive do
      {:event, topic, data} ->
        IO.puts("🎯 Pattern event received!")
        IO.puts("   Topic: #{topic}")
        IO.puts("   Data: #{inspect data, limit: 3, printable_limit: 100}")
        loop_fn.(loop_fn)
    after
      10_000 ->
        IO.puts("⏰ 10 seconds elapsed")
    end
  end
  
  receive_loop.(receive_loop)
else
  IO.puts("❌ No VSM subsystems running - cannot test pattern publishing")
end

IO.puts("\n🏁 Test complete!")