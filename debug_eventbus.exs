defmodule EventBusDebugger do
  use GenServer
  require Logger
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  def init(_) do
    # Subscribe to user_interaction events
    AutonomousOpponentV2Core.EventBus.subscribe(:user_interaction)
    Logger.info("EventBusDebugger subscribed to :user_interaction")
    {:ok, %{count: 0}}
  end
  
  def handle_info({:event_bus, event_name, event_data}, state) do
    Logger.info("EventBusDebugger received event: #{event_name} with data: #{inspect(event_data)}")
    {:noreply, %{state | count: state.count + 1}}
  end
  
  def handle_info(msg, state) do
    Logger.info("EventBusDebugger received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  def get_count do
    GenServer.call(__MODULE__, :get_count)
  end
  
  def handle_call(:get_count, _from, state) do
    {:reply, state.count, state}
  end
end

# Start the debugger
{:ok, pid} = EventBusDebugger.start_link([])
IO.puts("Started EventBusDebugger with PID: #{inspect(pid)}")

# Publish a test event
IO.puts("\nPublishing test event...")
AutonomousOpponentV2Core.EventBus.publish(:user_interaction, %{
  type: :debug_test,
  message: "Testing EventBus delivery",
  timestamp: DateTime.utc_now()
})

# Wait a bit
Process.sleep(1000)

# Check if received
count = EventBusDebugger.get_count()
IO.puts("\nEventBusDebugger received #{count} events")

# Check EventBus state
eb_pid = Process.whereis(AutonomousOpponentV2Core.EventBus)
if eb_pid do
  state = :sys.get_state(eb_pid)
  
  IO.puts("\nEventBus subscription details:")
  Enum.each(state.subscriptions, fn {event, subscribers} ->
    IO.puts("  #{event}: #{length(subscribers)} subscribers")
    if event == :user_interaction do
      IO.puts("    Subscriber PIDs: #{inspect(Enum.map(subscribers, & &1.pid))}")
    end
  end)
end

# Check if SemanticAnalyzer is in the list
sa_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer)
IO.puts("\nSemanticAnalyzer PID: #{inspect(sa_pid)}")