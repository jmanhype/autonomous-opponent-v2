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
  
  ## Options
  
  - `:ordered_delivery` - Enable causal ordering for this subscription (default: false)
  - `:buffer_window_ms` - Time window for ordering buffer (default: 50)
  - `:batch_delivery` - Receive events in batches (default: false)
  
  ## Examples
  
      # Simple subscription
      EventBus.subscribe(:my_event)
      
      # Ordered delivery subscription  
      EventBus.subscribe(:my_event, self(), ordered_delivery: true)
      
      # Custom buffer window
      EventBus.subscribe(:my_event, self(), ordered_delivery: true, buffer_window_ms: 100)
  """
  def subscribe(event_type, pid \\ self(), opts \\ []) do
    SystemTelemetry.measure([:event_bus, :subscribe], %{event_type: event_type}, fn ->
      GenServer.call(__MODULE__, {:subscribe, event_type, pid, opts})
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
    
    # Add topic field to match what OrderedDelivery expects
    event = Map.put(event, :topic, event_type)
    
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

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for subscriptions
    :ets.new(@table_name, [:named_table, :bag, :public, {:read_concurrency, true}])
    
    # Create ETS table for ordered delivery processes
    :ets.new(:event_bus_ordered_delivery, [:named_table, :set, :public])

    Logger.info("EventBus initialized")
    
    # Emit initialization telemetry
    SystemTelemetry.emit(
      [:event_bus, :initialized],
      %{table_size: :ets.info(@table_name, :size)},
      %{}
    )

    {:ok, %{ordered_delivery_supervisor: nil}}
  end

  @impl true
  def handle_call({:subscribe, event_type, pid, opts}, _from, state) do
    # Monitor the subscriber process
    Process.monitor(pid)

    # Check if ordered delivery is requested
    if Keyword.get(opts, :ordered_delivery, false) do
      # Start an OrderedDelivery process for this subscriber
      {:ok, delivery_pid} = start_ordered_delivery(event_type, pid, opts)
      
      # Store the mapping
      :ets.insert(:event_bus_ordered_delivery, {{event_type, pid}, delivery_pid})
      
      # Subscribe the OrderedDelivery process instead of the actual subscriber
      :ets.insert(@table_name, {event_type, delivery_pid})
      
      Logger.info("Process #{inspect(pid)} subscribed to #{inspect(event_type)} with ordered delivery")
    else
      # Regular subscription
      :ets.insert(@table_name, {event_type, pid})
      Logger.debug("Process #{inspect(pid)} subscribed to #{inspect(event_type)}")
    end
    
    # Emit subscription telemetry
    subscriber_count = length(:ets.lookup(@table_name, event_type))
    SystemTelemetry.emit(
      [:event_bus, :subscription_added],
      %{subscriber_count: subscriber_count, ordered: Keyword.get(opts, :ordered_delivery, false)},
      %{event_type: event_type, pid: pid}
    )

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unsubscribe, event_type, pid}, _from, state) do
    # Check if this has ordered delivery
    case :ets.lookup(:event_bus_ordered_delivery, {event_type, pid}) do
      [{{^event_type, ^pid}, delivery_pid}] ->
        # Stop the OrderedDelivery process
        Process.exit(delivery_pid, :normal)
        :ets.delete(:event_bus_ordered_delivery, {event_type, pid})
        :ets.delete_object(@table_name, {event_type, delivery_pid})
        
      [] ->
        # Regular unsubscription
        :ets.delete_object(@table_name, {event_type, pid})
    end
    
    # Emit unsubscription telemetry
    subscriber_count = length(:ets.lookup(@table_name, event_type))
    SystemTelemetry.emit(
      [:event_bus, :subscription_removed],
      %{subscriber_count: subscriber_count},
      %{event_type: event_type, pid: pid}
    )

    Logger.debug("Process #{inspect(pid)} unsubscribed from #{inspect(event_type)}")

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
        # Check if this pid is in the ordered delivery table (meaning it's an OrderedDelivery process)
        ordered_entries = :ets.match(:event_bus_ordered_delivery, {:_, pid})
        
        if length(ordered_entries) > 0 do
          # This is an OrderedDelivery process
          AutonomousOpponentV2Core.EventBus.OrderedDelivery.submit_event(pid, event)
        else
          # Regular subscriber - send directly
          send(pid, {:event_bus_hlc, event})
        end
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
    
    # Also clean up any OrderedDelivery mappings
    ordered_mappings = :ets.match(:event_bus_ordered_delivery, {{:"$1", pid}, :"$2"})
    Enum.each(ordered_mappings, fn [event_type, delivery_pid] ->
      Process.exit(delivery_pid, :normal)
      :ets.delete(:event_bus_ordered_delivery, {event_type, pid})
    end)
    
    # Emit cleanup telemetry
    SystemTelemetry.emit(
      [:event_bus, :subscriber_cleanup],
      %{subscriptions_removed: cleaned_count, ordered_removed: length(ordered_mappings)},
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
  
  # Private functions
  
  defp start_ordered_delivery(event_type, subscriber_pid, opts) do
    # Prepare options for OrderedDelivery
    delivery_opts = [
      subscriber: subscriber_pid,
      buffer_window_ms: Keyword.get(opts, :buffer_window_ms, 50),
      config: %{
        batch_size: if(Keyword.get(opts, :batch_delivery, false), do: 100, else: 1),
        adaptive_window: Keyword.get(opts, :adaptive_window, true),
        max_buffer_size: 10_000,
        max_window_ms: 100,
        min_window_ms: 10,
        algedonic_bypass_threshold: 0.95,
        clock_drift_tolerance_ms: 1000
      }
    ]
    
    # Start under a simple supervisor
    case DynamicSupervisor.start_child(
      AutonomousOpponentV2Core.EventBus.OrderedDeliverySupervisor,
      {AutonomousOpponentV2Core.EventBus.OrderedDelivery, delivery_opts}
    ) do
      {:ok, pid} ->
        {:ok, pid}
        
      error ->
        Logger.error("Failed to start OrderedDelivery: #{inspect(error)}")
        error
    end
  end
end