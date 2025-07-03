defmodule AutonomousOpponentCore.EventBus do
  @moduledoc """
  Simple EventBus implementation for the Core application.
  
  Provides pub/sub functionality for modules within the core app
  to communicate asynchronously.
  """
  
  use GenServer
  require Logger
  
  @table_name :event_bus_subscriptions
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Subscribe to events of a specific type.
  """
  def subscribe(event_type) do
    GenServer.call(__MODULE__, {:subscribe, event_type, self()})
  end
  
  @doc """
  Publish an event to all subscribers.
  """
  def publish(event_type, data) do
    GenServer.cast(__MODULE__, {:publish, event_type, data})
  end
  
  @impl true
  def init(_opts) do
    # Create ETS table for subscribers
    :ets.new(@table_name, [:bag, :named_table, :public])
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:subscribe, event_type, pid}, _from, state) do
    # Add subscriber to ETS table
    :ets.insert(@table_name, {event_type, pid})
    
    # Monitor the subscriber process
    Process.monitor(pid)
    
    Logger.debug("Process #{inspect(pid)} subscribed to #{event_type}")
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_cast({:publish, event_type, data}, state) do
    # Find all subscribers for this event type
    subscribers = :ets.lookup(@table_name, event_type)
    
    # Send event to all subscribers
    Enum.each(subscribers, fn {_event_type, pid} ->
      if Process.alive?(pid) do
        send(pid, {:event, event_type, data})
      else
        # Clean up dead process
        :ets.delete_object(@table_name, {event_type, pid})
      end
    end)
    
    Logger.debug("Published #{event_type} to #{length(subscribers)} subscribers")
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up subscriptions for dead process
    :ets.match_delete(@table_name, {:_, pid})
    {:noreply, state}
  end
end