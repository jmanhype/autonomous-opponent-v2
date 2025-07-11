defmodule AutonomousOpponentV2Web.PatternsChannel do
  @moduledoc """
  Real-time pattern streaming channel for HNSW event patterns.
  
  Provides WebSocket interface for:
  - Live pattern stream from EventBus
  - Pattern statistics and monitoring
  - VSM subsystem pattern flow
  - Algedonic pattern alerts
  - Connection count metrics for operational monitoring
  """
  use AutonomousOpponentV2Web, :channel
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
  
  # ETS table for connection tracking
  @connection_table :pattern_channel_connections
  
  # Initialize the connection tracking table
  def init_connection_tracking do
    if :ets.whereis(@connection_table) == :undefined do
      :ets.new(@connection_table, [:public, :named_table, :set, {:write_concurrency, true}])
    end
  end

  @impl true
  def join("patterns:stream", _payload, socket) do
    # Initialize connection tracking if not already done
    init_connection_tracking()
    
    # Increment connection counter for this topic
    :ets.update_counter(@connection_table, {"patterns:stream", node()}, 1, {{"patterns:stream", node()}, 0})
    
    # Try to subscribe to pattern events, but don't crash if EventBus isn't available
    try do
      EventBus.subscribe(:patterns_indexed)
      EventBus.subscribe(:pattern_matched)
      EventBus.subscribe(:algedonic_signal)
      Logger.info("Successfully subscribed to pattern events")
    catch
      :exit, {:noproc, _} ->
        Logger.warning("EventBus not available - pattern events will not be received")
      error ->
        Logger.error("Failed to subscribe to events: #{inspect(error)}")
    end
    
    # Send initial stats
    send(self(), :send_initial_stats)
    
    {:ok, socket}
  end
  
  @impl true
  def join("patterns:stats", _payload, socket) do
    # Initialize connection tracking if not already done
    init_connection_tracking()
    
    # Increment connection counter for this topic
    :ets.update_counter(@connection_table, {"patterns:stats", node()}, 1, {{"patterns:stats", node()}, 0})
    
    # Stats-only channel - no event subscriptions
    send(self(), :send_stats)
    
    # Schedule periodic stats updates
    Process.send_after(self(), :send_stats, 5000)
    
    {:ok, socket}
  end
  
  @impl true
  def join("patterns:vsm", payload, socket) do
    subsystem = Map.get(payload, "subsystem", "all")
    
    # Initialize connection tracking if not already done
    init_connection_tracking()
    
    # Increment connection counter for this topic
    :ets.update_counter(@connection_table, {"patterns:vsm", node()}, 1, {{"patterns:vsm", node()}, 0})
    
    # Subscribe to VSM-specific pattern events
    if subsystem == "all" do
      EventBus.subscribe(:vsm_pattern_flow)
    else
      EventBus.subscribe(:"vsm_#{subsystem}_patterns")
    end
    
    {:ok, assign(socket, :vsm_subsystem, subsystem)}
  end

  # Handle EventBus events
  @impl true
  def handle_info({:event_bus_hlc, %{type: :patterns_indexed} = event}, socket) do
    # Forward indexed patterns to client
    push(socket, "pattern_indexed", %{
      count: event.data[:count] || 0,
      deduplicated: event.data[:deduplicated] || 0,
      timestamp: event.timestamp,
      source: event.data[:source] || "unknown"
    })
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :pattern_matched} = event}, socket) do
    # Stream individual pattern matches
    pattern_data = event.data
    
    push(socket, "pattern_matched", %{
      pattern_id: pattern_data[:pattern_id],
      confidence: pattern_data[:match_context][:confidence] || 0.0,
      type: pattern_data[:match_context][:type] || "unknown",
      timestamp: event.timestamp,
      context: sanitize_context(pattern_data[:match_context])
    })
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :algedonic_signal} = event}, socket) do
    # Priority broadcast for algedonic patterns
    signal_data = event.data
    
    if signal_data[:intensity] > 0.8 do
      push(socket, "algedonic_pattern", %{
        type: signal_data[:type],
        intensity: signal_data[:intensity],
        source: signal_data[:source],
        pattern_vector: signal_data[:pattern_vector],
        timestamp: event.timestamp,
        severity: "critical"
      })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(:send_initial_stats, socket) do
    stats = get_pattern_stats()
    monitoring = get_monitoring_info()
    
    push(socket, "initial_stats", %{
      stats: stats,
      monitoring: monitoring,
      timestamp: DateTime.utc_now()
    })
    
    # Schedule periodic updates
    Process.send_after(self(), :send_stats, 5000)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(:send_stats, socket) do
    stats = get_pattern_stats()
    connection_stats = get_connection_stats()
    
    push(socket, "stats_update", %{
      stats: stats,
      connections: connection_stats,
      timestamp: DateTime.utc_now()
    })
    
    # Reschedule
    Process.send_after(self(), :send_stats, 5000)
    
    {:noreply, socket}
  end

  # Client commands
  @impl true
  def handle_in("query_similar", %{"vector" => vector, "k" => k}, socket) do
    case Process.whereis(:hnsw_index) do
      nil ->
        {:reply, {:error, %{reason: "HNSW index not available"}}, socket}
      _pid ->
        case HNSWIndex.search(:hnsw_index, vector, k) do
          {:ok, results} ->
            {:reply, {:ok, %{results: format_search_results(results)}}, socket}
          {:error, reason} ->
            {:reply, {:error, %{reason: to_string(reason)}}, socket}
        end
    end
  end
  
  @impl true
  def handle_in("get_monitoring", _payload, socket) do
    monitoring = get_monitoring_info()
    {:reply, {:ok, monitoring}, socket}
  end
  
  @impl true
  def handle_in("get_cluster_patterns", %{"min_nodes" => min_nodes}, socket) do
    case AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator.get_consensus_patterns(min_nodes) do
      {:ok, patterns} ->
        {:reply, {:ok, %{patterns: patterns}}, socket}
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end
  
  @impl true
  def handle_in("search_cluster", %{"vector" => vector, "k" => k}, socket) do
    case AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator.search_cluster(vector, k) do
      {:ok, results} ->
        {:reply, {:ok, %{results: results}}, socket}
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end
  
  @impl true
  def handle_in("get_connection_stats", _payload, socket) do
    stats = get_connection_stats()
    {:reply, {:ok, stats}, socket}
  end
  
  @impl true
  def handle_in("get_cluster_connection_stats", _payload, socket) do
    case AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator.get_cluster_connection_stats() do
      {:ok, stats} ->
        {:reply, {:ok, stats}, socket}
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Decrement connection counter
    topic = socket.topic
    try do
      :ets.update_counter(@connection_table, {topic, node()}, -1, {{topic, node()}, 0})
    catch
      :error, :badarg ->
        # Table might not exist, ignore
        :ok
    end
    
    # Unsubscribe from all EventBus topics
    EventBus.unsubscribe(:patterns_indexed)
    EventBus.unsubscribe(:pattern_matched)
    EventBus.unsubscribe(:algedonic_signal)
    EventBus.unsubscribe(:vsm_pattern_flow)
    
    # Unsubscribe from VSM-specific patterns if applicable
    case socket.assigns[:vsm_subsystem] do
      nil -> :ok
      "all" -> :ok
      subsystem -> EventBus.unsubscribe(:"vsm_#{subsystem}_patterns")
    end
    
    :ok
  end

  # Private helpers
  
  defp get_pattern_stats do
    case Process.whereis(AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge) do
      nil -> 
        %{error: "bridge_not_running"}
      _pid ->
        AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_stats()
    end
  end
  
  @doc """
  Get WebSocket connection statistics for this node.
  """
  def get_connection_stats do
    init_connection_tracking()
    
    # Collect all connection data
    connections = :ets.tab2list(@connection_table)
    
    # Group by topic
    stats = Enum.reduce(connections, %{}, fn {{topic, node}, count}, acc ->
      Map.update(acc, topic, %{node => count}, fn existing ->
        Map.put(existing, node, count)
      end)
    end)
    
    # Calculate totals
    total_connections = connections
    |> Enum.map(fn {_, count} -> count end)
    |> Enum.sum()
    
    %{
      connections: stats,
      total: total_connections,
      node: node(),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp get_monitoring_info do
    bridge_info = case Process.whereis(AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge) do
      nil -> 
        %{error: "bridge_not_running"}
      _pid ->
        AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_monitoring_info()
    end
    
    # Add connection stats to monitoring info
    connection_stats = get_connection_stats()
    
    Map.merge(bridge_info, %{
      websocket_connections: connection_stats
    })
  end
  
  defp sanitize_context(context) when is_map(context) do
    context
    |> Map.take([:type, :confidence, :source, :subsystem])
    |> Map.new(fn {k, v} -> {k, sanitize_value(v)} end)
  end
  defp sanitize_context(_), do: %{}
  
  defp sanitize_value(v) when is_binary(v), do: v
  defp sanitize_value(v) when is_number(v), do: v
  defp sanitize_value(v) when is_atom(v), do: to_string(v)
  defp sanitize_value(_), do: nil
  
  defp format_search_results(results) do
    Enum.map(results, fn {id, distance} ->
      %{
        pattern_id: id,
        similarity: distance,
        # Convert distance to similarity score
        score: 1.0 - distance
      }
    end)
  end
end