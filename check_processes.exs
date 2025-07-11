#\!/usr/bin/env elixir

# Check which processes are running
IO.puts("🔍 Checking Process Status\n")

processes = [
  {AutonomousOpponentV2Core.EventBus, "EventBus"},
  {AutonomousOpponentV2Core.Core.Metrics, "Metrics"},
  {AutonomousOpponentV2Core.VSM.S1.Operations, "VSM S1"},
  {AutonomousOpponentV2Core.VSM.S2.Coordination, "VSM S2"},
  {AutonomousOpponentV2Core.VSM.S3.Control, "VSM S3"},
  {AutonomousOpponentV2Core.VSM.S4.Intelligence, "VSM S4"},
  {AutonomousOpponentV2Core.VSM.S5.Policy, "VSM S5"},
  {AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge, "PatternHNSWBridge"},
  {AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator, "PatternAggregator"},
  {AutonomousOpponentV2Core.Metrics.Cluster.Supervisor, "Metrics Cluster Supervisor"},
  {AutonomousOpponentV2Core.Metrics.Cluster.CRDTStore, "CRDT Store"},
  {AutonomousOpponentV2Core.Metrics.Cluster.Aggregator, "Metrics Aggregator"}
]

running = []
not_running = []

Enum.each(processes, fn {module, name} ->
  case Process.whereis(module) do
    nil -> 
      not_running = [name | not_running]
      IO.puts("❌ #{name}: Not running")
    pid when is_pid(pid) ->
      if Process.alive?(pid) do
        running = [name | running]
        IO.puts("✅ #{name}: Running (#{inspect(pid)})")
      else
        not_running = [name | not_running]
        IO.puts("💀 #{name}: Dead process")
      end
  end
end)

IO.puts("\n📊 Summary:")
IO.puts("  Running: #{length(running)}")
IO.puts("  Not running: #{length(not_running)}")

# Check if we're running as a distributed node
IO.puts("\n🌐 Node Status:")
IO.puts("  Node alive?: #{Node.alive?()}")
IO.puts("  Node name: #{node()}")
IO.puts("  Connected nodes: #{inspect(Node.list())}")

# Check Metrics Cluster Supervisor children
IO.puts("\n👶 Checking Metrics Cluster Supervisor children:")
case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Supervisor) do
  nil -> 
    IO.puts("  Supervisor not running\!")
  pid ->
    children = Supervisor.which_children(pid)
    Enum.each(children, fn {id, child_pid, type, modules} ->
      status = if child_pid == :undefined, do: "❌ Not started", else: "✅ Running"
      IO.puts("  #{status} #{id} (#{inspect(child_pid)})")
    end)
end
EOF < /dev/null