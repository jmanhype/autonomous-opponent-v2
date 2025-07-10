defmodule AutonomousOpponentV2Core.EventBus.PhoenixPubSubAdapter do
  @moduledoc """
  Phoenix.PubSub adapter that bridges Phoenix.PubSub with EventBus clustering.
  
  This allows existing Phoenix LiveView and Channel code to automatically
  benefit from EventBus clustering without modification.
  
  ## Usage in config:
  
      config :autonomous_opponent_web, AutonomousOpponentV2Web.PubSub,
        adapter: AutonomousOpponentV2Core.EventBus.PhoenixPubSubAdapter,
        pool_size: 1
  
  ## Features:
  
  - Automatic event ordering via HLC timestamps
  - Circuit breaker protection for failed nodes
  - Priority lanes for critical events
  - Transparent fallback to local operation
  """
  
  @behaviour Phoenix.PubSub.Adapter
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.EventBus.ClusterBridge
  
  require Logger
  
  @impl true
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
  
  def start_link(opts) do
    # Extract our options
    name = Keyword.fetch!(opts, :name)
    adapter_name = Module.concat(name, __MODULE__)
    
    # Start a supervisor for our processes
    children = [
      # Registry for tracking subscribers
      {Registry, keys: :duplicate, name: registry_name(adapter_name)},
      
      # GenServer to handle subscriptions
      {__MODULE__.Server, {adapter_name, opts}}
    ]
    
    Supervisor.start_link(children, strategy: :one_for_all, name: adapter_name)
  end
  
  @impl true
  def node_name(_adapter_name), do: node()
  
  @impl true
  def broadcast(adapter_name, topic, message, _dispatcher \\ __MODULE__.Dispatcher) do
    # Convert to EventBus event
    event_type = topic_to_event_type(topic)
    
    # Check if this is a priority message
    priority = case message do
      %{__priority__: :high} -> true
      %{type: type} when type in [:alarm, :alert, :emergency] -> true
      _ -> false
    end
    
    # Publish via EventBus (which handles clustering)
    EventBus.publish(event_type, %{
      topic: topic,
      message: message,
      priority: priority,
      source_node: node()
    })
    
    :ok
  end
  
  @impl true
  def direct_broadcast(adapter_name, node_name, topic, message, dispatcher \\ __MODULE__.Dispatcher) do
    # For direct broadcasts, we still use EventBus but tag it
    if node_name == node() do
      broadcast(adapter_name, topic, message, dispatcher)
    else
      # Send directly to specific node via ClusterBridge
      event = %{
        type: topic_to_event_type(topic),
        data: %{
          topic: topic,
          message: message,
          target_node: node_name,
          source_node: node()
        },
        _direct_broadcast: true
      }
      
      ClusterBridge.replicate_event(event)
      :ok
    end
  end
  
  defmodule Server do
    @moduledoc false
    use GenServer
    
    def start_link({adapter_name, opts}) do
      GenServer.start_link(__MODULE__, {adapter_name, opts}, name: adapter_name)
    end
    
    def init({adapter_name, _opts}) do
      # Subscribe to all EventBus events that look like PubSub topics
      EventBus.subscribe(:pubsub_all, self(), ordered_delivery: true)
      
      {:ok, %{adapter_name: adapter_name, subscriptions: %{}}}
    end
    
    def handle_info({:event_bus_hlc, event}, state) do
      # Extract topic from event
      case event.data do
        %{topic: topic, message: message} ->
          # Dispatch to local subscribers
          Phoenix.PubSub.local_broadcast(state.adapter_name, topic, message)
          
        _ ->
          :ok
      end
      
      {:noreply, state}
    end
  end
  
  defmodule Dispatcher do
    @moduledoc false
    
    def dispatch(entries, from, message) do
      for {pid, metadata} <- entries do
        send(pid, {from, metadata, message})
      end
    end
  end
  
  # Helper functions
  
  defp topic_to_event_type(topic) when is_binary(topic) do
    String.to_atom("pubsub_" <> String.replace(topic, ":", "_"))
  end
  
  defp topic_to_event_type(topic) when is_atom(topic) do
    String.to_atom("pubsub_" <> Atom.to_string(topic))
  end
  
  defp registry_name(adapter_name) do
    Module.concat(adapter_name, Registry)
  end
  
  defp dispatch_to_subscribers(adapter_name, topic, message) do
    Registry.dispatch(registry_name(adapter_name), topic, fn entries ->
      Dispatcher.dispatch(entries, self(), message)
    end)
  end
end