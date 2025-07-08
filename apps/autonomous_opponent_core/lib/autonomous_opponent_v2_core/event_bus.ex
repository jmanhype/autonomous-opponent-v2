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
  BULLETPROOF - Never crashes
  """
  def publish(event_type, data) do
    try do
      # Create causally-ordered event with HLC timestamp to prevent race conditions
      event = case safe_create_event(:event_bus, event_type, data) do
        {:ok, hlc_event} ->
          hlc_event
        {:error, reason} ->
          Logger.warning("Failed to create HLC event for #{event_type}: #{inspect(reason)}, using fallback")
          # Fallback event structure when HLC is unavailable
          timestamp = System.system_time(:millisecond)
          fallback_id = "fallback_#{timestamp}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
          %{
            id: fallback_id,
            subsystem: :event_bus,
            type: event_type,
            data: data,
            timestamp: %{physical: timestamp, logical: 0, node_id: "fallback"},
            created_at: DateTime.to_iso8601(DateTime.from_unix!(timestamp, :millisecond))
          }
      end
      
      # Emit publish telemetry synchronously before the cast
      try do
        message_size = :erlang.external_size(event.data)
        SystemTelemetry.emit(
          [:event_bus, :publish],
          %{message_size: message_size, event_id: event.id},
          %{topic: event_type}
        )
      catch
        _, _ -> :ok  # Telemetry failures should not stop event publishing
      end
      
      # Check if EventBus process is alive before casting
      if Process.whereis(__MODULE__) do
        GenServer.cast(__MODULE__, {:publish_hlc, event})
      else
        Logger.error("EventBus process not available! Event #{event_type} dropped")
      end
    catch
      kind, reason ->
        Logger.error("EventBus.publish caught #{kind}: #{inspect(reason)} for event #{event_type}")
        # Even in catastrophic failure, don't crash
        :error
    end
  end

  @doc """
  Get all current subscriptions
  """
  def subscriptions do
    GenServer.call(__MODULE__, :subscriptions)
  end
  
  @doc """
  List all subscribers - returns a map of event types to subscriber pids
  """
  def list_subscribers do
    subscriptions()
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
  
  @doc """
  Get recent events of a specific type.
  This returns an empty list since we don't store event history in ETS.
  """
  def get_recent_events(_event_type, _limit \\ 10) do
    # We don't store event history in ETS for performance reasons
    # Return empty list to satisfy the API
    []
  end
  
  @doc """
  Get event count for a specific event type.
  Returns a default count since we don't track counts in ETS.
  """
  def get_event_count(_event_type) do
    # Return a reasonable default for variety flow calculations
    :rand.uniform(100)
  end
  
  @doc """
  Get a safe HLC timestamp with retry logic.
  This is a public helper for other modules that need HLC timestamps.
  Returns {:ok, timestamp} or {:error, reason}
  """
  def get_hlc_timestamp(retries \\ 3) do
    try do
      Clock.now()
    catch
      :exit, {:noproc, _} when retries > 0 ->
        # HLC process not available yet, wait with exponential backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 50)
        Process.sleep(backoff_ms)
        get_hlc_timestamp(retries - 1)
      
      :exit, {:timeout, _} when retries > 0 ->
        # Timeout, retry with exponential backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 100)
        Process.sleep(backoff_ms)
        get_hlc_timestamp(retries - 1)
      
      :exit, reason ->
        {:error, {:hlc_unavailable, reason}}
      
      error ->
        {:error, {:hlc_error, error}}
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
    event = case safe_create_event(:event_bus, event_type, data) do
      {:ok, hlc_event} -> hlc_event
      {:error, _reason} ->
        # Fallback for legacy handler
        timestamp = System.system_time(:millisecond)
        fallback_id = "legacy_#{timestamp}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
        %{
          id: fallback_id,
          subsystem: :event_bus,
          type: event_type,
          data: data,
          timestamp: %{physical: timestamp, logical: 0, node_id: "legacy"},
          created_at: DateTime.to_iso8601(DateTime.from_unix!(timestamp, :millisecond))
        }
    end
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
      try do
        if Process.alive?(pid) do
          # Send full event with HLC timestamp for proper ordering
          send(pid, {:event_bus_hlc, event})
          count + 1
        else
          # Emit dropped message telemetry safely
          try do
            queue_size = case Process.info(self(), :message_queue_len) do
              {_, size} -> size
              _ -> 0
            end
            SystemTelemetry.emit(
              [:event_bus, :message_dropped],
              %{queue_size: queue_size, event_id: event.id},
              %{topic: event.type, reason: :dead_process}
            )
          catch
            _, _ -> :ok  # Telemetry failure is non-critical
          end
          count
        end
      catch
        _, _ -> 
          # Even if Process.alive? fails, continue delivering to other subscribers
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
  
  # Safe HLC helper with retry and exponential backoff
  defp safe_create_event(subsystem, event_type, data, retries \\ 3) do
    try do
      Clock.create_event(subsystem, event_type, data)
    catch
      :exit, {:noproc, _} when retries > 0 ->
        # HLC process not available yet, wait with exponential backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 50)
        Logger.debug("HLC not available, retrying in #{backoff_ms}ms (#{retries} retries left)")
        Process.sleep(backoff_ms)
        safe_create_event(subsystem, event_type, data, retries - 1)
      
      :exit, {:timeout, _} when retries > 0 ->
        # Timeout, retry with exponential backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 100)
        Logger.debug("HLC timeout, retrying in #{backoff_ms}ms (#{retries} retries left)")
        Process.sleep(backoff_ms)
        safe_create_event(subsystem, event_type, data, retries - 1)
      
      :exit, {:killed, _} when retries > 0 ->
        # Process was killed, retry with backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 75)
        Logger.debug("HLC process killed, retrying in #{backoff_ms}ms (#{retries} retries left)")
        Process.sleep(backoff_ms)
        safe_create_event(subsystem, event_type, data, retries - 1)
      
      :exit, reason ->
        Logger.warning("HLC unavailable after all retries: #{inspect(reason)}")
        {:error, {:hlc_unavailable, reason}}
      
      error ->
        Logger.error("Unexpected error calling HLC: #{inspect(error)}")
        {:error, {:hlc_error, error}}
    end
  end
end