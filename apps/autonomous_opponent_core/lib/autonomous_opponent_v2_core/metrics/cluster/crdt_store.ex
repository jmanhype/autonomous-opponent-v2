defmodule AutonomousOpponentV2Core.Metrics.Cluster.CRDTStore do
  @moduledoc """
  🔮 CONFLICT-FREE REPLICATED METRICS STORE
  
  This module provides eventually-consistent distributed storage for metrics
  using CRDTs (Conflict-free Replicated Data Types). It ensures that metrics
  can be safely aggregated across nodes even in the presence of:
  
  - Network partitions
  - Node failures
  - Clock skew
  - Concurrent updates
  
  ## CRDT Types Used
  
  - **PN-Counter**: For monotonic counters (requests, errors, events)
  - **LWW-Register**: For gauge values (CPU, memory, temperature)
  - **OR-Set**: For tracking active nodes and metric tags
  - **Delta-CRDT**: For efficient synchronization of large datasets
  
  ## Variety Management
  
  The store implements variety constraints to prevent metric explosion:
  - Automatic pruning of old metrics
  - Compression of similar metrics
  - Hierarchical aggregation
  
  ## Integration
  
  Integrates with the existing CRDT Store for persistence and replication.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore, as: BaseCRDT
  alias AutonomousOpponentV2Core.EventBus
  
  @metric_prefix "metric:"
  @sync_interval :timer.seconds(5)
  @retention_ms :timer.hours(24)
  @compression_threshold 1000
  
  defstruct [
    :base_store,
    :metric_index,
    :sync_timer,
    :stats,
    :compression_enabled
  ]
  
  # ========== CLIENT API ==========
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Creates a CRDT for a specific metric
  """
  def create_metric_crdt(metric_name, type \\ :pn_counter) do
    GenServer.call(__MODULE__, {:create_metric, metric_name, type})
  end
  
  @doc """
  Updates a metric value using CRDT semantics
  """
  def update_metric(metric_name, value, node \\ node()) do
    GenServer.cast(__MODULE__, {:update_metric, metric_name, value, node})
  end
  
  @doc """
  Persists an aggregated metric result
  """
  def persist_aggregated_metric(metric) do
    GenServer.cast(__MODULE__, {:persist_aggregated, metric})
  end
  
  @doc """
  Queries metrics within a time range
  """
  def query_metric_range(metric_name, start_time, end_time, opts \\ []) do
    GenServer.call(__MODULE__, {:query_range, metric_name, start_time, end_time, opts})
  end
  
  @doc """
  Marks all metrics from a node as stale
  """
  def mark_node_stale(node) do
    GenServer.cast(__MODULE__, {:mark_stale, node})
  end
  
  @doc """
  Gets current statistics about the metric store
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Forces synchronization with peers
  """
  def sync_now do
    GenServer.cast(__MODULE__, :sync_now)
  end
  
  # ========== CALLBACKS ==========
  
  @impl true
  def init(opts) do
    Logger.info("🔮 Initializing CRDT Metrics Store...")
    
    # Subscribe to relevant events
    EventBus.subscribe(:crdt_sync_request)
    EventBus.subscribe(:node_status_change)
    
    # Initialize state
    state = %__MODULE__{
      base_store: nil,  # Will be set when BaseCRDT is available
      metric_index: init_metric_index(),
      sync_timer: nil,
      stats: init_stats(),
      compression_enabled: Keyword.get(opts, :compression, true)
    }
    
    # Schedule periodic sync
    {:ok, schedule_sync(state)}
  end
  
  @impl true
  def handle_call({:create_metric, metric_name, type}, _from, state) do
    key = make_metric_key(metric_name)
    
    # Create appropriate CRDT type
    result = case type do
      :pn_counter ->
        BaseCRDT.create_crdt(key, :pn_counter)
        
      :lww_register ->
        BaseCRDT.create_crdt(key, :lww_register)
        
      :or_set ->
        BaseCRDT.create_crdt(key, :or_set)
        
      _ ->
        {:error, :unsupported_type}
    end
    
    # Update index
    new_state = case result do
      :ok ->
        update_metric_index(state, metric_name, type)
      _ ->
        state
    end
    
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:query_range, metric_name, start_time, end_time, opts}, _from, state) do
    # Query time-series data
    result = query_time_series(metric_name, start_time, end_time, state, opts)
    {:reply, {:ok, result}, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      metric_count: :ets.info(state.metric_index, :size),
      compression_enabled: state.compression_enabled,
      last_sync: get_last_sync_time()
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:update_metric, metric_name, value, node}, state) do
    key = make_metric_key(metric_name)
    timestamp = System.os_time(:millisecond)
    
    # Determine CRDT type from index
    type = get_metric_type(state, metric_name)
    
    # Update based on type
    case type do
      :pn_counter when is_number(value) ->
        # Increment counter
        BaseCRDT.update_crdt(key, :increment, {value, node})
        
      :lww_register ->
        # Update gauge with timestamp
        BaseCRDT.update_crdt(key, :set, {value, timestamp, node})
        
      :or_set ->
        # Add to set
        BaseCRDT.update_crdt(key, :add, {value, node})
        
      nil ->
        # Auto-create based on value type
        create_and_update(metric_name, value, node)
    end
    
    # Update stats
    new_state = update_stats(state, :updates)
    
    # Check if compression needed
    new_state = maybe_compress(new_state)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:persist_aggregated, metric}, state) do
    # Store aggregated metric with metadata
    key = make_aggregated_key(metric.name)
    timestamp = metric.timestamp || System.os_time(:millisecond)
    
    # Store in time-series format
    time_key = {key, timestamp}
    value = %{
      aggregated: metric.aggregated,
      node_values: metric.node_values,
      type: metric.type,
      metadata: %{
        aggregated_at: timestamp,
        aggregated_by: node(),
        node_count: length(metric.node_values)
      }
    }
    
    # Use LWW register for aggregated values
    BaseCRDT.update_crdt(time_key, :set, {value, timestamp, node()})
    
    # Update index
    update_time_series_index(state, metric.name, timestamp)
    
    # Emit event
    EventBus.publish(:metric_aggregated, %{
      metric: metric.name,
      timestamp: timestamp,
      node_count: length(metric.node_values)
    })
    
    {:noreply, update_stats(state, :aggregations)}
  end
  
  @impl true
  def handle_cast({:mark_stale, node}, state) do
    Logger.warn("Marking metrics from #{node} as stale")
    
    # Add stale marker to node's metrics
    stale_key = make_metric_key("_stale_nodes")
    BaseCRDT.update_crdt(stale_key, :add, {node, System.os_time(:millisecond)})
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast(:sync_now, state) do
    perform_sync(state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:scheduled_sync, state) do
    # Perform periodic sync
    perform_sync(state)
    
    # Schedule next sync
    {:noreply, schedule_sync(state)}
  end
  
  @impl true
  def handle_info(:compress_metrics, state) do
    if state.compression_enabled do
      compressed_count = compress_old_metrics(state)
      Logger.info("Compressed #{compressed_count} old metrics")
      
      {:noreply, update_stats(state, {:compressed, compressed_count})}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{event_name: :crdt_sync_request} = event}, state) do
    # Handle sync request from peer
    if event.data.type == :metrics do
      handle_sync_request(event.data, state)
    end
    
    {:noreply, state}
  end
  
  # ========== PRIVATE FUNCTIONS ==========
  
  defp make_metric_key(metric_name) do
    "#{@metric_prefix}#{metric_name}"
  end
  
  defp make_aggregated_key(metric_name) do
    "#{@metric_prefix}aggregated:#{metric_name}"
  end
  
  defp init_metric_index do
    # ETS table for fast metric lookups
    :ets.new(:metric_crdt_index, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true}
    ])
  end
  
  defp init_stats do
    %{
      updates: 0,
      aggregations: 0,
      queries: 0,
      compressions: 0,
      sync_count: 0
    }
  end
  
  defp update_metric_index(state, metric_name, type) do
    :ets.insert(state.metric_index, {metric_name, type, System.os_time(:millisecond)})
    state
  end
  
  defp update_time_series_index(state, metric_name, timestamp) do
    # Maintain sorted index for time-series queries
    key = {:ts_index, metric_name}
    
    case :ets.lookup(state.metric_index, key) do
      [{^key, timestamps}] ->
        # Add timestamp to sorted set
        new_timestamps = [timestamp | timestamps]
        |> Enum.sort()
        |> Enum.take(-1000)  # Keep last 1000 entries
        
        :ets.insert(state.metric_index, {key, new_timestamps})
        
      [] ->
        :ets.insert(state.metric_index, {key, [timestamp]})
    end
    
    state
  end
  
  defp get_metric_type(state, metric_name) do
    case :ets.lookup(state.metric_index, metric_name) do
      [{^metric_name, type, _}] -> type
      [] -> nil
    end
  end
  
  defp create_and_update(metric_name, value, node) do
    # Auto-detect type based on value
    type = cond do
      is_number(value) -> :pn_counter
      is_map(value) -> :lww_register
      true -> :or_set
    end
    
    # Create and update in one go
    create_metric_crdt(metric_name, type)
    update_metric(metric_name, value, node)
  end
  
  defp query_time_series(metric_name, start_time, end_time, state, opts) do
    # Get timestamps from index
    key = {:ts_index, metric_name}
    
    timestamps = case :ets.lookup(state.metric_index, key) do
      [{^key, ts_list}] -> ts_list
      [] -> []
    end
    
    # Filter timestamps in range
    relevant_timestamps = timestamps
    |> Enum.filter(fn ts -> ts >= start_time and ts <= end_time end)
    
    # Fetch values for each timestamp
    aggregated_key = make_aggregated_key(metric_name)
    
    results = Enum.map(relevant_timestamps, fn ts ->
      time_key = {aggregated_key, ts}
      
      case BaseCRDT.read_crdt(time_key) do
        {:ok, value} -> {ts, value}
        _ -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    
    # Apply aggregation function if requested
    case opts[:aggregation] do
      nil -> results
      :raw -> results
      func -> apply_aggregation(results, func)
    end
  end
  
  defp apply_aggregation(results, :avg) do
    values = Enum.map(results, fn {_ts, data} -> 
      get_in(data, [:aggregated, :avg]) || 0
    end)
    
    if length(values) > 0 do
      %{avg: Enum.sum(values) / length(values)}
    else
      %{avg: 0}
    end
  end
  
  defp apply_aggregation(results, :sum) do
    sum = results
    |> Enum.map(fn {_ts, data} -> 
      get_in(data, [:aggregated, :sum]) || 0
    end)
    |> Enum.sum()
    
    %{sum: sum}
  end
  
  defp apply_aggregation(results, :max) do
    max = results
    |> Enum.map(fn {_ts, data} -> 
      get_in(data, [:aggregated, :max]) || 0
    end)
    |> Enum.max(fn -> 0 end)
    
    %{max: max}
  end
  
  defp perform_sync(state) do
    # Sync with other CRDT stores
    Logger.debug("Performing CRDT metrics sync...")
    
    # Get list of metrics to sync
    metrics_to_sync = get_metrics_for_sync(state)
    
    # Trigger sync via base CRDT store
    Enum.each(metrics_to_sync, fn metric_key ->
      BaseCRDT.sync_crdt(metric_key)
    end)
    
    # Update stats
    update_stats(state, :sync_count)
  end
  
  defp get_metrics_for_sync(state) do
    # Get recently updated metrics
    current_time = System.os_time(:millisecond)
    cutoff_time = current_time - @sync_interval
    
    :ets.select(state.metric_index, [
      {
        {:"$1", :"$2", :"$3"},
        [{:>, :"$3", cutoff_time}],
        [:"$1"]
      }
    ])
    |> Enum.map(&make_metric_key/1)
  end
  
  defp compress_old_metrics(state) do
    # Compress metrics older than retention period
    current_time = System.os_time(:millisecond)
    cutoff_time = current_time - @retention_ms
    
    # Find old metrics
    old_metrics = :ets.select(state.metric_index, [
      {
        {:"$1", :"$2", :"$3"},
        [{:<, :"$3", cutoff_time}],
        [{:"$1", :"$2"}]
      }
    ])
    
    # Compress each old metric
    Enum.each(old_metrics, fn {metric_name, type} ->
      compress_metric(metric_name, type, state)
    end)
    
    length(old_metrics)
  end
  
  defp compress_metric(metric_name, :pn_counter, _state) do
    # Counters don't need compression - they're already compact
    :ok
  end
  
  defp compress_metric(metric_name, type, _state) do
    # For other types, downsample time-series data
    key = {:ts_index, metric_name}
    
    case :ets.lookup(:metric_crdt_index, key) do
      [{^key, timestamps}] ->
        # Keep every 10th timestamp for old data
        compressed = timestamps
        |> Enum.with_index()
        |> Enum.filter(fn {_ts, idx} -> rem(idx, 10) == 0 end)
        |> Enum.map(fn {ts, _idx} -> ts end)
        
        :ets.insert(:metric_crdt_index, {key, compressed})
        
      [] ->
        :ok
    end
  end
  
  defp maybe_compress(state) do
    metric_count = :ets.info(state.metric_index, :size)
    
    if metric_count > @compression_threshold and state.compression_enabled do
      Process.send_after(self(), :compress_metrics, 100)
    end
    
    state
  end
  
  defp update_stats(state, stat) when is_atom(stat) do
    %{state | stats: Map.update(state.stats, stat, 1, &(&1 + 1))}
  end
  
  defp update_stats(state, {stat, value}) do
    %{state | stats: Map.update(state.stats, stat, value, &(&1 + value))}
  end
  
  defp schedule_sync(state) do
    timer = Process.send_after(self(), :scheduled_sync, @sync_interval)
    %{state | sync_timer: timer}
  end
  
  defp get_last_sync_time do
    # Get from base CRDT store metadata
    case BaseCRDT.get_sync_stats() do
      {:ok, stats} -> stats.last_sync
      _ -> nil
    end
  catch
    _, _ -> nil
  end
  
  defp handle_sync_request(request_data, state) do
    # Handle incoming sync request
    metric_name = request_data.metric
    
    # Send our version of the metric
    if metric_name do
      key = make_metric_key(metric_name)
      
      case BaseCRDT.read_crdt(key) do
        {:ok, value} ->
          # Send back via EventBus
          EventBus.publish(:crdt_sync_response, %{
            metric: metric_name,
            value: value,
            node: node(),
            timestamp: System.os_time(:millisecond)
          })
          
        _ ->
          :ok
      end
    end
  end
end