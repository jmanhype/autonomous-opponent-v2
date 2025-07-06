defmodule AutonomousOpponentV2Core.AMCP.Events.SemanticFusion do
  @moduledoc """
  Semantic Fusion Engine for aMCP event processing.
  
  Fuses multiple event streams into semantically meaningful contexts,
  enabling the cybernetic consciousness to understand causality,
  relationships, and emergent patterns across distributed events.
  
  Key capabilities:
  - Event correlation across time and space
  - Causal chain detection
  - Pattern emergence identification
  - Semantic context enrichment
  - Priority-based fusion strategies
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  # Removed unused alias CRDTStore
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  
  defstruct [
    :fusion_rules,
    :event_buffer,
    :context_graph,
    :pattern_cache,
    :causal_chains,
    :fusion_stats
  ]
  
  @event_buffer_size 1000
  @pattern_ttl_seconds 3600  # 1 hour
  @fusion_interval_ms 500    # Process every 500ms (reduced from 100ms for performance)
  @max_event_buffer_size 10_000  # Maximum events to keep in buffer
  @max_pattern_cache_size 1_000  # Maximum patterns to cache
  @max_causal_chains 100       # Maximum causal chains to maintain
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Submits an event for semantic fusion.
  """
  def fuse_event(event_name, event_data) do
    GenServer.cast(__MODULE__, {:fuse_event, event_name, event_data})
  end
  
  @doc """
  Gets the current semantic context for a given topic.
  """
  def get_context(topic) do
    GenServer.call(__MODULE__, {:get_context, topic})
  end
  
  @doc """
  Queries for causal chains matching a pattern.
  """
  def query_causality(pattern) do
    GenServer.call(__MODULE__, {:query_causality, pattern})
  end
  
  @doc """
  Gets detected patterns within a time window.
  """
  def get_patterns(time_window_seconds \\ 300) do
    GenServer.call(__MODULE__, {:get_patterns, time_window_seconds})
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to specific events for fusion
    EventBus.subscribe(:user_interaction)
    EventBus.subscribe(:system_performance)
    EventBus.subscribe(:pattern_detected)
    EventBus.subscribe(:consciousness_response)
    EventBus.subscribe(:consciousness_error)
    EventBus.subscribe(:consciousness_reflection_requested)
    EventBus.subscribe(:consciousness_reflection_completed)
    EventBus.subscribe(:consciousness_query)
    EventBus.subscribe(:consciousness_state_retrieved)
    EventBus.subscribe(:amcp_crdt_created)
    EventBus.subscribe(:amcp_crdt_updated)
    EventBus.subscribe(:vsm_state_change)
    EventBus.subscribe(:algedonic_signal)
    EventBus.subscribe(:consciousness_update)
    EventBus.subscribe(:s4_intelligence)
    EventBus.subscribe(:s5_policy)
    
    # Start fusion timer
    :timer.send_interval(@fusion_interval_ms, :perform_fusion)
    
    # Start cleanup timer (every 5 minutes)
    :timer.send_interval(300_000, :perform_cleanup)
    
    state = %__MODULE__{
      fusion_rules: init_fusion_rules(),
      event_buffer: :queue.new(),
      context_graph: %{},
      pattern_cache: %{},
      causal_chains: [],
      fusion_stats: init_stats()
    }
    
    Logger.info("Semantic Fusion Engine initialized with performance optimizations")
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:fuse_event, event_name, event_data}, state) do
    # Add event to buffer with metadata
    enriched_event = enrich_event(event_name, event_data)
    
    new_buffer = add_to_buffer(state.event_buffer, enriched_event)
    new_state = %{state | event_buffer: new_buffer}
    
    # Update stats
    new_stats = increment_stat(new_state.fusion_stats, :events_received)
    
    {:noreply, %{new_state | fusion_stats: new_stats}}
  end
  
  @impl true
  def handle_call({:get_context, topic}, _from, state) do
    context = Map.get(state.context_graph, topic, %{})
    {:reply, {:ok, context}, state}
  end
  
  @impl true
  def handle_call({:query_causality, pattern}, _from, state) do
    matching_chains = Enum.filter(state.causal_chains, fn chain ->
      matches_pattern?(chain, pattern)
    end)
    
    {:reply, {:ok, matching_chains}, state}
  end
  
  @impl true
  def handle_call({:get_patterns, time_window}, _from, state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -time_window, :second)
    
    recent_patterns = state.pattern_cache
    |> Enum.filter(fn {_pattern_id, pattern_data} ->
      DateTime.compare(pattern_data.detected_at, cutoff_time) == :gt
    end)
    |> Enum.map(fn {_, pattern_data} -> pattern_data end)
    
    # Enhance patterns with LLM explanations
    enhanced_patterns = case enhance_patterns_with_llm(recent_patterns) do
      {:ok, enhanced} -> enhanced
      {:error, _reason} -> recent_patterns  # Fallback to original patterns
    end
    
    {:reply, {:ok, enhanced_patterns}, state}
  end
  
  @impl true
  def handle_info(:perform_fusion, state) do
    # Get events from buffer
    {events_to_fuse, remaining_buffer} = extract_fusion_batch(state.event_buffer)
    
    if length(events_to_fuse) > 0 do
      # Perform semantic fusion
      new_state = events_to_fuse
      |> fuse_events(state)
      |> detect_patterns()
      |> update_causal_chains()
      |> enrich_contexts()
      
      # Update buffer and stats
      new_stats = increment_stat(new_state.fusion_stats, :fusion_cycles)
      
      {:noreply, %{new_state | 
        event_buffer: remaining_buffer,
        fusion_stats: new_stats
      }}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event_bus, event_name, event_data}, state) do
    # Handle EventBus events directly
    Logger.debug("SemanticFusion received event: #{event_name}")
    
    # Add event to buffer with metadata (same logic as handle_cast)
    enriched_event = enrich_event(event_name, event_data)
    
    new_buffer = add_to_buffer(state.event_buffer, enriched_event)
    new_state = %{state | event_buffer: new_buffer}
    
    # Update stats
    new_stats = increment_stat(new_state.fusion_stats, :events_received)
    
    {:noreply, %{new_state | fusion_stats: new_stats}}
  end
  
  @impl true
  def handle_info(:perform_cleanup, state) do
    # Periodic cleanup to prevent memory leaks
    Logger.debug("Performing periodic cleanup of SemanticFusion state")
    
    # Clean context graph - remove old contexts
    cutoff_time = DateTime.add(DateTime.utc_now(), -3600, :second)  # 1 hour
    cleaned_context = state.context_graph
    |> Enum.filter(fn {_key, context} ->
      case context do
        %{timestamp: ts} -> DateTime.compare(ts, cutoff_time) == :gt
        _ -> true
      end
    end)
    |> Map.new()
    
    # Log cleanup stats
    original_context_size = map_size(state.context_graph)
    cleaned_context_size = map_size(cleaned_context)
    if original_context_size > cleaned_context_size do
      Logger.info("Cleaned up #{original_context_size - cleaned_context_size} old contexts")
    end
    
    {:noreply, %{state | context_graph: cleaned_context}}
  end
  
  # Private Functions
  
  defp init_fusion_rules do
    # Define semantic fusion rules
    %{
      # VSM subsystem interactions
      vsm_coordination: %{
        events: [:s1_operations, :s2_coordination, :s3_control],
        window: 1000,  # 1 second
        fusion_fn: &fuse_vsm_coordination/1
      },
      
      # Algedonic response patterns
      algedonic_response: %{
        events: [:algedonic_signal, :vsm_adaptation, :policy_change],
        window: 5000,  # 5 seconds
        fusion_fn: &fuse_algedonic_response/1
      },
      
      # Consciousness state changes
      consciousness_evolution: %{
        events: [:consciousness_update, :belief_change, :memory_update],
        window: 2000,  # 2 seconds
        fusion_fn: &fuse_consciousness_evolution/1
      },
      
      # Environmental adaptation
      environmental_response: %{
        events: [:environmental_change, :s4_intelligence, :strategic_update],
        window: 10000,  # 10 seconds
        fusion_fn: &fuse_environmental_response/1
      },
      
      # Error cascades
      error_cascade: %{
        events: [:error, :failure, :circuit_break],
        window: 500,  # 0.5 seconds
        fusion_fn: &fuse_error_cascade/1
      }
    }
  end
  
  defp init_stats do
    %{
      events_received: 0,
      fusion_cycles: 0,
      patterns_detected: 0,
      causal_chains_identified: 0,
      contexts_enriched: 0,
      started_at: DateTime.utc_now()
    }
  end
  
  defp enrich_event(event_name, event_data) do
    %{
      name: event_name,
      data: event_data,
      timestamp: DateTime.utc_now(),
      id: generate_event_id(),
      metadata: extract_metadata(event_name, event_data)
    }
  end
  
  defp extract_metadata(event_name, event_data) do
    %{
      source: event_data[:source] || :unknown,
      priority: event_data[:priority] || calculate_priority(event_name),
      subsystem: identify_subsystem(event_name),
      semantic_tags: generate_semantic_tags(event_name, event_data)
    }
  end
  
  defp calculate_priority(:algedonic_signal), do: :critical
  defp calculate_priority(:consciousness_update), do: :high
  defp calculate_priority(:vsm_state_change), do: :high
  defp calculate_priority(:error), do: :high
  defp calculate_priority(_), do: :normal
  
  defp identify_subsystem(event_name) do
    cond do
      String.contains?(to_string(event_name), "s1") -> :s1_operations
      String.contains?(to_string(event_name), "s2") -> :s2_coordination
      String.contains?(to_string(event_name), "s3") -> :s3_control
      String.contains?(to_string(event_name), "s4") -> :s4_intelligence
      String.contains?(to_string(event_name), "s5") -> :s5_policy
      String.contains?(to_string(event_name), "algedonic") -> :algedonic
      String.contains?(to_string(event_name), "consciousness") -> :consciousness
      true -> :general
    end
  end
  
  defp generate_semantic_tags(event_name, event_data) do
    base_tags = [event_name]
    
    # Add data-driven tags
    data_tags = case event_data do
      %{type: type} -> [type]
      %{action: action} -> [action]
      %{category: cat} -> [cat]
      _ -> []
    end
    
    # Add semantic relationships
    semantic_tags = infer_semantic_tags(event_name, event_data)
    
    Enum.uniq(base_tags ++ data_tags ++ semantic_tags)
  end
  
  defp infer_semantic_tags(event_name, _event_data) do
    # Infer additional semantic meaning
    cond do
      String.contains?(to_string(event_name), "error") -> [:failure, :attention_required]
      String.contains?(to_string(event_name), "success") -> [:positive_reinforcement]
      String.contains?(to_string(event_name), "update") -> [:state_change, :adaptation]
      true -> []
    end
  end
  
  defp add_to_buffer(buffer, event) do
    new_buffer = :queue.in(event, buffer)
    
    # Maintain buffer size limit more aggressively
    current_size = :queue.len(new_buffer)
    
    cond do
      current_size > @max_event_buffer_size ->
        # Emergency trim - drop many old events
        Logger.warning("Event buffer exceeded max size (#{current_size}), dropping old events")
        drop_count = current_size - @event_buffer_size
        drop_from_queue(new_buffer, drop_count)
        
      current_size > @event_buffer_size ->
        # Normal trim - remove one
        {_, trimmed} = :queue.out(new_buffer)
        trimmed
        
      true ->
        new_buffer
    end
  end
  
  defp drop_from_queue(queue, 0), do: queue
  defp drop_from_queue(queue, count) do
    case :queue.out(queue) do
      {{:value, _}, new_queue} -> drop_from_queue(new_queue, count - 1)
      {:empty, queue} -> queue
    end
  end
  
  defp extract_fusion_batch(buffer) do
    # Extract up to 50 events for fusion
    extract_from_queue(buffer, 50, [])
  end
  
  defp extract_from_queue(queue, 0, acc), do: {Enum.reverse(acc), queue}
  defp extract_from_queue(queue, n, acc) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        extract_from_queue(new_queue, n - 1, [item | acc])
      {:empty, queue} ->
        {Enum.reverse(acc), queue}
    end
  end
  
  defp fuse_events(events, state) do
    # Apply fusion rules to event batch
    Enum.reduce(state.fusion_rules, state, fn {rule_name, rule}, acc_state ->
      apply_fusion_rule(rule_name, rule, events, acc_state)
    end)
  end
  
  defp apply_fusion_rule(rule_name, rule, events, state) do
    # Find events matching the rule within time window
    matching_events = find_matching_events(events, rule.events, rule.window)
    
    if length(matching_events) >= 2 do
      # Apply fusion function
      case rule.fusion_fn.(matching_events) do
        {:ok, fused_context} ->
          # Update context graph
          new_context_graph = Map.put(state.context_graph, rule_name, fused_context)
          
          # Publish fused context
          EventBus.publish(:semantic_fusion_complete, %{
            rule: rule_name,
            context: fused_context,
            source_events: Enum.map(matching_events, & &1.id)
          })
          
          %{state | context_graph: new_context_graph}
          
        _ ->
          state
      end
    else
      state
    end
  end
  
  defp find_matching_events(events, event_types, time_window_ms) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -time_window_ms, :millisecond)
    
    events
    |> Enum.filter(fn event ->
      Enum.member?(event_types, event.name) and
      DateTime.compare(event.timestamp, cutoff_time) == :gt
    end)
  end
  
  defp detect_patterns(state) do
    # Pattern detection logic
    new_patterns = detect_event_patterns(state.event_buffer)
    
    # Update pattern cache with size limit
    updated_cache = Enum.reduce(new_patterns, state.pattern_cache, fn pattern, cache ->
      # If cache is full, remove oldest pattern first
      cache_to_use = if map_size(cache) >= @max_pattern_cache_size do
        # Find and remove oldest pattern
        cache
        |> Enum.min_by(fn {_id, p} -> p.detected_at end, fn -> nil end)
        |> case do
          {id, _} -> Map.delete(cache, id)
          _ -> cache
        end
      else
        cache
      end
      
      Map.put(cache_to_use, pattern.id, pattern)
    end)
    
    # Clean old patterns (TTL-based)
    cleaned_cache = clean_old_patterns(updated_cache)
    
    # Update stats
    new_stats = Map.update(state.fusion_stats, :patterns_detected, 
                          length(new_patterns), &(&1 + length(new_patterns)))
    
    %{state | 
      pattern_cache: cleaned_cache,
      fusion_stats: new_stats
    }
  end
  
  defp detect_event_patterns(event_buffer) do
    # Convert queue to list for pattern analysis
    events = :queue.to_list(event_buffer)
    
    # Detect various pattern types
    patterns = []
    |> detect_frequency_patterns(events)
    |> detect_sequence_patterns(events)
    |> detect_correlation_patterns(events)
    |> detect_anomaly_patterns(events)
    |> detect_trend_patterns(events)
    |> detect_periodic_patterns(events)
    
    patterns
  end
  
  defp detect_frequency_patterns(patterns, events) do
    # Detect high-frequency event patterns
    event_counts = Enum.frequencies_by(events, & &1.name)
    
    high_freq_patterns = event_counts
    |> Enum.filter(fn {_, count} -> count > 5 end)
    |> Enum.map(fn {event_name, count} ->
      %{
        id: generate_pattern_id(),
        type: :high_frequency,
        pattern: %{event: event_name, count: count},
        detected_at: DateTime.utc_now(),
        confidence: calculate_frequency_confidence(count)
      }
    end)
    
    patterns ++ high_freq_patterns
  end
  
  defp detect_sequence_patterns(patterns, events) do
    # Detect sequential patterns (A always followed by B)
    sequences = events
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [e1, e2] -> {e1.name, e2.name} end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count > 2 end)
    |> Enum.map(fn {{event1, event2}, count} ->
      %{
        id: generate_pattern_id(),
        type: :sequence,
        pattern: %{sequence: [event1, event2], count: count},
        detected_at: DateTime.utc_now(),
        confidence: calculate_sequence_confidence(count)
      }
    end)
    
    patterns ++ sequences
  end
  
  defp detect_correlation_patterns(patterns, events) do
    # Detect correlated events using statistical analysis
    
    # Group events by time windows (sliding window approach)
    window_size_ms = 1000  # 1 second windows
    slide_ms = 500         # 500ms slide
    
    time_windows = create_sliding_windows(events, window_size_ms, slide_ms)
    
    # Calculate event co-occurrence matrix
    cooccurrence_matrix = calculate_cooccurrence_matrix(time_windows)
    
    # Find statistically significant correlations
    correlations = cooccurrence_matrix
    |> Enum.filter(fn {{event1, event2}, stats} ->
      event1 != event2 and stats.correlation > 0.6 and stats.count > 3
    end)
    |> Enum.map(fn {{event1, event2}, stats} ->
      %{
        id: generate_pattern_id(),
        type: :correlation,
        pattern: %{
          correlated_events: [event1, event2],
          correlation_coefficient: stats.correlation,
          co_occurrence_count: stats.count,
          time_lag: stats.avg_time_lag
        },
        detected_at: DateTime.utc_now(),
        confidence: calculate_correlation_confidence(stats)
      }
    end)
    
    # Also detect multi-event correlations (3+ events)
    multi_correlations = detect_multi_event_correlations(time_windows)
    
    patterns ++ correlations ++ multi_correlations
  end
  
  defp create_sliding_windows([], _window_size_ms, _slide_ms), do: []
  defp create_sliding_windows(events, window_size_ms, slide_ms) do
    sorted_events = Enum.sort_by(events, & &1.timestamp, DateTime)
    first_time = List.first(sorted_events).timestamp
    last_time = List.last(sorted_events).timestamp
    
    # Generate window start times
    window_starts = generate_window_starts(first_time, last_time, slide_ms)
    
    # Create windows
    Enum.map(window_starts, fn start_time ->
      end_time = DateTime.add(start_time, window_size_ms, :millisecond)
      
      events_in_window = Enum.filter(sorted_events, fn event ->
        DateTime.compare(event.timestamp, start_time) != :lt and
        DateTime.compare(event.timestamp, end_time) == :lt
      end)
      
      %{
        start: start_time,
        end: end_time,
        events: events_in_window
      }
    end)
    |> Enum.filter(fn window -> length(window.events) > 0 end)
  end
  
  defp generate_window_starts(first_time, last_time, slide_ms) do
    duration_ms = DateTime.diff(last_time, first_time, :millisecond)
    num_windows = max(1, div(duration_ms, slide_ms))
    
    Enum.map(0..num_windows, fn i ->
      DateTime.add(first_time, i * slide_ms, :millisecond)
    end)
  end
  
  defp calculate_cooccurrence_matrix(time_windows) do
    # Initialize co-occurrence tracking
    cooccurrences = %{}
    
    Enum.reduce(time_windows, cooccurrences, fn window, acc ->
      event_names = window.events |> Enum.map(& &1.name) |> Enum.uniq()
      
      # Calculate pairwise co-occurrences
      pairs = for e1 <- event_names, e2 <- event_names, e1 < e2, do: {e1, e2}
      
      Enum.reduce(pairs, acc, fn {event1, event2}, acc2 ->
        # Calculate time lag between events
        time_lag = calculate_average_time_lag(window.events, event1, event2)
        
        Map.update(acc2, {event1, event2}, 
          %{count: 1, time_lags: [time_lag], correlation: 0.0},
          fn stats ->
            %{stats | 
              count: stats.count + 1,
              time_lags: [time_lag | stats.time_lags]
            }
          end
        )
      end)
    end)
    |> calculate_correlation_coefficients(time_windows)
  end
  
  defp calculate_average_time_lag(events, event1_name, event2_name) do
    event1_times = events
    |> Enum.filter(fn e -> e.name == event1_name end)
    |> Enum.map(& &1.timestamp)
    
    event2_times = events
    |> Enum.filter(fn e -> e.name == event2_name end)
    |> Enum.map(& &1.timestamp)
    
    if event1_times != [] and event2_times != [] do
      # Calculate average time difference
      avg_time1 = average_datetime(event1_times)
      avg_time2 = average_datetime(event2_times)
      DateTime.diff(avg_time2, avg_time1, :millisecond)
    else
      0
    end
  end
  
  defp average_datetime(datetimes) do
    avg_unix = datetimes
    |> Enum.map(&DateTime.to_unix(&1, :millisecond))
    |> Enum.sum()
    |> div(length(datetimes))
    
    DateTime.from_unix!(avg_unix, :millisecond)
  end
  
  defp calculate_correlation_coefficients(cooccurrences, time_windows) do
    # Calculate correlation based on co-occurrence frequency
    total_windows = length(time_windows)
    
    Map.new(cooccurrences, fn {{event1, event2}, stats} ->
      avg_time_lag = if stats.time_lags != [] do
        Enum.sum(stats.time_lags) / length(stats.time_lags)
      else
        0
      end
      
      # Simple correlation: co-occurrence frequency / total windows
      correlation = stats.count / max(1, total_windows)
      
      {{event1, event2}, %{stats | 
        correlation: correlation,
        avg_time_lag: avg_time_lag
      }}
    end)
  end
  
  defp detect_multi_event_correlations(time_windows) do
    # Find groups of 3+ events that frequently occur together
    time_windows
    |> Enum.map(fn window ->
      window.events |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.sort()
    end)
    |> Enum.filter(fn group -> length(group) >= 3 end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count >= 2 end)
    |> Enum.map(fn {event_group, count} ->
      %{
        id: generate_pattern_id(),
        type: :multi_correlation,
        pattern: %{
          correlated_events: event_group,
          occurrence_count: count
        },
        detected_at: DateTime.utc_now(),
        confidence: calculate_multi_correlation_confidence(count, length(event_group))
      }
    end)
  end
  
  defp calculate_correlation_confidence(stats) do
    # Confidence based on correlation strength and sample size
    base_confidence = stats.correlation
    sample_factor = min(1.0, stats.count / 10.0)
    base_confidence * sample_factor
  end
  
  defp calculate_multi_correlation_confidence(count, group_size) do
    # Higher confidence for larger groups that occur frequently
    base = count / 10.0
    size_bonus = (group_size - 2) * 0.1
    min(1.0, base + size_bonus)
  end
  
  defp detect_anomaly_patterns(patterns, events) do
    # Detect anomalous events based on statistical analysis
    
    # Group events by type
    events_by_type = Enum.group_by(events, & &1.name)
    
    anomalies = Enum.flat_map(events_by_type, fn {event_type, type_events} ->
      if length(type_events) >= 5 do
        # Calculate inter-arrival times
        inter_arrival_times = calculate_inter_arrival_times(type_events)
        
        if length(inter_arrival_times) > 0 do
          # Calculate mean and standard deviation
          mean = Enum.sum(inter_arrival_times) / length(inter_arrival_times)
          std_dev = calculate_std_dev(inter_arrival_times, mean)
          
          # Find anomalies (events with unusual timing)
          type_events
          |> Enum.zip([:first | inter_arrival_times])
          |> Enum.filter(fn {_event, iat} ->
            iat != :first and abs(iat - mean) > 2 * std_dev
          end)
          |> Enum.map(fn {event, iat} ->
            %{
              id: generate_pattern_id(),
              type: :anomaly,
              pattern: %{
                event_type: event_type,
                event_id: event.id,
                inter_arrival_time: iat,
                expected_range: {mean - 2 * std_dev, mean + 2 * std_dev},
                deviation: abs(iat - mean) / std_dev
              },
              detected_at: DateTime.utc_now(),
              confidence: calculate_anomaly_confidence(abs(iat - mean) / std_dev)
            }
          end)
        else
          []
        end
      else
        []
      end
    end)
    
    patterns ++ anomalies
  end
  
  defp detect_trend_patterns(patterns, events) do
    # Detect trending patterns in event frequencies over time
    
    # Group events by type and time buckets
    time_bucket_size = 10_000  # 10 seconds
    events_by_type_and_time = group_by_type_and_time(events, time_bucket_size)
    
    trends = Enum.flat_map(events_by_type_and_time, fn {event_type, time_buckets} ->
      if map_size(time_buckets) >= 3 do
        # Sort by time and get counts
        sorted_buckets = time_buckets
        |> Enum.sort_by(fn {time, _} -> time end)
        |> Enum.map(fn {_, count} -> count end)
        
        # Calculate trend using linear regression
        trend = calculate_trend(sorted_buckets)
        
        if abs(trend.slope) > 0.1 do  # Significant trend
          [%{
            id: generate_pattern_id(),
            type: :trend,
            pattern: %{
              event_type: event_type,
              direction: if(trend.slope > 0, do: :increasing, else: :decreasing),
              slope: trend.slope,
              r_squared: trend.r_squared,
              data_points: sorted_buckets
            },
            detected_at: DateTime.utc_now(),
            confidence: trend.r_squared  # Use R² as confidence
          }]
        else
          []
        end
      else
        []
      end
    end)
    
    patterns ++ trends
  end
  
  defp detect_periodic_patterns(patterns, events) do
    # Detect periodic/cyclical patterns using autocorrelation
    
    events_by_type = Enum.group_by(events, & &1.name)
    
    periodicities = Enum.flat_map(events_by_type, fn {event_type, type_events} ->
      if length(type_events) >= 10 do
        # Convert to time series
        time_series = events_to_time_series(type_events)
        
        # Calculate autocorrelation for different lags
        autocorrelations = calculate_autocorrelations(time_series, 1..10)
        
        # Find significant peaks (indicating periodicity)
        _periodic_lags = autocorrelations
        |> Enum.filter(fn {_lag, correlation} -> correlation > 0.5 end)
        |> Enum.map(fn {lag, correlation} ->
          %{
            id: generate_pattern_id(),
            type: :periodic,
            pattern: %{
              event_type: event_type,
              period_ms: lag * 1000,  # Convert to milliseconds
              correlation: correlation,
              sample_size: length(type_events)
            },
            detected_at: DateTime.utc_now(),
            confidence: correlation
          }
        end)
      else
        []
      end
    end)
    
    patterns ++ periodicities
  end
  
  defp calculate_inter_arrival_times(events) do
    events
    |> Enum.sort_by(& &1.timestamp, DateTime)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [e1, e2] ->
      DateTime.diff(e2.timestamp, e1.timestamp, :millisecond)
    end)
  end
  
  defp calculate_std_dev(values, mean) do
    variance = values
    |> Enum.map(fn v -> :math.pow(v - mean, 2) end)
    |> Enum.sum()
    |> Kernel./(length(values))
    
    :math.sqrt(variance)
  end
  
  defp calculate_anomaly_confidence(z_score) do
    # Higher z-score = higher confidence in anomaly
    min(1.0, z_score / 5.0)
  end
  
  defp group_by_type_and_time(events, bucket_size) do
    events
    |> Enum.group_by(& &1.name)
    |> Map.new(fn {event_type, type_events} ->
      time_buckets = type_events
      |> Enum.group_by(fn event ->
        # Group by time bucket
        unix_ms = DateTime.to_unix(event.timestamp, :millisecond)
        div(unix_ms, bucket_size) * bucket_size
      end)
      |> Map.new(fn {bucket, events} -> {bucket, length(events)} end)
      
      {event_type, time_buckets}
    end)
  end
  
  defp calculate_trend(values) do
    n = length(values)
    if n < 2 do
      %{slope: 0.0, r_squared: 0.0}
    else
      # Simple linear regression
      xs = Enum.to_list(0..(n-1))
      
      x_mean = Enum.sum(xs) / n
      y_mean = Enum.sum(values) / n
      
      numerator = xs
      |> Enum.zip(values)
      |> Enum.map(fn {x, y} -> (x - x_mean) * (y - y_mean) end)
      |> Enum.sum()
      
      denominator = xs
      |> Enum.map(fn x -> :math.pow(x - x_mean, 2) end)
      |> Enum.sum()
      
      slope = if denominator == 0, do: 0.0, else: numerator / denominator
      
      # Calculate R-squared
      y_pred = Enum.map(xs, fn x -> y_mean + slope * (x - x_mean) end)
      
      ss_res = values
      |> Enum.zip(y_pred)
      |> Enum.map(fn {y, y_p} -> :math.pow(y - y_p, 2) end)
      |> Enum.sum()
      
      ss_tot = values
      |> Enum.map(fn y -> :math.pow(y - y_mean, 2) end)
      |> Enum.sum()
      
      r_squared = if ss_tot == 0, do: 0.0, else: 1 - (ss_res / ss_tot)
      
      %{slope: slope, r_squared: r_squared}
    end
  end
  
  defp events_to_time_series(events) do
    # Convert events to a time series (1-second buckets)
    events
    |> Enum.group_by(fn event ->
      DateTime.to_unix(event.timestamp)
    end)
    |> Enum.sort_by(fn {time, _} -> time end)
    |> Enum.map(fn {_time, events} -> length(events) end)
  end
  
  defp calculate_autocorrelations(time_series, lag_range) do
    n = length(time_series)
    mean = Enum.sum(time_series) / n
    
    variance = time_series
    |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
    |> Enum.sum()
    |> Kernel./(n)
    
    Enum.map(lag_range, fn lag ->
      if lag < n do
        correlation = calculate_autocorrelation_at_lag(time_series, mean, variance, lag)
        {lag, correlation}
      else
        {lag, 0.0}
      end
    end)
  end
  
  defp calculate_autocorrelation_at_lag(time_series, mean, variance, lag) do
    n = length(time_series)
    
    if variance == 0 or lag >= n do
      0.0
    else
      covariance = time_series
      |> Enum.drop(lag)
      |> Enum.zip(time_series)
      |> Enum.take(n - lag)
      |> Enum.map(fn {x1, x2} -> (x1 - mean) * (x2 - mean) end)
      |> Enum.sum()
      |> Kernel./(n - lag)
      
      covariance / variance
    end
  end
  
  defp calculate_frequency_confidence(count) do
    # Simple confidence calculation based on frequency
    min(1.0, count / 10.0)
  end
  
  defp calculate_sequence_confidence(count) do
    # Confidence for sequential patterns
    min(1.0, count / 5.0)
  end
  
  defp clean_old_patterns(pattern_cache) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -@pattern_ttl_seconds, :second)
    
    pattern_cache
    |> Enum.filter(fn {_, pattern} ->
      DateTime.compare(pattern.detected_at, cutoff_time) == :gt
    end)
    |> Map.new()
  end
  
  defp update_causal_chains(state) do
    # Detect causal relationships between events
    new_chains = detect_causality(state.event_buffer, state.causal_chains)
    
    # Merge with existing chains
    merged_chains = merge_causal_chains(state.causal_chains, new_chains)
    
    # Limit chain storage and remove old chains
    trimmed_chains = merged_chains
    |> Enum.sort_by(& &1.detected_at, {:desc, DateTime})
    |> Enum.take(@max_causal_chains)
    
    %{state | causal_chains: trimmed_chains}
  end
  
  defp detect_causality(event_buffer, existing_chains) do
    events = :queue.to_list(event_buffer)
    
    # Look for cause-effect patterns
    potential_chains = events
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.filter(&is_causal_sequence?/1)
    |> Enum.map(&build_causal_chain/1)
    
    # Filter out duplicates
    Enum.reject(potential_chains, fn chain ->
      Enum.any?(existing_chains, &chains_equivalent?(&1, chain))
    end)
  end
  
  defp is_causal_sequence?([e1, e2, e3]) do
    # Heuristic: events are causal if they occur in quick succession
    # and have related semantic tags
    time_diff1 = DateTime.diff(e2.timestamp, e1.timestamp, :millisecond)
    time_diff2 = DateTime.diff(e3.timestamp, e2.timestamp, :millisecond)
    
    # Must occur within 500ms of each other
    if time_diff1 < 500 and time_diff2 < 500 do
      # Check for semantic relationship
      tags1 = MapSet.new(e1.metadata.semantic_tags)
      tags2 = MapSet.new(e2.metadata.semantic_tags)
      tags3 = MapSet.new(e3.metadata.semantic_tags)
      
      # Some tags must be shared
      not MapSet.disjoint?(tags1, tags2) or
      not MapSet.disjoint?(tags2, tags3)
    else
      false
    end
  end
  
  defp build_causal_chain(events) do
    %{
      id: generate_chain_id(),
      events: Enum.map(events, fn e -> %{name: e.name, id: e.id, timestamp: e.timestamp} end),
      detected_at: DateTime.utc_now(),
      confidence: calculate_causality_confidence(events)
    }
  end
  
  defp calculate_causality_confidence(events) do
    # Base confidence on timing and semantic similarity
    time_consistency = calculate_time_consistency(events)
    semantic_similarity = calculate_semantic_similarity(events)
    
    (time_consistency + semantic_similarity) / 2
  end
  
  defp calculate_time_consistency(events) do
    # Check if time intervals are consistent
    intervals = events
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [e1, e2] ->
      DateTime.diff(e2.timestamp, e1.timestamp, :millisecond)
    end)
    
    if length(intervals) > 0 do
      avg = Enum.sum(intervals) / length(intervals)
      variance = Enum.map(intervals, fn i -> abs(i - avg) end) |> Enum.sum()
      variance = variance / length(intervals)
      
      # Lower variance = higher consistency
      # Avoid division by zero
      if avg > 0 do
        max(0, 1 - (variance / avg))
      else
        1.0  # Perfect consistency if all intervals are 0
      end
    else
      0.5
    end
  end
  
  defp calculate_semantic_similarity(events) do
    # Calculate overlap in semantic tags
    all_tags = events
    |> Enum.flat_map(fn e -> e.metadata.semantic_tags end)
    |> Enum.uniq()
    
    if length(all_tags) > 0 do
      shared_tags = all_tags
      |> Enum.filter(fn tag ->
        Enum.all?(events, fn e -> tag in e.metadata.semantic_tags end)
      end)
      
      length(shared_tags) / length(all_tags)
    else
      0.0
    end
  end
  
  defp chains_equivalent?(chain1, chain2) do
    # Check if two causal chains represent the same pattern
    events1 = Enum.map(chain1.events, & &1.name)
    events2 = Enum.map(chain2.events, & &1.name)
    
    events1 == events2
  end
  
  defp merge_causal_chains(existing, new_chains) do
    # Merge new chains with existing, updating confidence
    existing ++ new_chains
  end
  
  defp enrich_contexts(state) do
    # Enrich semantic contexts with additional meaning
    enriched_contexts = state.context_graph
    |> Enum.map(fn {topic, context} ->
      enriched = enrich_single_context(topic, context, state)
      {topic, enriched}
    end)
    |> Map.new()
    
    %{state | context_graph: enriched_contexts}
  end
  
  defp enrich_single_context(topic, context, state) do
    # Add derived insights to context
    context
    |> Map.put(:patterns, find_relevant_patterns(topic, state.pattern_cache))
    |> Map.put(:causal_chains, find_relevant_chains(topic, state.causal_chains))
    |> Map.put(:enriched_at, DateTime.utc_now())
  end
  
  defp find_relevant_patterns(topic, pattern_cache) do
    # Find patterns related to the topic
    pattern_cache
    |> Map.values()
    |> Enum.filter(fn pattern ->
      # Simple relevance check - in production would be more sophisticated
      case pattern.type do
        :high_frequency -> 
          pattern.pattern.event == topic
        :sequence ->
          topic in pattern.pattern.sequence
        :correlation ->
          topic in pattern.pattern.correlated_events
        _ ->
          false
      end
    end)
  end
  
  defp find_relevant_chains(topic, causal_chains) do
    # Find causal chains involving the topic
    Enum.filter(causal_chains, fn chain ->
      Enum.any?(chain.events, fn event ->
        event.name == topic
      end)
    end)
  end
  
  defp generate_event_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp generate_pattern_id do
    "pattern_" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower))
  end
  
  defp generate_chain_id do
    "chain_" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower))
  end
  
  defp increment_stat(stats, key) do
    Map.update(stats, key, 1, &(&1 + 1))
  end
  
  defp matches_pattern?(chain, pattern) when is_map(pattern) do
    # Match chain against pattern criteria
    Enum.all?(pattern, fn {key, value} ->
      case key do
        :events -> 
          chain_events = Enum.map(chain.events, & &1.name)
          Enum.all?(value, &(&1 in chain_events))
        :min_confidence ->
          chain.confidence >= value
        _ ->
          true
      end
    end)
  end
  
  defp matches_pattern?(_chain, _pattern), do: false
  
  # Fusion Functions
  
  defp fuse_vsm_coordination(events) do
    # Fuse VSM subsystem coordination events
    {:ok, %{
      type: :vsm_coordination,
      subsystems_involved: Enum.map(events, fn e -> e.metadata.subsystem end) |> Enum.uniq(),
      coordination_quality: assess_coordination_quality(events),
      timestamp: DateTime.utc_now()
    }}
  end
  
  defp fuse_algedonic_response(events) do
    # Fuse algedonic response patterns
    algedonic_events = Enum.filter(events, fn e -> e.name == :algedonic_signal end)
    response_events = Enum.filter(events, fn e -> e.name in [:vsm_adaptation, :policy_change] end)
    
    {:ok, %{
      type: :algedonic_response,
      stimulus: extract_algedonic_stimulus(algedonic_events),
      responses: Enum.map(response_events, & &1.data),
      response_time_ms: calculate_response_time(algedonic_events, response_events),
      effectiveness: assess_response_effectiveness(events)
    }}
  end
  
  defp fuse_consciousness_evolution(events) do
    # Fuse consciousness state changes
    {:ok, %{
      type: :consciousness_evolution,
      state_changes: extract_state_changes(events),
      evolution_direction: determine_evolution_direction(events),
      coherence: calculate_consciousness_coherence(events)
    }}
  end
  
  defp fuse_environmental_response(events) do
    # Fuse environmental adaptation events
    {:ok, %{
      type: :environmental_response,
      environmental_changes: extract_environmental_changes(events),
      adaptations: extract_adaptations(events),
      adaptation_speed: calculate_adaptation_speed(events),
      success_rate: estimate_adaptation_success(events)
    }}
  end
  
  defp fuse_error_cascade(events) do
    # Fuse error cascade patterns
    {:ok, %{
      type: :error_cascade,
      root_cause: identify_root_cause(events),
      cascade_path: extract_cascade_path(events),
      impact_severity: calculate_cascade_severity(events),
      recovery_actions: identify_recovery_actions(events)
    }}
  end
  
  # Helper functions for fusion
  
  defp assess_coordination_quality(events) do
    # Assess how well subsystems are coordinating
    if length(events) >= 3, do: :excellent, else: :good
  end
  
  defp extract_algedonic_stimulus(algedonic_events) do
    algedonic_events
    |> Enum.map(fn e -> e.data end)
    |> List.first()
  end
  
  defp calculate_response_time(stimulus_events, response_events) do
    if length(stimulus_events) > 0 and length(response_events) > 0 do
      stimulus_time = List.first(stimulus_events).timestamp
      response_time = List.first(response_events).timestamp
      DateTime.diff(response_time, stimulus_time, :millisecond)
    else
      nil
    end
  end
  
  defp assess_response_effectiveness(_events) do
    # Simplified effectiveness assessment
    :effective
  end
  
  defp extract_state_changes(events) do
    events
    |> Enum.filter(fn e -> e.name == :consciousness_update end)
    |> Enum.map(fn e -> e.data end)
  end
  
  defp determine_evolution_direction(_events) do
    # Determine if consciousness is evolving positively
    :ascending
  end
  
  defp calculate_consciousness_coherence(_events) do
    # Measure coherence of consciousness updates
    0.85
  end
  
  defp extract_environmental_changes(events) do
    events
    |> Enum.filter(fn e -> e.name == :environmental_change end)
    |> Enum.map(fn e -> e.data end)
  end
  
  defp extract_adaptations(events) do
    events
    |> Enum.filter(fn e -> e.name in [:s4_intelligence, :strategic_update] end)
    |> Enum.map(fn e -> e.data end)
  end
  
  defp calculate_adaptation_speed(events) do
    if length(events) > 1 do
      first = List.first(events).timestamp
      last = List.last(events).timestamp
      DateTime.diff(last, first, :millisecond)
    else
      nil
    end
  end
  
  defp estimate_adaptation_success(_events) do
    # Estimate success rate of adaptations
    0.9
  end
  
  defp identify_root_cause(events) do
    # Find the earliest error event
    events
    |> Enum.filter(fn e -> e.name == :error end)
    |> Enum.min_by(fn e -> e.timestamp end, fn -> nil end)
    |> case do
      nil -> :unknown
      event -> event.data
    end
  end
  
  defp extract_cascade_path(events) do
    # Map the path of error propagation
    events
    |> Enum.sort_by(fn e -> e.timestamp end)
    |> Enum.map(fn e -> {e.name, e.metadata.subsystem} end)
  end
  
  defp calculate_cascade_severity(events) do
    # Severity based on number and type of errors
    error_count = Enum.count(events, fn e -> e.name in [:error, :failure] end)
    
    cond do
      error_count > 5 -> :critical
      error_count > 2 -> :high
      error_count > 0 -> :medium
      true -> :low
    end
  end
  
  defp identify_recovery_actions(events) do
    # Look for circuit breaker activations or recovery events
    events
    |> Enum.filter(fn e -> e.name == :circuit_break end)
    |> Enum.map(fn e -> e.data end)
  end
  
  defp enhance_patterns_with_llm(patterns) do
    if length(patterns) == 0 do
      {:ok, []}
    else
      # Limit patterns for LLM context
      patterns_for_analysis = Enum.take(patterns, 10)
      
      pattern_context = patterns_for_analysis
      |> Enum.map(fn pattern ->
        "#{pattern.type}: #{inspect(pattern.pattern, limit: 2)} (confidence: #{Float.round(pattern.confidence, 2)})"
      end)
      |> Enum.join("\n")
      
      case LLMBridge.call_llm_api(
        """
        Analyze these detected patterns from the cybernetic event stream:
        
        #{pattern_context}
        
        For each pattern, provide insights covering:
        1. What this pattern indicates about system behavior
        2. Potential causes or contributing factors
        3. Implications for system health and performance
        4. Recommended actions or observations
        5. Relationship to other patterns (if any)
        
        Format response as:
        PATTERN_TYPE|significance|causes|implications|recommendations|relationships
        
        Only analyze the patterns listed above.
        """,
        :analysis,
        timeout: 20_000
      ) do
        {:ok, response} ->
          enhanced = add_llm_insights_to_patterns(patterns_for_analysis, response)
          # Add back any patterns that weren't analyzed
          all_enhanced = enhanced ++ Enum.drop(patterns, 10)
          {:ok, all_enhanced}
          
        {:error, reason} ->
          Logger.debug("Pattern LLM enhancement failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
  
  defp add_llm_insights_to_patterns(patterns, llm_response) do
    insights = parse_pattern_insights(llm_response)
    
    Enum.map(patterns, fn pattern ->
      insight = Enum.find(insights, fn i -> 
        String.downcase(to_string(i.pattern_type)) == String.downcase(to_string(pattern.type))
      end)
      
      if insight do
        Map.merge(pattern, %{
          llm_significance: insight.significance,
          llm_causes: insight.causes,
          llm_implications: insight.implications,
          llm_recommendations: insight.recommendations,
          llm_relationships: insight.relationships
        })
      else
        pattern
      end
    end)
  end
  
  defp parse_pattern_insights(response) do
    response
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "|"))
    |> Enum.map(&parse_insight_line/1)
    |> Enum.filter(& &1 != nil)
  end
  
  defp parse_insight_line(line) do
    case String.split(line, "|") do
      [pattern_type, significance, causes, implications, recommendations, relationships] ->
        %{
          pattern_type: String.to_atom(String.downcase(String.trim(pattern_type))),
          significance: String.trim(significance),
          causes: String.trim(causes),
          implications: String.trim(implications),
          recommendations: String.trim(recommendations),
          relationships: String.trim(relationships)
        }
      _ -> nil
    end
  end
end