defmodule AutonomousOpponentV2Core.VSM.S4.PatternCorrelationAnalyzer do
  @moduledoc """
  Advanced pattern correlation analysis for S4 Intelligence.
  
  Analyzes relationships, dependencies, and causality between patterns
  detected across the VSM cybernetic system. Implements Beer's variety
  engineering principles for pattern correlation intelligence.
  
  Key Features:
  - Temporal correlation analysis (cause-effect relationships)
  - Cross-subsystem pattern correlation (S1↔S2↔S3↔S4↔S5)
  - Pattern clustering and similarity analysis
  - Predictive pattern modeling
  - Algedonic correlation (pain/pleasure pattern relationships)
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore
  alias AutonomousOpponentV2Core.Core.HybridLogicalClock, as: HLC
  
  defstruct [
    :pattern_history,      # LRU cache of recent patterns
    :correlation_matrix,   # Pattern correlation coefficients
    :temporal_windows,     # Sliding time windows for analysis
    :clustering_state,     # K-means clustering state
    :prediction_models,    # Predictive models for pattern sequences
    :subsystem_patterns,   # Patterns grouped by VSM subsystem
    :algedonic_correlations, # Pain/pleasure pattern relationships
    :causality_graph,      # Directed graph of causal relationships
    :pattern_cache,        # Fast pattern lookup cache
    :metrics              # Performance and accuracy metrics
  ]
  
  # Configuration constants
  @max_pattern_history 10_000
  @correlation_window_ms 60_000  # 1 minute correlation window
  @min_correlation_strength 0.3
  @temporal_lag_threshold 5_000  # 5 second maximum lag for causality
  @clustering_update_interval 30_000  # 30 seconds
  @prediction_horizon_ms 300_000  # 5 minute prediction horizon
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def analyze_correlation(pattern_a, pattern_b, opts \\ []) do
    GenServer.call(__MODULE__, {:analyze_correlation, pattern_a, pattern_b, opts})
  end
  
  def get_correlations(pattern_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_correlations, pattern_id, opts})
  end
  
  def predict_patterns(context, time_horizon \\ @prediction_horizon_ms) do
    GenServer.call(__MODULE__, {:predict_patterns, context, time_horizon})
  end
  
  def get_causality_chain(pattern_id, max_depth \\ 3) do
    GenServer.call(__MODULE__, {:get_causality_chain, pattern_id, max_depth})
  end
  
  def get_cluster_analysis(opts \\ []) do
    GenServer.call(__MODULE__, {:get_cluster_analysis, opts})
  end
  
  def get_algedonic_correlations(intensity_threshold \\ 0.7) do
    GenServer.call(__MODULE__, {:get_algedonic_correlations, intensity_threshold})
  end
  
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to pattern events from S4 Intelligence and other subsystems
    EventBus.subscribe(:pattern_detected)
    EventBus.subscribe(:temporal_pattern_detected)
    EventBus.subscribe(:vsm_pattern_flow)
    EventBus.subscribe(:algedonic_signal)
    EventBus.subscribe(:s4_environmental_signal)
    
    # Schedule periodic correlation analysis
    Process.send_after(self(), :update_correlations, @clustering_update_interval)
    Process.send_after(self(), :update_clusters, @clustering_update_interval)
    Process.send_after(self(), :cleanup_history, 300_000)  # 5 minute cleanup
    
    state = %__MODULE__{
      pattern_history: :queue.new(),
      correlation_matrix: %{},
      temporal_windows: init_temporal_windows(),
      clustering_state: init_clustering(),
      prediction_models: init_prediction_models(),
      subsystem_patterns: init_subsystem_tracking(),
      algedonic_correlations: %{},
      causality_graph: :digraph.new([:acyclic]),
      pattern_cache: %{},
      metrics: init_metrics()
    }
    
    Logger.info("🔗 Pattern Correlation Analyzer initialized for S4 Intelligence")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:analyze_correlation, pattern_a, pattern_b, _opts}, _from, state) do
    correlation = calculate_correlation(pattern_a, pattern_b, state)
    {:reply, {:ok, correlation}, state}
  end
  
  @impl true
  def handle_call({:get_correlations, pattern_id, opts}, _from, state) do
    correlations = get_pattern_correlations(pattern_id, state, opts)
    {:reply, {:ok, correlations}, state}
  end
  
  @impl true
  def handle_call({:predict_patterns, context, time_horizon}, _from, state) do
    predictions = generate_pattern_predictions(context, time_horizon, state)
    {:reply, {:ok, predictions}, state}
  end
  
  @impl true
  def handle_call({:get_causality_chain, pattern_id, max_depth}, _from, state) do
    chain = build_causality_chain(pattern_id, max_depth, state)
    {:reply, {:ok, chain}, state}
  end
  
  @impl true
  def handle_call({:get_cluster_analysis, _opts}, _from, state) do
    analysis = generate_cluster_analysis(state)
    {:reply, {:ok, analysis}, state}
  end
  
  @impl true
  def handle_call({:get_algedonic_correlations, threshold}, _from, state) do
    correlations = filter_algedonic_correlations(state.algedonic_correlations, threshold)
    {:reply, {:ok, correlations}, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  # Event handlers
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :pattern_detected} = event}, state) do
    new_state = process_pattern_event(event, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :temporal_pattern_detected} = event}, state) do
    new_state = process_temporal_pattern_event(event, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :vsm_pattern_flow} = event}, state) do
    new_state = process_vsm_pattern_event(event, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :algedonic_signal} = event}, state) do
    new_state = process_algedonic_event(event, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:update_correlations, state) do
    new_state = update_correlation_matrix(state)
    Process.send_after(self(), :update_correlations, @clustering_update_interval)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:update_clusters, state) do
    new_state = update_pattern_clusters(state)
    Process.send_after(self(), :update_clusters, @clustering_update_interval)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:cleanup_history, state) do
    new_state = cleanup_pattern_history(state)
    Process.send_after(self(), :cleanup_history, 300_000)
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp init_temporal_windows do
    %{
      short: [],      # 1 minute window
      medium: [],     # 5 minute window  
      long: []        # 15 minute window
    }
  end
  
  defp init_clustering do
    %{
      clusters: %{},
      centroids: [],
      k: 5,  # Number of clusters
      iterations: 0,
      convergence_threshold: 0.01
    }
  end
  
  defp init_prediction_models do
    %{
      temporal_sequence: %{},
      markov_chains: %{},
      regression_models: %{},
      neural_patterns: %{}
    }
  end
  
  defp init_subsystem_tracking do
    %{
      s1: [],
      s2: [],
      s3: [],
      s4: [],
      s5: [],
      cross_subsystem: []
    }
  end
  
  defp init_metrics do
    %{
      patterns_analyzed: 0,
      correlations_found: 0,
      predictions_made: 0,
      prediction_accuracy: 0.0,
      clustering_quality: 0.0,
      causality_chains_built: 0,
      algedonic_correlations: 0,
      processing_time_avg: 0.0,
      last_updated: DateTime.utc_now()
    }
  end
  
  defp process_pattern_event(event, state) do
    pattern = create_pattern_record(event)
    
    # Add to history with LRU eviction
    new_history = add_to_history(state.pattern_history, pattern)
    
    # Update pattern cache for fast lookup
    new_cache = Map.put(state.pattern_cache, pattern.id, pattern)
    
    # Update temporal windows
    new_windows = update_temporal_windows(state.temporal_windows, pattern)
    
    # Update subsystem tracking
    new_subsystem = update_subsystem_patterns(state.subsystem_patterns, pattern)
    
    # Update causality graph if causal relationship detected
    new_causality = update_causality_graph(state.causality_graph, pattern, state)
    
    # Update metrics
    new_metrics = update_metrics(state.metrics, :pattern_processed)
    
    %{state |
      pattern_history: new_history,
      pattern_cache: new_cache,
      temporal_windows: new_windows,
      subsystem_patterns: new_subsystem,
      causality_graph: new_causality,
      metrics: new_metrics
    }
  end
  
  defp process_temporal_pattern_event(event, state) do
    # Temporal patterns get special handling for time-series correlation
    pattern = create_temporal_pattern_record(event)
    
    # Update temporal correlation models
    new_models = update_temporal_models(state.prediction_models, pattern)
    
    # Process as regular pattern but with temporal emphasis
    new_state = process_pattern_event(event, state)
    
    %{new_state | prediction_models: new_models}
  end
  
  defp process_vsm_pattern_event(event, state) do
    pattern = create_vsm_pattern_record(event)
    
    # Track cross-subsystem correlations
    new_subsystem = update_cross_subsystem_correlations(state.subsystem_patterns, pattern)
    
    # Process as regular pattern
    new_state = process_pattern_event(event, state)
    
    %{new_state | subsystem_patterns: new_subsystem}
  end
  
  defp process_algedonic_event(event, state) do
    # Algedonic signals create special correlation patterns
    signal_data = event.data
    
    if signal_data[:intensity] > 0.7 do
      # High-intensity algedonic signals trigger correlation analysis
      new_algedonic = update_algedonic_correlations(state.algedonic_correlations, event, state)
      
      # Publish algedonic correlation insights
      EventBus.publish(:algedonic_correlation_detected, %{
        signal: signal_data,
        correlations: get_recent_pattern_correlations(state),
        timestamp: event.timestamp
      })
      
      %{state | algedonic_correlations: new_algedonic}
    else
      state
    end
  end
  
  defp create_pattern_record(event) do
    %{
      id: generate_pattern_id(event),
      type: event.data[:pattern_type] || :unknown,
      source: event.data[:source] || :unknown,
      confidence: event.data[:confidence] || 0.0,
      severity: event.data[:severity] || :normal,
      timestamp: event.timestamp,
      data: event.data,
      vector: extract_pattern_vector(event.data),
      subsystem: detect_subsystem(event.data)
    }
  end
  
  defp create_temporal_pattern_record(event) do
    %{
      id: generate_pattern_id(event),
      type: :temporal,
      source: event.data[:source] || :temporal_detector,
      confidence: event.data[:confidence] || 0.0,
      timestamp: event.timestamp,
      time_window: event.data[:time_window],
      frequency: event.data[:frequency],
      data: event.data,
      vector: extract_temporal_vector(event.data),
      subsystem: :temporal
    }
  end
  
  defp create_vsm_pattern_record(event) do
    %{
      id: generate_pattern_id(event),
      type: :vsm_flow,
      source: event.data[:subsystem] || :unknown,
      confidence: event.data[:confidence] || 0.0,
      timestamp: event.timestamp,
      variety_type: event.data[:variety_type],
      flow_direction: event.data[:flow_direction],
      data: event.data,
      vector: extract_vsm_vector(event.data),
      subsystem: String.to_atom(event.data[:subsystem] || "unknown")
    }
  end
  
  defp calculate_correlation(pattern_a, pattern_b, _state) do
    # Calculate Pearson correlation coefficient between pattern vectors
    vector_a = pattern_a[:vector] || []
    vector_b = pattern_b[:vector] || []
    
    if length(vector_a) == length(vector_b) and length(vector_a) > 0 do
      pearson_correlation(vector_a, vector_b)
    else
      0.0
    end
  end
  
  defp pearson_correlation(vector_a, vector_b) do
    n = length(vector_a)
    
    sum_a = Enum.sum(vector_a)
    sum_b = Enum.sum(vector_b)
    
    sum_a_sq = Enum.sum(Enum.map(vector_a, &(&1 * &1)))
    sum_b_sq = Enum.sum(Enum.map(vector_b, &(&1 * &1)))
    
    sum_ab = Enum.zip(vector_a, vector_b)
             |> Enum.map(fn {a, b} -> a * b end)
             |> Enum.sum()
    
    numerator = n * sum_ab - sum_a * sum_b
    denominator_a = :math.sqrt(n * sum_a_sq - sum_a * sum_a)
    denominator_b = :math.sqrt(n * sum_b_sq - sum_b * sum_b)
    
    if denominator_a * denominator_b == 0 do
      0.0
    else
      numerator / (denominator_a * denominator_b)
    end
  end
  
  defp update_correlation_matrix(state) do
    # Recalculate correlation matrix for recent patterns
    recent_patterns = get_recent_patterns(state.pattern_history, @correlation_window_ms)
    
    new_matrix = calculate_correlation_matrix(recent_patterns)
    
    %{state | correlation_matrix: new_matrix}
  end
  
  defp calculate_correlation_matrix(patterns) do
    # Calculate pairwise correlations between all patterns
    patterns
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {pattern_a, i}, acc ->
      patterns
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {pattern_b, j}, inner_acc ->
        if i != j do
          correlation = calculate_correlation(pattern_a, pattern_b, %{})
          if abs(correlation) >= @min_correlation_strength do
            key = {pattern_a.id, pattern_b.id}
            Map.put(inner_acc, key, correlation)
          else
            inner_acc
          end
        else
          inner_acc
        end
      end)
    end)
  end
  
  defp generate_pattern_predictions(context, time_horizon, state) do
    # Use temporal models to predict likely patterns
    current_patterns = get_recent_patterns(state.pattern_history, 30_000)  # Last 30 seconds
    
    # Find similar historical contexts
    similar_contexts = find_similar_contexts(current_patterns, state.pattern_history)
    
    # Generate predictions based on historical patterns
    predictions = similar_contexts
    |> Enum.map(&predict_from_context(&1, time_horizon, state))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.confidence, :desc)
    |> Enum.take(5)  # Top 5 predictions
    
    predictions
  end
  
  defp cleanup_pattern_history(state) do
    # Remove old patterns to maintain performance
    history_list = :queue.to_list(state.pattern_history)
    cutoff_time = DateTime.add(DateTime.utc_now(), -3600, :second)  # 1 hour ago
    
    filtered_patterns = Enum.filter(history_list, fn pattern ->
      DateTime.compare(pattern.timestamp, cutoff_time) == :gt
    end)
    
    new_history = :queue.from_list(Enum.take(filtered_patterns, @max_pattern_history))
    
    # Clean up pattern cache
    pattern_ids = Enum.map(filtered_patterns, & &1.id) |> MapSet.new()
    new_cache = Map.filter(state.pattern_cache, fn {id, _} -> MapSet.member?(pattern_ids, id) end)
    
    %{state | pattern_history: new_history, pattern_cache: new_cache}
  end
  
  # Helper functions with minimal implementations
  
  defp generate_pattern_id(event) do
    # Handle HLC timestamp properly - convert to string representation
    timestamp_str = case event.timestamp do
      %{physical: physical, logical: logical, node_id: node_id} ->
        "#{physical}-#{logical}-#{node_id}"
      timestamp when is_binary(timestamp) ->
        timestamp
      timestamp ->
        inspect(timestamp)
    end
    
    :crypto.hash(:sha256, "#{timestamp_str}#{inspect(event.data)}")
    |> Base.encode16()
    |> String.slice(0, 16)
  end
  
  defp extract_pattern_vector(data) do
    # Simple vector extraction - in production this would be more sophisticated
    [
      Map.get(data, :confidence, 0.0),
      hash_to_float(inspect(Map.get(data, :pattern_type, :unknown))),
      hash_to_float(inspect(Map.get(data, :source, :unknown))),
      case Map.get(data, :severity, :normal) do
        :low -> 0.2
        :normal -> 0.5
        :high -> 0.8
        :critical -> 1.0
        _ -> 0.5
      end
    ]
  end
  
  defp extract_temporal_vector(data) do
    [
      Map.get(data, :confidence, 0.0),
      Map.get(data, :frequency, 0.0),
      hash_to_float(inspect(Map.get(data, :time_window, :unknown))),
      0.5  # Temporal type indicator
    ]
  end
  
  defp extract_vsm_vector(data) do
    [
      Map.get(data, :confidence, 0.0),
      hash_to_float(inspect(Map.get(data, :variety_type, :unknown))),
      hash_to_float(inspect(Map.get(data, :flow_direction, :unknown))),
      hash_to_float(inspect(Map.get(data, :subsystem, :unknown)))
    ]
  end
  
  defp hash_to_float(string) do
    :crypto.hash(:md5, string)
    |> :binary.decode_unsigned()
    |> rem(1000)
    |> Kernel./(1000.0)
  end
  
  defp detect_subsystem(data) do
    case Map.get(data, :source) do
      source when source in [:s1_operations, "s1_operations"] -> :s1
      source when source in [:s2_coordination, "s2_coordination"] -> :s2
      source when source in [:s3_control, "s3_control"] -> :s3
      source when source in [:s4_intelligence, "s4_intelligence"] -> :s4
      source when source in [:s5_policy, "s5_policy"] -> :s5
      _ -> :unknown
    end
  end
  
  # Placeholder implementations for complex functions
  defp add_to_history(history, pattern), do: :queue.in(pattern, history)
  defp update_temporal_windows(windows, _pattern), do: windows
  defp update_subsystem_patterns(subsystem, _pattern), do: subsystem
  defp update_causality_graph(graph, _pattern, _state), do: graph
  defp update_metrics(metrics, :pattern_processed), do: %{metrics | patterns_analyzed: metrics.patterns_analyzed + 1}
  defp update_temporal_models(models, _pattern), do: models
  defp update_cross_subsystem_correlations(subsystem, _pattern), do: subsystem
  defp update_algedonic_correlations(correlations, _event, _state), do: correlations
  defp get_recent_pattern_correlations(_state), do: []
  defp get_pattern_correlations(_pattern_id, _state, _opts), do: []
  defp build_causality_chain(_pattern_id, _max_depth, _state), do: []
  defp generate_cluster_analysis(_state), do: %{}
  defp filter_algedonic_correlations(correlations, _threshold), do: correlations
  defp update_pattern_clusters(state), do: state
  defp get_recent_patterns(history, _window_ms), do: :queue.to_list(history)
  defp find_similar_contexts(_current, _history), do: []
  defp predict_from_context(_context, _horizon, _state), do: nil
end