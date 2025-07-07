defmodule AutonomousOpponentV2Core.EventBus do
  @moduledoc """
  Central event bus for the Autonomous Opponent system.

  Provides pub/sub functionality for all VSM subsystems to communicate
  asynchronously while maintaining loose coupling.
  """

  use GenServer
  require Logger
  alias AutonomousOpponentV2Core.Telemetry.SystemTelemetry
  alias AutonomousOpponentV2Core.VSM.Clock

  @table_name :event_bus_subscriptions

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe to events of a specific type
  """
  def subscribe(event_type, pid \\ self()) do
    SystemTelemetry.measure([:event_bus, :subscribe], %{event_type: event_type}, fn ->
      GenServer.call(__MODULE__, {:subscribe, event_type, pid})
    end)
  end

  @doc """
  Unsubscribe from events of a specific type
  """
  def unsubscribe(event_type, pid \\ self()) do
    SystemTelemetry.measure([:event_bus, :unsubscribe], %{event_type: event_type}, fn ->
      GenServer.call(__MODULE__, {:unsubscribe, event_type, pid})
    end)
  end

  @doc """
  Publish an event to all subscribers
  """
  def publish(event_type, data) do
    # Create causally-ordered event with HLC timestamp to prevent race conditions
    {:ok, event} = Clock.create_event(:event_bus, event_type, data)
    
    # Emit publish telemetry synchronously before the cast
    message_size = :erlang.external_size(event.data)
    SystemTelemetry.emit(
      [:event_bus, :publish],
      %{message_size: message_size, event_id: event.id},
      %{topic: event_type}
    )
    
    GenServer.cast(__MODULE__, {:publish_hlc, event})
  end

  @doc """
  Get all current subscriptions
  """
  def subscriptions do
    GenServer.call(__MODULE__, :subscriptions)
  end
  
  @doc """
  Make a synchronous call to a named process via EventBus
  """
  def call(name, request, timeout \\ 5000) do
    try do
      GenServer.call(name, request, timeout)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end
  
  @doc """
  Make a synchronous call with arguments to a named process via EventBus
  """
  def call(name, request, args, timeout) when is_list(args) do
    try do
      GenServer.call(name, {request, args}, timeout)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for subscriptions
    :ets.new(@table_name, [:named_table, :bag, :public, {:read_concurrency, true}])

    Logger.info("EventBus initialized")
    
    # Emit initialization telemetry
    SystemTelemetry.emit(
      [:event_bus, :initialized],
      %{table_size: :ets.info(@table_name, :size)},
      %{}
    )

    {:ok, %{}}
  end

  @impl true
  def handle_call({:subscribe, event_type, pid}, _from, state) do
    # Monitor the subscriber process
    Process.monitor(pid)

    # Add subscription to ETS
    :ets.insert(@table_name, {event_type, pid})
    
    # Emit subscription telemetry
    subscriber_count = length(:ets.lookup(@table_name, event_type))
    SystemTelemetry.emit(
      [:event_bus, :subscription_added],
      %{subscriber_count: subscriber_count},
      %{event_type: event_type, pid: pid}
    )

    Logger.debug("Process #{inspect(pid)} subscribed to #{event_type}")

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unsubscribe, event_type, pid}, _from, state) do
    # Remove subscription from ETS
    :ets.delete_object(@table_name, {event_type, pid})
    
    # Emit unsubscription telemetry
    subscriber_count = length(:ets.lookup(@table_name, event_type))
    SystemTelemetry.emit(
      [:event_bus, :subscription_removed],
      %{subscriber_count: subscriber_count},
      %{event_type: event_type, pid: pid}
    )

    Logger.debug("Process #{inspect(pid)} unsubscribed from #{event_type}")

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:subscriptions, _from, state) do
    subscriptions =
      :ets.tab2list(@table_name)
      |> Enum.group_by(fn {event_type, _pid} -> event_type end, fn {_event_type, pid} -> pid end)

    {:reply, subscriptions, state}
  end

  @impl true
  # Legacy publish handler - maintained for backward compatibility
  def handle_cast({:publish, event_type, data}, state) do
    # Convert to HLC event for consistent handling
    {:ok, event} = Clock.create_event(:event_bus, event_type, data)
    handle_cast({:publish_hlc, event}, state)
  end
  
  # New HLC-based publish handler
  def handle_cast({:publish_hlc, event}, state) do
    # Get all subscribers for this event type
    subscribers = :ets.lookup(@table_name, event.type)
    
    # Measure broadcast time
    start_time = System.monotonic_time()

    # Send event to each subscriber with HLC timestamp and ordering info
    delivered = Enum.reduce(subscribers, 0, fn {_event_type, pid}, count ->
      if Process.alive?(pid) do
        # Send full event with HLC timestamp for proper ordering
        send(pid, {:event_bus_hlc, event})
        count + 1
      else
        # Emit dropped message telemetry
        SystemTelemetry.emit(
          [:event_bus, :message_dropped],
          %{queue_size: Process.info(self(), :message_queue_len) |> elem(1), event_id: event.id},
          %{topic: event.type, reason: :dead_process}
        )
        count
      end
    end)
    
    # Emit broadcast completion telemetry
    duration = System.monotonic_time() - start_time
    SystemTelemetry.emit(
      [:event_bus, :broadcast],
      %{recipient_count: delivered, duration: duration, event_id: event.id},
      %{topic: event.type}
    )

    # Log high-priority events with HLC info
    case event.type do
      :algedonic_pain ->
        Logger.warning("Algedonic pain signal published", 
          event_id: event.id, hlc: event.timestamp, data: event.data)

      :algedonic_intervention ->
        Logger.warning("Algedonic intervention published", 
          event_id: event.id, hlc: event.timestamp, data: event.data)

      :emergency_algedonic ->
        Logger.error("EMERGENCY algedonic signal published", 
          event_id: event.id, hlc: event.timestamp, data: event.data)

      _ ->
        Logger.debug("Event published", type: event.type, event_id: event.id)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove all subscriptions for the dead process
    subscriptions = :ets.match(@table_name, {:"$1", pid})

    cleaned_count = Enum.reduce(subscriptions, 0, fn [event_type], count ->
      :ets.delete_object(@table_name, {event_type, pid})
      count + 1
    end)
    
    # Emit cleanup telemetry
    SystemTelemetry.emit(
      [:event_bus, :subscriber_cleanup],
      %{subscriptions_removed: cleaned_count},
      %{pid: pid}
    )

    Logger.debug("Cleaned up #{cleaned_count} subscriptions for dead process #{inspect(pid)}")

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("EventBus received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end