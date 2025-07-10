#!/usr/bin/env elixir

require Logger

IO.puts("=== Debugging API Call Issue ===")

# First, ensure HLC is running
IO.puts("\n1. Checking HLC status...")
hlc_pid = Process.whereis(AutonomousOpponentV2Core.Core.HybridLogicalClock)
IO.puts("HLC PID: #{inspect(hlc_pid)}")
IO.puts("HLC alive? #{if hlc_pid, do: Process.alive?(hlc_pid), else: false}")

# Test HLC directly
IO.puts("\n2. Testing HLC.now() directly...")
try do
  {:ok, timestamp} = AutonomousOpponentV2Core.Core.HybridLogicalClock.now()
  IO.puts("✅ HLC.now() works: #{inspect(timestamp)}")
catch
  :exit, reason ->
    IO.puts("❌ HLC.now() failed: #{inspect(reason)}")
end

# Test EventBus publish (which uses VSM.Clock internally)
IO.puts("\n3. Testing EventBus.publish...")
try do
  AutonomousOpponentV2Core.EventBus.publish(:vsm_state_query, %{
    type: :state_check,
    source: :debug_script,
    timestamp: DateTime.utc_now()
  })
  IO.puts("✅ EventBus.publish succeeded")
catch
  :exit, reason ->
    IO.puts("❌ EventBus.publish failed: #{inspect(reason)}")
end

# Test VSM.Clock directly
IO.puts("\n4. Testing VSM.Clock.now()...")
try do
  {:ok, timestamp} = AutonomousOpponentV2Core.VSM.Clock.now()
  IO.puts("✅ VSM.Clock.now() works: #{inspect(timestamp)}")
catch
  :exit, reason ->
    IO.puts("❌ VSM.Clock.now() failed: #{inspect(reason)}")
end

# Test VSM.Clock.create_event
IO.puts("\n5. Testing VSM.Clock.create_event...")
try do
  {:ok, event} = AutonomousOpponentV2Core.VSM.Clock.create_event(:event_bus, :test_event, %{data: "test"})
  IO.puts("✅ VSM.Clock.create_event works: #{inspect(event.id)}")
catch
  :exit, reason ->
    IO.puts("❌ VSM.Clock.create_event failed: #{inspect(reason)}")
end

# Simulate what happens in EventBus.publish
IO.puts("\n6. Simulating EventBus publish flow...")
try do
  alias AutonomousOpponentV2Core.VSM.Clock
  
  # This is what EventBus.publish does internally
  {:ok, event} = Clock.create_event(:event_bus, :vsm_state_query, %{test: true})
  IO.puts("✅ Clock.create_event succeeded in simulation")
  IO.puts("Event: #{inspect(event)}")
  
  # Try to send it through GenServer.cast
  GenServer.cast(AutonomousOpponentV2Core.EventBus, {:publish_hlc, event})
  IO.puts("✅ GenServer.cast succeeded")
catch
  :exit, reason ->
    IO.puts("❌ Simulation failed: #{inspect(reason)}")
end

# Wait a bit for any async operations
Process.sleep(1000)

IO.puts("\n=== Debug Complete ===")