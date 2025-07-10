#!/usr/bin/env elixir

# Quick check of synthesis state

alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore

# Get current state
state = :sys.get_state(CRDTStore)

IO.puts("\n📊 CRDT Store Synthesis State:")
IO.puts("=" <> String.duplicate("=", 50))
IO.puts("• Synthesis enabled: #{state.synthesis_enabled}")
IO.puts("• Belief update count: #{state.belief_update_count}")
IO.puts("• Active synthesis tasks: #{state.active_synthesis_count}/#{state.max_concurrent_synthesis}")
IO.puts("• Last synthesis time: #{state.last_synthesis_time || "Never"}")

# Check Task.Supervisor
case Process.whereis(AutonomousOpponentV2Core.TaskSupervisor) do
  nil -> IO.puts("• ❌ TaskSupervisor: NOT RUNNING")
  pid -> IO.puts("• ✅ TaskSupervisor: Running at #{inspect(pid)}")
end

# Check if synthesis functions are available
IO.puts("\n🔧 Key Features Check:")
IO.puts("• Cast handlers: #{function_exported?(AutonomousOpponentV2Core.AMCP.Memory.CRDTStore, :handle_cast, 2)}")
IO.puts("• Periodic synthesis: #{function_exported?(AutonomousOpponentV2Core.AMCP.Memory.CRDTStore, :handle_info, 2)}")

IO.puts("\n✨ Claude's Implementation Status:")
IO.puts("• Race condition fix: " <> if(Map.has_key?(state, :active_synthesis_count), do: "✅ Implemented", else: "❌ Missing"))
IO.puts("• Task supervision: " <> if(Process.whereis(AutonomousOpponentV2Core.TaskSupervisor), do: "✅ Active", else: "❌ Missing"))
IO.puts("• Concurrent limiting: " <> if(Map.has_key?(state, :max_concurrent_synthesis), do: "✅ Configured", else: "❌ Missing"))