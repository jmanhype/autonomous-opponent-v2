defmodule AutonomousOpponentWeb.PatternsChannel do
  @moduledoc """
  Real-time pattern streaming channel for HNSW event patterns.
  
  Provides WebSocket interface for:
  - Live pattern stream from EventBus
  - Pattern statistics and monitoring
  - VSM subsystem pattern flow
  - Algedonic pattern alerts
  """
  use AutonomousOpponentWeb, :channel
  require Logger
  
  alias AutonomousOpponent.EventBus
  alias AutonomousOpponent.VSM.S4.PatternHNSWBridge
  alias AutonomousOpponent.VSM.S4.VectorStore.HNSWIndex

  @impl true
  def join("patterns:stream", _payload, socket) do
    # Subscribe to pattern events
    EventBus.subscribe(:patterns_indexed)
    EventBus.subscribe(:pattern_matched)
    EventBus.subscribe(:algedonic_signal)
    
    # Send initial stats
    send(self(), :send_initial_stats)
    
    {:ok, socket}
  end
  
  @impl true
  def join("patterns:stats", _payload, socket) do
    # Stats-only channel - no event subscriptions
    send(self(), :send_stats)
    
    # Schedule periodic stats updates
    Process.send_after(self(), :send_stats, 5000)
    
    {:ok, socket}
  end
  
  @impl true
  def join("patterns:vsm", payload, socket) do
    subsystem = Map.get(payload, "subsystem", "all")
    
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
    
    push(socket, "stats_update", %{
      stats: stats,
      timestamp: DateTime.utc_now()
    })
    
    # Reschedule
    Process.send_after(self(), :send_stats, 5000)
    
    {:noreply, socket}
  end

  # Client commands
  @impl true
  def handle_in("query_similar", %{"vector" => vector, "k" => k}, socket) do
    case HNSWIndex.search(:hnsw_index, vector, k) do
      {:ok, results} ->
        {:reply, {:ok, %{results: format_search_results(results)}}, socket}
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end
  
  @impl true
  def handle_in("get_monitoring", _payload, socket) do
    monitoring = get_monitoring_info()
    {:reply, {:ok, monitoring}, socket}
  end
  
  @impl true
  def handle_in("get_cluster_patterns", %{"min_nodes" => min_nodes}, socket) do
    case AutonomousOpponent.Metrics.Cluster.PatternAggregator.get_consensus_patterns(min_nodes) do
      {:ok, patterns} ->
        {:reply, {:ok, %{patterns: patterns}}, socket}
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end
  
  @impl true
  def handle_in("search_cluster", %{"vector" => vector, "k" => k}, socket) do
    case AutonomousOpponent.Metrics.Cluster.PatternAggregator.search_cluster(vector, k) do
      {:ok, results} ->
        {:reply, {:ok, %{results: results}}, socket}
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
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
    case Process.whereis(AutonomousOpponent.VSM.S4.PatternHNSWBridge) do
      nil -> 
        %{error: "bridge_not_running"}
      _pid ->
        AutonomousOpponent.VSM.S4.PatternHNSWBridge.get_stats()
    end
  end
  
  defp get_monitoring_info do
    case Process.whereis(AutonomousOpponent.VSM.S4.PatternHNSWBridge) do
      nil -> 
        %{error: "bridge_not_running"}
      _pid ->
        AutonomousOpponent.VSM.S4.PatternHNSWBridge.get_monitoring_info()
    end
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