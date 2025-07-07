#!/usr/bin/env elixir

# Test script to verify S5 Policy fix

IO.puts("\n=== Testing S5 Policy Fix ===\n")

# Start the application
Application.ensure_all_started(:autonomous_opponent_core)

# Give it a moment to start
Process.sleep(2000)

# Check if S5 is alive
s5_pid = Process.whereis(AutonomousOpponentV2Core.VSM.S5.Policy)
IO.puts("S5 Process PID: #{inspect(s5_pid)}")
IO.puts("S5 Alive?: #{inspect(Process.alive?(s5_pid))}")

# Check Algedonic channel
algedonic_pid = Process.whereis(AutonomousOpponentV2Core.VSM.Algedonic.Channel)
IO.puts("\nAlgedonic Process PID: #{inspect(algedonic_pid)}")
IO.puts("Algedonic Alive?: #{inspect(Process.alive?(algedonic_pid))}")

# Get Algedonic state
state = AutonomousOpponentV2Core.VSM.Algedonic.Channel.get_hedonic_state()
IO.puts("\nAlgedonic State:")
IO.inspect(state, pretty: true)

# Check monitors
metrics = AutonomousOpponentV2Core.VSM.Algedonic.Channel.get_metrics()
IO.puts("\nMonitor Metrics:")
IO.inspect(metrics, pretty: true)

# Get S5 identity
identity = AutonomousOpponentV2Core.VSM.S5.Policy.get_identity()
IO.puts("\nS5 Identity:")
IO.inspect(identity, pretty: true)

# Wait a bit to see if any crashes occur
IO.puts("\nWaiting 5 seconds to monitor stability...")
Process.sleep(5000)

# Check again
s5_still_alive = Process.alive?(Process.whereis(AutonomousOpponentV2Core.VSM.S5.Policy) || spawn(fn -> :ok end))
IO.puts("\nS5 Still Alive?: #{s5_still_alive}")

if s5_still_alive do
  IO.puts("\n✅ S5 Policy is stable and running!")
else
  IO.puts("\n❌ S5 Policy crashed during test")
end

# Check for emergency signals in last few seconds
Process.sleep(1000)
final_state = AutonomousOpponentV2Core.VSM.Algedonic.Channel.get_hedonic_state()
IO.puts("\nFinal check - Recent screams: #{final_state.recent_screams}")
IO.puts("Intervention active: #{final_state.intervention_active}")

IO.puts("\n=== Test Complete ===\n")