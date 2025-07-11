defmodule AutonomousOpponentV2Core.Metrics.Cluster.EventBridge do
  @moduledoc """
  🌉 METRICS EVENT BRIDGE - INTEGRATING WITH THE VSM NERVOUS SYSTEM
  
  This module bridges the metrics aggregation system with the EventBus,
  ensuring that metric events flow through the same variety-managed channels
  as all other system events.
  
  ## Integration Points
  
  - Subscribes to metric-related events from EventBus
  - Publishes aggregated metrics back to EventBus
  - Respects variety quotas to prevent metric storms
  - Provides algedonic bypass for critical metrics
  
  ## VSM Compliance
  
  The bridge ensures metrics follow VSM communication patterns:
  - S1/S2 operational metrics use normal channels
  - S3 control metrics have priority routing
  - S4/S5 strategic metrics are batched
  - Algedonic signals bypass all constraints
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.EventBus.Cluster.VarietyManager
  alias AutonomousOpponentV2Core.Metrics.Cluster.Aggregator
  
  @metric_events [
    :metrics_update,
    :metrics_aggregate_request,
    :algedonic_signal,
    :vsm_variety_overflow,
    :cluster_health_change
  ]
  
  defstruct [
    :subscriptions,
    :variety_quota,
    :pending_publishes,
    :stats
  ]
  
  # ========== CLIENT API ==========
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Publishes a metric event through variety-managed channels
  """
  def publish_metric_event(metric_name, value, tags \\ %{}) do
    GenServer.cast(__MODULE__, {:publish_metric, metric_name, value, tags})
  end
  
  @doc """
  Broadcasts aggregated metrics to subscribers
  """
  def broadcast_aggregated_metrics(metrics) do
    GenServer.cast(__MODULE__, {:broadcast_aggregated, metrics})
  end
  
  # ========== CALLBACKS ==========
  
  @impl true
  def init(opts) do
    Logger.info("🌉 Initializing Metrics Event Bridge...")
    
    # Subscribe to relevant events
    subscriptions = Enum.map(@metric_events, fn event ->
      EventBus.subscribe(event)
      event
    end)
    
    state = %__MODULE__{
      subscriptions: subscriptions,
      variety_quota: opts[:variety_quota] || 1000,
      pending_publishes: [],
      stats: %{
        events_received: 0,
        events_published: 0,
        events_dropped: 0,
        algedonic_bypasses: 0
      }
    }
    
    # Schedule periodic flush of pending publishes
    Process.send_after(self(), :flush_pending, :timer.seconds(1))
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:publish_metric, metric_name, value, tags}, state) do
    event = %{
      metric: metric_name,
      value: value,
      tags: tags,
      node: node(),
      timestamp: System.os_time(:millisecond)
    }
    
    # Check if this is an algedonic signal
    if is_algedonic?(metric_name) do
      # Bypass variety constraints
      publish_immediately(event, :algedonic)
      new_state = update_stats(state, :algedonic_bypasses)
      {:noreply, new_state}
    else
      # Queue for variety-managed publishing
      new_state = queue_event(event, state)
      {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_cast({:broadcast_aggregated, metrics}, state) do
    # Broadcast aggregated metrics to all subscribers
    event = %{
      type: :aggregated_metrics,
      metrics: metrics,
      node_count: length(Node.list()) + 1,
      timestamp: System.os_time(:millisecond)
    }
    
    # Use Phoenix.PubSub for efficient broadcast
    Phoenix.PubSub.broadcast(
      AutonomousOpponentV2Core.PubSub,
      "metrics:aggregated",
      {:metrics_aggregated, event}
    )
    
    # Also publish to EventBus for recording
    EventBus.publish(:metrics_aggregated, event)
    
    {:noreply, update_stats(state, :events_published)}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{event_name: :metrics_update} = event}, state) do
    # Handle incoming metric update
    handle_metric_update(event.data, state)
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{event_name: :metrics_aggregate_request} = event}, state) do
    # Trigger aggregation for requested metrics
    Task.start(fn ->
      case event.data do
        %{metric: metric_name, options: opts} ->
          Aggregator.aggregate_metric(metric_name, opts)
          
        %{all: true} ->
          Aggregator.aggregate_cluster_metrics()
          
        _ ->
          Logger.warn("Invalid aggregate request: #{inspect(event.data)}")
      end
    end)
    
    {:noreply, update_stats(state, :events_received)}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{event_name: :algedonic_signal} = event}, state) do
    # Immediate handling of algedonic signals
    Logger.warn("🚨 Algedonic signal received: #{inspect(event.data)}")
    
    # Convert to metric and aggregate immediately
    metric_name = "algedonic.#{event.data.type}.#{event.data.source}"
    value = event.data.intensity
    
    # Trigger immediate aggregation
    Aggregator.aggregate_now!(metric_name, :algedonic)
    
    # Broadcast to all monitoring systems
    broadcast_algedonic_alert(event.data)
    
    {:noreply, update_stats(state, :algedonic_bypasses)}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{event_name: :vsm_variety_overflow} = event}, state) do
    # Handle variety overflow - reduce metric publishing rate
    Logger.warn("⚠️ Variety overflow detected: #{inspect(event.data)}")
    
    # Implement backpressure
    new_state = apply_backpressure(state, event.data)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{event_name: :cluster_health_change} = event}, state) do
    # React to cluster health changes
    handle_health_change(event.data, state)
  end
  
  @impl true
  def handle_info(:flush_pending, state) do
    # Flush pending metric events with variety management
    new_state = flush_pending_events(state)
    
    # Schedule next flush
    Process.send_after(self(), :flush_pending, :timer.seconds(1))
    
    {:noreply, new_state}
  end
  
  # ========== PRIVATE FUNCTIONS ==========
  
  defp handle_metric_update(data, state) do
    # Process incoming metric update
    case data do
      %{metric: name, value: value, tags: tags} ->
        # Forward to aggregator if it's a cluster metric
        if should_aggregate?(name) do
          Task.start(fn ->
            Aggregator.aggregate_metric(name, [immediate: true])
          end)
        end
        
      _ ->
        Logger.debug("Unhandled metric update: #{inspect(data)}")
    end
    
    {:noreply, update_stats(state, :events_received)}
  end
  
  defp handle_health_change(health_data, state) do
    # Adjust metric collection based on cluster health
    case health_data do
      %{status: :degraded, nodes_down: nodes} when length(nodes) > 0 ->
        # Increase aggregation frequency for remaining nodes
        Logger.warn("Cluster degraded - increasing metric aggregation")
        Aggregator.aggregate_cluster_metrics([priority: :high])
        
      %{status: :critical} ->
        # Switch to emergency mode - only critical metrics
        Logger.error("Cluster critical - emergency metrics only")
        apply_emergency_mode(state)
        
      _ ->
        state
    end
  end
  
  defp is_algedonic?(metric_name) do
    String.starts_with?(metric_name, "algedonic.") or
    String.contains?(metric_name, ".pain.") or
    String.contains?(metric_name, ".pleasure.")
  end
  
  defp should_aggregate?(metric_name) do
    # Aggregate VSM and cluster-wide metrics
    String.starts_with?(metric_name, "vsm.") or
    String.starts_with?(metric_name, "cluster.") or
    String.contains?(metric_name, ".total") or
    String.contains?(metric_name, ".avg")
  end
  
  defp publish_immediately(event, priority) do
    # Bypass variety constraints for critical events
    EventBus.publish(:metrics_update, event, metadata: %{
      priority: priority,
      bypass_variety: true,
      cluster_bridge: true
    })
  end
  
  defp queue_event(event, state) do
    %{state | pending_publishes: [event | state.pending_publishes]}
  end
  
  defp flush_pending_events(state) do
    if length(state.pending_publishes) == 0 do
      state
    else
      # Check variety constraints
      case check_variety_quota(state) do
        {:ok, available} ->
          # Publish up to available quota
          {to_publish, remaining} = Enum.split(state.pending_publishes, available)
          
          # Batch publish for efficiency
          publish_batch(to_publish)
          
          %{state | 
            pending_publishes: remaining,
            stats: Map.update(state.stats, :events_published, length(to_publish), &(&1 + length(to_publish)))
          }
          
        {:error, :quota_exceeded} ->
          # Drop oldest events if queue is too large
          if length(state.pending_publishes) > 1000 do
            Logger.warn("Dropping #{length(state.pending_publishes) - 1000} old metric events")
            
            new_pending = Enum.take(state.pending_publishes, -1000)
            dropped = length(state.pending_publishes) - 1000
            
            %{state | 
              pending_publishes: new_pending,
              stats: Map.update(state.stats, :events_dropped, dropped, &(&1 + dropped))
            }
          else
            state
          end
      end
    end
  end
  
  defp check_variety_quota(state) do
    # Check with VarietyManager
    case VarietyManager.check_outbound(VarietyManager, :metrics) do
      :allowed ->
        {:ok, min(state.variety_quota, 100)}  # Batch size limit
        
      :throttled ->
        {:ok, 10}  # Reduced batch size
        
      :blocked ->
        {:error, :quota_exceeded}
    end
  catch
    :exit, _ ->
      # VarietyManager not available, use local quota
      {:ok, 50}
  end
  
  defp publish_batch(events) do
    # Group by metric name for efficient publishing
    grouped = Enum.group_by(events, & &1.metric)
    
    Enum.each(grouped, fn {metric_name, metric_events} ->
      batch_event = %{
        type: :metric_batch,
        metric: metric_name,
        values: Enum.map(metric_events, fn e -> 
          %{value: e.value, tags: e.tags, timestamp: e.timestamp}
        end),
        node: node(),
        count: length(metric_events)
      }
      
      EventBus.publish(:metrics_batch, batch_event, metadata: %{
        cluster_bridge: true,
        compressed: true
      })
    end)
  end
  
  defp broadcast_algedonic_alert(algedonic_data) do
    # Broadcast to multiple channels for redundancy
    channels = [
      "algedonic:critical",
      "metrics:algedonic",
      "vsm:emergency"
    ]
    
    Enum.each(channels, fn channel ->
      Phoenix.PubSub.broadcast(
        AutonomousOpponentV2Core.PubSub,
        channel,
        {:algedonic_alert, algedonic_data}
      )
    end)
  end
  
  defp apply_backpressure(state, overflow_data) do
    # Reduce publishing rate based on overflow severity
    severity = overflow_data[:severity] || :medium
    
    new_quota = case severity do
      :low -> div(state.variety_quota, 2)
      :medium -> div(state.variety_quota, 4)
      :high -> div(state.variety_quota, 10)
      :critical -> 1  # Only most critical metrics
    end
    
    Logger.info("Applying backpressure - reducing quota to #{new_quota}")
    
    %{state | variety_quota: new_quota}
  end
  
  defp apply_emergency_mode(state) do
    # Only allow critical metrics through
    critical_only = Enum.filter(state.pending_publishes, fn event ->
      is_algedonic?(event.metric) or
      String.contains?(event.metric, "critical") or
      String.contains?(event.metric, "failure")
    end)
    
    # Drop all non-critical
    dropped = length(state.pending_publishes) - length(critical_only)
    
    %{state | 
      pending_publishes: critical_only,
      variety_quota: 10,  # Minimal quota
      stats: Map.update(state.stats, :events_dropped, dropped, &(&1 + dropped))
    }
  end
  
  defp update_stats(state, key) do
    %{state | stats: Map.update(state.stats, key, 1, &(&1 + 1))}
  end
end