defmodule AutonomousOpponentV2Core.EventBus do
  @moduledoc """
  Central event bus for the Autonomous Opponent system.

  Provides pub/sub functionality for all VSM subsystems to communicate
  asynchronously while maintaining loose coupling.
  """

  use GenServer
  require Logger

  @table_name :event_bus_subscriptions

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe to events of a specific type
  """
  def subscribe(event_type, pid \\ self()) do
    GenServer.call(__MODULE__, {:subscribe, event_type, pid})
  end

  @doc """
  Unsubscribe from events of a specific type
  """
  def unsubscribe(event_type, pid \\ self()) do
    GenServer.call(__MODULE__, {:unsubscribe, event_type, pid})
  end

  @doc """
  Publish an event to all subscribers
  """
  def publish(event_type, data) do
    GenServer.cast(__MODULE__, {:publish, event_type, data})
  end

  @doc """
  Get all current subscriptions
  """
  def subscriptions do
    GenServer.call(__MODULE__, :subscriptions)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for subscriptions
    :ets.new(@table_name, [:named_table, :bag, :public, {:read_concurrency, true}])

    Logger.info("EventBus initialized")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:subscribe, event_type, pid}, _from, state) do
    # Monitor the subscriber process
    Process.monitor(pid)

    # Add subscription to ETS
    :ets.insert(@table_name, {event_type, pid})

    Logger.debug("Process #{inspect(pid)} subscribed to #{event_type}")

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unsubscribe, event_type, pid}, _from, state) do
    # Remove subscription from ETS
    :ets.delete_object(@table_name, {event_type, pid})

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
  def handle_cast({:publish, event_type, data}, state) do
    # Get all subscribers for this event type
    subscribers = :ets.lookup(@table_name, event_type)

    # Send event to each subscriber
    Enum.each(subscribers, fn {^event_type, pid} ->
      send(pid, {:event, event_type, data})
    end)

    # Log high-priority events
    case event_type do
      :algedonic_pain ->
        Logger.warning("Algedonic pain signal published: #{inspect(data)}")

      :algedonic_intervention ->
        Logger.warning("Algedonic intervention published: #{inspect(data)}")

      :emergency_algedonic ->
        Logger.error("EMERGENCY algedonic signal published: #{inspect(data)}")

      _ ->
        Logger.debug("Event published: #{event_type}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove all subscriptions for the dead process
    subscriptions = :ets.match(@table_name, {:"$1", pid})

    Enum.each(subscriptions, fn [event_type] ->
      :ets.delete_object(@table_name, {event_type, pid})
    end)

    Logger.debug("Cleaned up subscriptions for dead process #{inspect(pid)}")

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("EventBus received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end