defmodule AutonomousOpponentV2Core.MCP.ResourceManager do
  @moduledoc """
  Manages MCP Resources with caching and real-time updates.
  
  Handles:
  - Resource caching for performance
  - Real-time resource updates from VSM events
  - Resource subscription management
  - Content transformation for different formats
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCP.Message
  
  defstruct [
    :resource_cache,
    :subscriptions,
    :update_queue
  ]
  
  @cache_ttl 30_000  # 30 seconds
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets resource content with caching.
  """
  def get_resource(uri) do
    GenServer.call(__MODULE__, {:get_resource, uri})
  end
  
  @doc """
  Subscribes to resource updates.
  """
  def subscribe_resource(uri, client_pid) do
    GenServer.call(__MODULE__, {:subscribe, uri, client_pid})
  end
  
  @doc """
  Unsubscribes from resource updates.
  """
  def unsubscribe_resource(uri, client_pid) do
    GenServer.call(__MODULE__, {:unsubscribe, uri, client_pid})
  end
  
  @doc """
  Forces cache refresh for a resource.
  """
  def refresh_resource(uri) do
    GenServer.cast(__MODULE__, {:refresh, uri})
  end
  
  @doc """
  Gets cache size for monitoring.
  """
  def cache_size do
    GenServer.call(__MODULE__, :cache_size)
  end
  
  @impl true
  def init(_opts) do
    # Subscribe to VSM events for resource updates
    EventBus.subscribe(:vsm_state_change)
    EventBus.subscribe(:algedonic_signal)
    EventBus.subscribe(:consciousness_update)
    EventBus.subscribe(:metrics_update)
    
    # Start cache cleanup timer
    :timer.send_interval(60_000, :cleanup_cache)
    
    state = %__MODULE__{
      resource_cache: %{},
      subscriptions: %{},
      update_queue: :queue.new()
    }
    
    Logger.info("MCP ResourceManager started")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_resource, uri}, _from, state) do
    case get_cached_resource(uri, state) do
      {:hit, content} ->
        {:reply, {:ok, content}, state}
        
      :miss ->
        case fetch_resource(uri) do
          {:ok, content} ->
            state = cache_resource(uri, content, state)
            {:reply, {:ok, content}, state}
            
          error ->
            {:reply, error, state}
        end
    end
  end
  
  @impl true
  def handle_call({:subscribe, uri, client_pid}, _from, state) do
    # Monitor the client process
    Process.monitor(client_pid)
    
    # Add to subscriptions
    subs = Map.get(state.subscriptions, uri, MapSet.new())
    new_subs = MapSet.put(subs, client_pid)
    
    state = %{state | subscriptions: Map.put(state.subscriptions, uri, new_subs)}
    
    Logger.debug("Client #{inspect(client_pid)} subscribed to resource: #{uri}")
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:unsubscribe, uri, client_pid}, _from, state) do
    case Map.get(state.subscriptions, uri) do
      nil ->
        {:reply, :ok, state}
        
      subs ->
        new_subs = MapSet.delete(subs, client_pid)
        
        state = if MapSet.size(new_subs) == 0 do
          %{state | subscriptions: Map.delete(state.subscriptions, uri)}
        else
          %{state | subscriptions: Map.put(state.subscriptions, uri, new_subs)}
        end
        
        Logger.debug("Client #{inspect(client_pid)} unsubscribed from resource: #{uri}")
        {:reply, :ok, state}
    end
  end
  
  @impl true
  def handle_call(:cache_size, _from, state) do
    size = map_size(state.resource_cache)
    {:reply, {:ok, size}, state}
  end
  
  @impl true
  def handle_cast({:refresh, uri}, state) do
    case fetch_resource(uri) do
      {:ok, content} ->
        state = cache_resource(uri, content, state)
        notify_subscribers(uri, content, state)
        {:noreply, state}
        
      {:error, reason} ->
        Logger.warning("Failed to refresh resource #{uri}: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event, event_name, data}, state) do
    # Handle VSM events and update relevant resources
    state = case event_name do
      :vsm_state_change ->
        update_vsm_resources(data, state)
        
      :algedonic_signal ->
        update_algedonic_resources(data, state)
        
      :consciousness_update ->
        update_consciousness_resources(data, state)
        
      :metrics_update ->
        update_metrics_resources(data, state)
        
      _ ->
        state
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead client from all subscriptions
    state = remove_dead_client(pid, state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:cleanup_cache, state) do
    state = cleanup_expired_cache(state)
    {:noreply, state}
  end
  
  # Private Functions
  
  defp get_cached_resource(uri, state) do
    case Map.get(state.resource_cache, uri) do
      nil ->
        :miss
        
      {content, timestamp} ->
        if System.monotonic_time(:millisecond) - timestamp < @cache_ttl do
          {:hit, content}
        else
          :miss
        end
    end
  end
  
  defp cache_resource(uri, content, state) do
    timestamp = System.monotonic_time(:millisecond)
    cache = Map.put(state.resource_cache, uri, {content, timestamp})
    %{state | resource_cache: cache}
  end
  
  defp fetch_resource("vsm://subsystems") do
    case EventBus.call(:vsm_supervisor, :get_all_states, 5000) do
      {:ok, states} -> 
        {:ok, %{
          uri: "vsm://subsystems",
          mimeType: "application/json",
          text: Jason.encode!(states, pretty: true)
        }}
      error -> 
        error
    end
  end
  
  defp fetch_resource("vsm://consciousness") do
    case EventBus.call(:consciousness, :get_state, 5000) do
      {:ok, state} -> 
        {:ok, %{
          uri: "vsm://consciousness",
          mimeType: "application/json", 
          text: Jason.encode!(state, pretty: true)
        }}
      _ -> 
        {:ok, %{
          uri: "vsm://consciousness",
          mimeType: "application/json",
          text: Jason.encode!(%{state: "unknown", timestamp: DateTime.utc_now()})
        }}
    end
  end
  
  defp fetch_resource("vsm://algedonic") do
    case EventBus.call(:algedonic_monitor, :get_recent_signals, 5000) do
      {:ok, signals} -> 
        {:ok, %{
          uri: "vsm://algedonic",
          mimeType: "application/json",
          text: Jason.encode!(%{signals: signals}, pretty: true)
        }}
      _ -> 
        {:ok, %{
          uri: "vsm://algedonic", 
          mimeType: "application/json",
          text: Jason.encode!(%{signals: []})
        }}
    end
  end
  
  defp fetch_resource("vsm://metrics") do
    case EventBus.call(:metrics_collector, :get_all_metrics, 5000) do
      {:ok, metrics} -> 
        {:ok, %{
          uri: "vsm://metrics",
          mimeType: "application/json",
          text: Jason.encode!(metrics, pretty: true)
        }}
      _ -> 
        {:ok, %{
          uri: "vsm://metrics",
          mimeType: "application/json", 
          text: Jason.encode!(%{error: "Metrics unavailable"})
        }}
    end
  end
  
  defp fetch_resource("vsm://events") do
    # Return event stream description (actual stream handled separately)
    {:ok, %{
      uri: "vsm://events",
      mimeType: "text/event-stream",
      text: "data: Event stream endpoint for real-time VSM events\n\n"
    }}
  end
  
  defp fetch_resource(uri) do
    {:error, "Resource not found: #{uri}"}
  end
  
  defp notify_subscribers(uri, content, state) do
    case Map.get(state.subscriptions, uri) do
      nil ->
        :ok
        
      subscribers ->
        notification = Message.create_notification("notifications/resources/updated", %{
          uri: uri,
          content: content
        })
        
        Enum.each(subscribers, fn client_pid ->
          send(client_pid, {:mcp_notification, notification})
        end)
    end
  end
  
  defp update_vsm_resources(_data, state) do
    # Invalidate VSM-related caches
    uris_to_refresh = ["vsm://subsystems", "vsm://metrics"]
    
    Enum.each(uris_to_refresh, fn uri ->
      GenServer.cast(self(), {:refresh, uri})
    end)
    
    state
  end
  
  defp update_algedonic_resources(_data, state) do
    GenServer.cast(self(), {:refresh, "vsm://algedonic"})
    state
  end
  
  defp update_consciousness_resources(_data, state) do
    GenServer.cast(self(), {:refresh, "vsm://consciousness"})
    state
  end
  
  defp update_metrics_resources(_data, state) do
    GenServer.cast(self(), {:refresh, "vsm://metrics"})
    state
  end
  
  defp remove_dead_client(dead_pid, state) do
    new_subscriptions = state.subscriptions
    |> Enum.map(fn {uri, subscribers} ->
      {uri, MapSet.delete(subscribers, dead_pid)}
    end)
    |> Enum.reject(fn {_uri, subscribers} ->
      MapSet.size(subscribers) == 0
    end)
    |> Map.new()
    
    %{state | subscriptions: new_subscriptions}
  end
  
  defp cleanup_expired_cache(state) do
    current_time = System.monotonic_time(:millisecond)
    
    new_cache = state.resource_cache
    |> Enum.filter(fn {_uri, {_content, timestamp}} ->
      current_time - timestamp < @cache_ttl
    end)
    |> Map.new()
    
    if map_size(new_cache) != map_size(state.resource_cache) do
      Logger.debug("Cleaned up #{map_size(state.resource_cache) - map_size(new_cache)} expired cache entries")
    end
    
    %{state | resource_cache: new_cache}
  end
end