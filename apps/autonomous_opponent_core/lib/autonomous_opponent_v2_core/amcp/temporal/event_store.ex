defmodule AutonomousOpponentV2Core.AMCP.Temporal.EventStore do
  @moduledoc """
  High-performance temporal event storage for pattern detection.
  
  Provides efficient storage and retrieval of events with HLC timestamps
  for temporal pattern matching. Uses ETS tables optimized for temporal queries.
  
  Features:
  - HLC-based temporal ordering
  - Sliding window queries
  - Event correlation and sequence detection
  - Memory-efficient storage with automatic cleanup
  - VSM subsystem-aware organization
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.Core.HybridLogicalClock
  alias AutonomousOpponentV2Core.Core.Metrics
  alias AutonomousOpponentV2Core.EventBus
  
  @table_events :temporal_events_timeline
  @table_patterns :temporal_pattern_cache
  @table_windows :temporal_active_windows
  @table_sequences :temporal_event_sequences
  
  # Configuration
  @default_retention_ms 3_600_000  # 1 hour
  @cleanup_interval_ms 60_000      # 1 minute
  @max_events_per_window 10_000
  @event_compression_threshold 1000
  
  defstruct [
    :retention_ms,
    :cleanup_timer,
    :pattern_detection_enabled,
    :vsm_subsystem_filters,
    :event_compression_enabled
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Store an event with temporal indexing for pattern detection.
  """
  def store_event(event) do
    GenServer.call(__MODULE__, {:store_event, event})
  end
  
  @doc """
  Store multiple events efficiently.
  """
  def store_events(events) when is_list(events) do
    GenServer.call(__MODULE__, {:store_events, events})
  end
  
  @doc """
  Get events within a time window for pattern analysis.
  """
  def get_events_in_window(window_start, window_end, opts \\ []) do
    GenServer.call(__MODULE__, {:get_events_in_window, window_start, window_end, opts})
  end
  
  @doc """
  Get recent events for a specific subsystem.
  """
  def get_recent_events(subsystem, window_ms \\ 60_000) do
    GenServer.call(__MODULE__, {:get_recent_events, subsystem, window_ms})
  end
  
  @doc """
  Find event sequences matching a pattern.
  """
  def find_event_sequences(pattern_spec, window_ms \\ 300_000) do
    GenServer.call(__MODULE__, {:find_event_sequences, pattern_spec, window_ms})
  end
  
  @doc """
  Correlate events based on temporal and causal relationships.
  """
  def correlate_events(source_event, correlation_rules, window_ms \\ 60_000) do
    GenServer.call(__MODULE__, {:correlate_events, source_event, correlation_rules, window_ms})
  end
  
  @doc """
  Get temporal statistics for monitoring.
  """
  def get_temporal_stats do
    GenServer.call(__MODULE__, :get_temporal_stats)
  end
  
  # GenServer Callbacks
  
  def init(opts) do
    # Create ETS tables for temporal storage
    setup_ets_tables()
    
    # Subscribe to EventBus for real-time event capture
    EventBus.subscribe(:vsm_all_events)
    EventBus.subscribe(:system_event)
    EventBus.subscribe(:algedonic_signal)
    EventBus.subscribe(:pattern_detected)
    
    # Start cleanup timer
    cleanup_timer = Process.send_after(self(), :cleanup_old_events, @cleanup_interval_ms)
    
    state = %__MODULE__{
      retention_ms: opts[:retention_ms] || @default_retention_ms,
      cleanup_timer: cleanup_timer,
      pattern_detection_enabled: opts[:pattern_detection_enabled] || true,
      vsm_subsystem_filters: opts[:vsm_subsystem_filters] || [:all],
      event_compression_enabled: opts[:event_compression_enabled] || true
    }
    
    Logger.info("Temporal Event Store initialized with #{state.retention_ms}ms retention")
    {:ok, state}
  end
  
  def handle_call({:store_event, event}, _from, state) do
    result = do_store_event(event, state)
    {:reply, result, state}
  end
  
  def handle_call({:store_events, events}, _from, state) do
    results = Enum.map(events, &do_store_event(&1, state))
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    
    Metrics.counter(__MODULE__, "events.stored", success_count)
    {:reply, {:ok, success_count}, state}
  end
  
  def handle_call({:get_events_in_window, window_start, window_end, opts}, _from, state) do
    events = do_get_events_in_window(window_start, window_end, opts)
    Metrics.counter(__MODULE__, "queries.window", 1)
    Metrics.gauge(__MODULE__, "query_results.count", length(events))
    {:reply, events, state}
  end
  
  def handle_call({:get_recent_events, subsystem, window_ms}, _from, state) do
    events = do_get_recent_events(subsystem, window_ms)
    {:reply, events, state}
  end
  
  def handle_call({:find_event_sequences, pattern_spec, window_ms}, _from, state) do
    sequences = do_find_event_sequences(pattern_spec, window_ms)
    {:reply, sequences, state}
  end
  
  def handle_call({:correlate_events, source_event, correlation_rules, window_ms}, _from, state) do
    correlations = do_correlate_events(source_event, correlation_rules, window_ms)
    {:reply, correlations, state}
  end
  
  def handle_call(:get_temporal_stats, _from, state) do
    stats = do_get_temporal_stats()
    {:reply, stats, state}
  end
  
  def handle_info({:event_bus_hlc, event}, state) do
    # Real-time event capture from EventBus
    do_store_event(event, state)
    {:noreply, state}
  end
  
  def handle_info(:cleanup_old_events, state) do
    cleanup_count = do_cleanup_old_events(state.retention_ms)
    
    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_old_events, @cleanup_interval_ms)
    
    Metrics.counter(__MODULE__, "events.cleaned_up", cleanup_count)
    Logger.debug("Cleaned up #{cleanup_count} old events")
    
    {:noreply, %{state | cleanup_timer: cleanup_timer}}
  end
  
  def handle_info(msg, state) do
    Logger.debug("Temporal EventStore received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:record, _metric_type, _metric_name, _value, _tags}, state) do
    # Metrics recording - ignore to prevent circular dependency
    # EventStore generates metrics but shouldn't record its own metrics
    {:noreply, state}
  end
  
  def handle_cast(msg, state) do
    Logger.debug("Temporal EventStore received unexpected cast: #{inspect(msg)}")
    {:noreply, state}
  end
  
  # Private Implementation
  
  defp setup_ets_tables do
    # Main events timeline - ordered by HLC timestamp
    :ets.new(@table_events, [
      :ordered_set,
      :named_table,
      :public,
      {:write_concurrency, true},
      {:read_concurrency, true}
    ])
    
    # Pattern cache for frequently accessed patterns
    :ets.new(@table_patterns, [
      :set,
      :named_table,
      :public,
      {:write_concurrency, true}
    ])
    
    # Active temporal windows for sliding window queries
    :ets.new(@table_windows, [
      :bag,
      :named_table,
      :public,
      {:write_concurrency, true}
    ])
    
    # Event sequences for temporal pattern detection
    :ets.new(@table_sequences, [
      :bag,
      :named_table,
      :public,
      {:write_concurrency, true}
    ])
  end
  
  defp do_store_event(event, state) do
    try do
      # Ensure event has proper temporal structure
      temporal_event = normalize_temporal_event(event)
      
      # Create storage key: {physical_time, logical_time, node_id, event_id}
      storage_key = create_storage_key(temporal_event)
      
      # Compress event data if enabled and over threshold
      stored_data = if state.event_compression_enabled and 
                       byte_size(:erlang.term_to_binary(temporal_event)) > @event_compression_threshold do
        compress_event_data(temporal_event)
      else
        temporal_event
      end
      
      # Store in main timeline
      :ets.insert(@table_events, {storage_key, stored_data})
      
      # Update sequence tracking if this is part of a sequence
      update_sequence_tracking(temporal_event)
      
      # Update pattern cache if pattern detection is enabled
      if state.pattern_detection_enabled do
        update_pattern_cache(temporal_event)
      end
      
      Metrics.counter(__MODULE__, "events.stored", 1, %{
        subsystem: temporal_event[:subsystem] || :unknown,
        type: temporal_event[:type] || :unknown
      })
      
      {:ok, storage_key}
    rescue
      error ->
        Logger.error("Failed to store temporal event: #{inspect(error)}")
        {:error, error}
    end
  end
  
  defp do_get_events_in_window(window_start, window_end, opts) do
    start_key = normalize_window_boundary(window_start)
    end_key = normalize_window_boundary(window_end)
    
    # Query events between boundaries
    match_spec = [
      {{:'$1', :'$2'}, 
       [{:andalso, {:>=, :'$1', start_key}, {:'=<', :'$1', end_key}}], 
       [:'$2']}
    ]
    
    events = :ets.select(@table_events, match_spec)
    
    # Apply filters if specified
    filtered_events = apply_event_filters(events, opts)
    
    # Decompress if necessary
    decompressed_events = Enum.map(filtered_events, &decompress_event_data/1)
    
    # Order by HLC timestamp
    Clock.order_events(decompressed_events)
  end
  
  defp do_get_recent_events(subsystem, window_ms) do
    case Clock.now() do
      {:ok, current_time} ->
        window_start = current_time.physical - window_ms
        
        # Create boundary for recent events
        start_boundary = %{
          physical: window_start,
          logical: 0,
          node_id: ""
        }
        
        events = do_get_events_in_window(start_boundary, current_time, [
          subsystem_filter: subsystem
        ])
        
        events
        
      {:error, error} ->
        Logger.error("Failed to get current time for recent events: #{inspect(error)}")
        []
    end
  end
  
  defp do_find_event_sequences(pattern_spec, window_ms) do
    case Clock.now() do
      {:ok, current_time} ->
        window_start = current_time.physical - window_ms
        
        # Get all events in window
        events = do_get_events_in_window(
          %{physical: window_start, logical: 0, node_id: ""},
          current_time,
          []
        )
        
        # Find sequences matching pattern
        find_matching_sequences(events, pattern_spec)
        
      {:error, _} -> []
    end
  end
  
  defp do_correlate_events(source_event, correlation_rules, window_ms) do
    case Clock.now() do
      {:ok, current_time} ->
        # Get events in correlation window
        window_start = source_event.timestamp.physical - window_ms
        window_end = source_event.timestamp.physical + window_ms
        
        candidate_events = do_get_events_in_window(
          %{physical: window_start, logical: 0, node_id: ""},
          %{physical: window_end, logical: 999_999, node_id: "zzz"},
          []
        )
        
        # Apply correlation rules
        apply_correlation_rules(source_event, candidate_events, correlation_rules)
        
      {:error, _} -> []
    end
  end
  
  defp do_get_temporal_stats do
    event_count = :ets.info(@table_events, :size)
    pattern_cache_size = :ets.info(@table_patterns, :size)
    sequence_count = :ets.info(@table_sequences, :size)
    
    memory_usage = (:ets.info(@table_events, :memory) +
                   :ets.info(@table_patterns, :memory) +
                   :ets.info(@table_sequences, :memory)) * :erlang.system_info(:wordsize)
    
    %{
      total_events: event_count,
      pattern_cache_entries: pattern_cache_size,
      tracked_sequences: sequence_count,
      memory_usage_bytes: memory_usage,
      timestamp: Clock.now()
    }
  end
  
  defp do_cleanup_old_events(retention_ms) do
    case Clock.now() do
      {:ok, current_time} ->
        cutoff_time = current_time.physical - retention_ms
        
        # Delete old events
        deleted_count = :ets.select_delete(@table_events, [
          {{:'$1', :'$2'}, 
           [{:<, {:element, 1, :'$1'}, cutoff_time}], 
           [true]}
        ])
        
        # Clean up pattern cache
        :ets.select_delete(@table_patterns, [
          {{:'$1', :'$2'}, 
           [{:<, {:element, 1, :'$1'}, cutoff_time}], 
           [true]}
        ])
        
        deleted_count
        
      {:error, _} -> 0
    end
  end
  
  # Helper Functions
  
  defp normalize_temporal_event(event) do
    cond do
      # Already has HLC timestamp
      is_map(event) and Map.has_key?(event, :timestamp) and 
      is_map(event.timestamp) and Map.has_key?(event.timestamp, :physical) ->
        event
        
      # Has timestamp but needs conversion to HLC
      is_map(event) and Map.has_key?(event, :timestamp) ->
        case Clock.now() do
          {:ok, hlc_timestamp} ->
            Map.put(event, :timestamp, hlc_timestamp)
          {:error, _} ->
            event
        end
        
      # No timestamp - add current HLC timestamp
      is_map(event) ->
        case Clock.now() do
          {:ok, hlc_timestamp} ->
            Map.put(event, :timestamp, hlc_timestamp)
          {:error, _} ->
            event
        end
        
      # Not a map - wrap it
      true ->
        case Clock.now() do
          {:ok, hlc_timestamp} ->
            %{
              data: event,
              timestamp: hlc_timestamp,
              type: :raw_data
            }
          {:error, _} ->
            %{data: event, type: :raw_data}
        end
    end
  end
  
  defp create_storage_key(%{timestamp: timestamp} = event) do
    event_id = event[:id] || :crypto.strong_rand_bytes(8) |> Base.encode16()
    {timestamp.physical, timestamp.logical, timestamp.node_id, event_id}
  end
  
  defp normalize_window_boundary(%{physical: physical, logical: logical, node_id: node_id}) do
    {physical, logical, node_id, ""}
  end
  
  defp normalize_window_boundary(timestamp) when is_integer(timestamp) do
    {timestamp, 0, "", ""}
  end
  
  defp compress_event_data(event) do
    compressed = :erlang.term_to_binary(event, [:compressed])
    %{compressed: true, data: compressed}
  end
  
  defp decompress_event_data(%{compressed: true, data: compressed_data}) do
    :erlang.binary_to_term(compressed_data)
  end
  
  defp decompress_event_data(event), do: event
  
  defp apply_event_filters(events, opts) do
    events
    |> filter_by_subsystem(opts[:subsystem_filter])
    |> filter_by_type(opts[:type_filter])
    |> filter_by_urgency(opts[:urgency_filter])
  end
  
  defp filter_by_subsystem(events, nil), do: events
  defp filter_by_subsystem(events, subsystem) do
    Enum.filter(events, fn event ->
      event[:subsystem] == subsystem
    end)
  end
  
  defp filter_by_type(events, nil), do: events
  defp filter_by_type(events, type) do
    Enum.filter(events, fn event ->
      event[:type] == type
    end)
  end
  
  defp filter_by_urgency(events, nil), do: events
  defp filter_by_urgency(events, min_urgency) do
    Enum.filter(events, fn event ->
      urgency = event[:urgency] || 0
      urgency >= min_urgency
    end)
  end
  
  defp update_sequence_tracking(event) do
    # Track event sequences for pattern detection
    sequence_key = {
      event[:subsystem] || :unknown,
      event[:type] || :unknown,
      event.timestamp.physical
    }
    
    :ets.insert(@table_sequences, {sequence_key, event})
  end
  
  defp update_pattern_cache(event) do
    # Cache frequently accessed patterns for performance
    pattern_key = {
      event[:subsystem] || :unknown,
      event[:type] || :unknown
    }
    
    current_time = System.monotonic_time(:millisecond)
    :ets.insert(@table_patterns, {pattern_key, event, current_time})
  end
  
  defp find_matching_sequences(events, pattern_spec) do
    # Simple sequence detection - can be enhanced with more sophisticated algorithms
    sequence_length = pattern_spec[:sequence_length] || 2
    max_gap_ms = pattern_spec[:max_gap_ms] || 10_000
    
    events
    |> Enum.chunk_every(sequence_length, 1, :discard)
    |> Enum.filter(fn sequence ->
      is_valid_sequence?(sequence, max_gap_ms)
    end)
  end
  
  defp is_valid_sequence?([first | rest], max_gap_ms) do
    Enum.reduce_while(rest, first, fn current, previous ->
      gap = current.timestamp.physical - previous.timestamp.physical
      if gap <= max_gap_ms do
        {:cont, current}
      else
        {:halt, false}
      end
    end) != false
  end
  
  defp apply_correlation_rules(source_event, candidate_events, correlation_rules) do
    Enum.filter(candidate_events, fn candidate ->
      Enum.any?(correlation_rules, fn rule ->
        check_correlation_rule(source_event, candidate, rule)
      end)
    end)
  end
  
  defp check_correlation_rule(source, candidate, rule) do
    case rule do
      {:same_subsystem} ->
        source[:subsystem] == candidate[:subsystem]
        
      {:causal_relationship} ->
        HybridLogicalClock.before?(source.timestamp, candidate.timestamp)
        
      {:type_correlation, type1, type2} ->
        source[:type] == type1 and candidate[:type] == type2
        
      {:custom, func} when is_function(func, 2) ->
        func.(source, candidate)
        
      _ -> false
    end
  end
end