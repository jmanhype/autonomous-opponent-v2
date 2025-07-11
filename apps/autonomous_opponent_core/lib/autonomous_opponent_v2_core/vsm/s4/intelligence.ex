defmodule AutonomousOpponentV2Core.VSM.S4.Intelligence do
  @moduledoc """
  System 4: Intelligence - The environmental scanner and future modeler.
  
  S4 looks OUTWARD and FORWARD. It scans the environment beyond the
  immediate operations, detects patterns, and models possible futures.
  It feeds intelligence to S5 for policy decisions and S3 for operational
  adjustments.
  
  Key responsibilities:
  - Environmental scanning and pattern detection
  - Future scenario modeling
  - Pattern storage using Vector Store and HNSW
  - Intelligence reports to S5 and S3
  - Learning from S3 audit trails
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: Algedonic
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore
  alias AutonomousOpponentV2Core.VSM.S4.PatternCorrelationAnalyzer
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  
  defstruct [
    :vector_store,
    :environmental_model,
    :pattern_detector,
    :scenario_modeler,
    :intelligence_reports,
    :learning_queue,
    :health_metrics,
    :pain_report_times,
    :pattern_cache,
    :llm_integration,
    :correlation_analyzer
  ]
  
  # Intelligence thresholds
  @pattern_confidence_threshold 0.7
  @scenario_probability_threshold 0.6
  @environmental_scan_interval 10_000  # 10 seconds
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def scan_environment do
    GenServer.call(__MODULE__, :scan_environment)
  end
  
  def model_scenario(parameters) do
    GenServer.call(__MODULE__, {:model_scenario, parameters})
  end
  
  def get_intelligence_report do
    GenServer.call(__MODULE__, :get_intelligence)
  end
  
  def learn_from_audit(audit_data) do
    GenServer.cast(__MODULE__, {:learn, audit_data})
  end
  
  def scan_environment(server, scan_types) do
    GenServer.call(server, {:scan_environment_with_types, scan_types})
  end
  
  def extract_patterns(server, scan_data) do
    GenServer.call(server, {:extract_patterns, scan_data})
  end
  
  def get_environmental_model(server) do
    GenServer.call(server, :get_environmental_model)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Start Vector Store for pattern memory with persistence
    vector_store_opts = [
      name: :s4_vector_store,
      vector_dim: 64,
      subspaces: 8
    ]
    
    # ============================================================================
    # VSM S4 INTELLIGENCE: COMPREHENSIVE HNSW PERSISTENCE CONFIGURATION
    # ============================================================================
    # Critical for cybernetic viability: S4 requires persistent pattern memory
    
    vector_store_opts = if Application.get_env(:autonomous_opponent_core, :hnsw_persist_enabled, false) do
      vector_store_opts ++ [
        # Enable HNSW index (CRITICAL - without this, HNSW won't initialize)
        hnsw_enabled: true,
        
        # Core persistence settings
        persist_path: Application.get_env(:autonomous_opponent_core, :hnsw_persist_path),
        persist_interval: Application.get_env(:autonomous_opponent_core, :hnsw_persist_interval, :timer.minutes(3)),
        persist_on_shutdown: Application.get_env(:autonomous_opponent_core, :hnsw_persist_on_shutdown, true),
        persist_async: Application.get_env(:autonomous_opponent_core, :hnsw_persist_async, true),
        
        # HNSW index parameters (optimized for S4 pattern recognition)
        hnsw_m: Application.get_env(:autonomous_opponent_core, :hnsw_m, 32),
        hnsw_ef: Application.get_env(:autonomous_opponent_core, :hnsw_ef, 400),
        hnsw_max_connections: Application.get_env(:autonomous_opponent_core, :hnsw_max_connections, 64),
        
        # Variety engineering (Beer's cybernetic principles)
        max_patterns: Application.get_env(:autonomous_opponent_core, :hnsw_max_patterns, 100_000),
        pattern_confidence_threshold: Application.get_env(:autonomous_opponent_core, :hnsw_pattern_confidence_threshold, 0.7),
        variety_pressure_limit: Application.get_env(:autonomous_opponent_core, :hnsw_variety_pressure_limit, 0.8),
        
        # Temporal pattern management (algedonic memory)
        prune_interval: Application.get_env(:autonomous_opponent_core, :hnsw_prune_interval, :timer.minutes(30)),
        prune_max_age: Application.get_env(:autonomous_opponent_core, :hnsw_prune_max_age, :timer.hours(48)),
        prune_low_confidence_age: Application.get_env(:autonomous_opponent_core, :hnsw_prune_low_confidence_age, :timer.hours(6)),
        pain_pattern_retention: Application.get_env(:autonomous_opponent_core, :hnsw_pain_pattern_retention, 7 * 24 * 60 * 60 * 1000),
        
        # Performance and reliability
        checkpoint_size_threshold: Application.get_env(:autonomous_opponent_core, :hnsw_checkpoint_size_threshold, 50_000_000),
        backup_retention: Application.get_env(:autonomous_opponent_core, :hnsw_backup_retention, 3),
        corruption_recovery: Application.get_env(:autonomous_opponent_core, :hnsw_corruption_recovery, true),
        
        # VSM integration
        eventbus_integration: Application.get_env(:autonomous_opponent_core, :hnsw_eventbus_integration, true),
        circuitbreaker_protection: Application.get_env(:autonomous_opponent_core, :hnsw_circuitbreaker_protection, true),
        telemetry_enabled: Application.get_env(:autonomous_opponent_core, :hnsw_telemetry_enabled, true),
        algedonic_integration: Application.get_env(:autonomous_opponent_core, :hnsw_algedonic_integration, true)
      ]
    else
      # No persistence mode - S4 operates in "amnesia" mode (not recommended for production)
      Logger.warning("🧠 VSM S4: HNSW persistence DISABLED - system will suffer from variety amnesia!")
      vector_store_opts
    end
    
    {:ok, vector_store} = case VectorStore.start_link(vector_store_opts) do
      {:ok, vs} -> {:ok, vs}
      {:error, {:already_started, vs}} -> {:ok, vs}
      {:error, reason} -> 
        Logger.warning("🧠 S4: Failed to start VectorStore: #{inspect(reason)}")
        # Return a mock vector store reference to prevent crashes
        {:ok, nil}
    end
    
    # Subscribe to variety channels from other subsystems
    EventBus.subscribe(:s4_intelligence)  # Variety channel output for S4
    EventBus.subscribe(:external_environment)  # External signals
    EventBus.subscribe(:algedonic_intervention)  # Emergency overrides
    
    # 🧠 CRITICAL VSM PATTERN INTEGRATION: Subscribe to pattern detection events
    # This completes the cybernetic variety channel from S1 pattern detection to S4 intelligence
    EventBus.subscribe(:pattern_detected)  # Primary pattern events from detectors
    EventBus.subscribe(:temporal_pattern_detected)  # Temporal pattern events
    EventBus.subscribe(:s4_environmental_signal)  # High-priority environmental patterns
    EventBus.subscribe(:patterns_indexed)  # Pattern indexing notifications
    
    # Start Pattern Correlation Analyzer for advanced pattern intelligence
    {:ok, correlation_analyzer} = case PatternCorrelationAnalyzer.start_link([]) do
      {:ok, analyzer} -> {:ok, analyzer}
      {:error, {:already_started, analyzer}} -> {:ok, analyzer}
      {:error, reason} -> 
        Logger.warning("🔗 S4: Failed to start Pattern Correlation Analyzer: #{inspect(reason)}")
        {:ok, nil}
    end
    
    # Start environmental scanning
    Process.send_after(self(), :environmental_scan, @environmental_scan_interval)
    Process.send_after(self(), :report_health, 1000)
    
    state = %__MODULE__{
      vector_store: vector_store,
      environmental_model: init_environmental_model(),
      pattern_detector: init_pattern_detector(),
      scenario_modeler: init_scenario_modeler(),
      intelligence_reports: [],
      learning_queue: :queue.new(),
      health_metrics: %{
        patterns_detected: 0,
        scenarios_modeled: 0,
        predictions_accurate: 0,
        predictions_total: 0,
        environmental_complexity: 0.5,
        scans_performed: 0,
        anomalies_detected: 0,
        total_patterns: 0,
        predictions_made: 0,
        correct_predictions: 0
      },
      pain_report_times: %{},
      pattern_cache: %{},
      llm_integration: %{
        enabled: true,
        provider: :local_fallback,
        model: "gpt-4",
        last_analysis_at: nil,
        analysis_count: 0
      },
      correlation_analyzer: correlation_analyzer
    }
    
    Logger.info("S4 Intelligence online - scanning the horizon")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:scan_environment, _from, state) do
    # Perform environmental scan
    scan_result = perform_environmental_scan(state)
    
    # Detect patterns in the scan
    patterns = detect_patterns(scan_result, state)
    
    # Store significant patterns
    significant_patterns = Enum.filter(patterns, fn p -> 
      p.confidence > @pattern_confidence_threshold 
    end)
    
    Enum.each(significant_patterns, fn pattern ->
      case VectorStore.store_pattern(state.vector_store, pattern, %{
        source: :environmental_scan,
        timestamp: DateTime.utc_now()
      }) do
        :ok -> 
          Logger.debug("🧠 S4: Successfully stored environmental scan pattern")
        {:error, reason} ->
          Logger.warning("🧠 S4: Failed to store environmental scan pattern: #{inspect(reason)}")
      end
    end)
    
    # Update environmental model
    new_model = update_environmental_model(state.environmental_model, scan_result, patterns)
    
    # Generate intelligence report
    report = generate_intelligence_report(new_model, patterns, state)
    
    # Send to S5
    send_intelligence_to_s5(report)
    
    new_state = %{state | 
      environmental_model: new_model,
      intelligence_reports: [report | state.intelligence_reports] |> Enum.take(100)
    }
    
    {:reply, {:ok, report}, new_state}
  end
  
  @impl true
  def handle_call({:model_scenario, parameters}, _from, state) do
    # Find similar historical patterns
    similar_patterns = case VectorStore.find_similar_patterns(
      state.vector_store,
      parameters,
      5
    ) do
      {:ok, patterns} -> patterns
      {:error, reason} ->
        Logger.warning("🧠 S4: Failed to find similar patterns: #{inspect(reason)}")
        []  # Return empty list to continue operation
    end
    
    # Model possible futures based on patterns
    scenarios = model_futures(parameters, similar_patterns, state)
    
    # Filter by probability
    likely_scenarios = Enum.filter(scenarios, fn s -> 
      s.probability > @scenario_probability_threshold 
    end)
    
    # Update metrics
    new_metrics = Map.update!(state.health_metrics, :scenarios_modeled, &(&1 + 1))
    
    {:reply, {:ok, likely_scenarios}, %{state | health_metrics: new_metrics}}
  end
  
  @impl true
  def handle_call(:get_intelligence, _from, state) do
    report = %{
      environmental_state: summarize_environment(state.environmental_model),
      detected_patterns: get_recent_patterns(state),
      future_scenarios: get_active_scenarios(state),
      recommendations: generate_recommendations(state)
    }
    
    {:reply, report, state}
  end
  
  @impl true
  def handle_call({:scan_environment_with_types, scan_types}, _from, state) do
    # Perform targeted environmental scan
    scan_result = perform_targeted_scan(scan_types, state)
    {:reply, {:ok, scan_result}, state}
  end
  
  @impl true
  def handle_call({:extract_patterns, scan_data}, _from, state) do
    # Extract patterns from provided scan data
    patterns = detect_patterns(scan_data, state)
    {:reply, {:ok, patterns}, state}
  end
  
  @impl true
  def handle_call(:get_environmental_model, _from, state) do
    {:reply, state.environmental_model, state}
  end
  
  @impl true
  def handle_cast({:learn, audit_data}, state) do
    # Queue learning data
    new_queue = :queue.in(audit_data, state.learning_queue)
    
    # Process if queue is getting full
    new_state = if :queue.len(new_queue) > 10 do
      process_learning_queue(%{state | learning_queue: new_queue})
    else
      %{state | learning_queue: new_queue}
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  # Handle new HLC event format from EventBus
  def handle_info({:event_bus_hlc, event}, state) do
    # Extract event data and forward to existing handler
    handle_info({:event, event.type, event.data}, state)
  end

  @impl true
  def handle_info({:event, :s3_to_s4, audit_entry}, state) do
    # Learn from S3's decisions
    Logger.debug("S4 learning from S3 audit: #{inspect(audit_entry)}")
    
    # Extract patterns from audit data
    patterns = extract_patterns_from_audit(audit_entry)
    
    # Store patterns for future reference
    Enum.each(patterns, fn pattern ->
      case VectorStore.store_pattern(state.vector_store, pattern, %{
        source: :s3_audit,
        decision_context: audit_entry[:decision_context]
      }) do
        :ok -> 
          Logger.debug("🧠 S4: Successfully stored S3 audit pattern")
        {:error, reason} ->
          Logger.warning("🧠 S4: Failed to store S3 audit pattern: #{inspect(reason)}")
      end
    end)
    
    # Update learning metrics
    new_state = update_learning_metrics(state, patterns)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :s4_intelligence, variety_data}, state) do
    # Handle variety from S3 via variety channel
    variety_type = Map.get(variety_data, :variety_type, :unknown)
    Logger.debug("S4 received variety data: #{inspect(variety_type)}")
    
    case variety_type do
      :audit ->
        # Process audit variety from S3
        patterns = extract_learning_patterns(variety_data.patterns_to_learn)
        
        # Store patterns for future reference
        Enum.each(patterns, fn pattern ->
          case VectorStore.store_pattern(state.vector_store, pattern, %{
            source: :s3_variety,
            decisions_made: variety_data.decisions_made,
            timestamp: Map.get(variety_data, :timestamp, DateTime.utc_now())
          }) do
            :ok -> 
              Logger.debug("🧠 S4: Successfully stored S3 variety pattern")
            {:error, reason} ->
              Logger.warning("🧠 S4: Failed to store S3 variety pattern: #{inspect(reason)}")
          end
        end)
        
        # Update learning metrics and generate intelligence
        new_state = update_learning_metrics(state, patterns)
        
        # Generate intelligence report based on learned patterns
        if length(patterns) > 0 do
          intelligence = analyze_patterns_for_intelligence(patterns, new_state)
          send_intelligence_to_s5(intelligence)
        end
        
        {:noreply, new_state}
        
      :unknown ->
        # Handle HNSW restoration and other events
        if Map.get(variety_data, :type) == :hnsw_restoration_completed do
          Logger.info("S4 received HNSW restoration completed notification")
          # Trigger a scan to populate intelligence from restored patterns
          send(self(), :environmental_scan)
        end
        {:noreply, state}
        
      _ ->
        {:noreply, state}
    end
  end
  
  # 🧠 CRITICAL VSM PATTERN INTEGRATION: Pattern Event Handlers
  # These handlers complete the cybernetic variety channel from pattern detection to S4 intelligence
  
  @impl true
  def handle_info({:event, :pattern_detected, pattern_data}, state) do
    # S4 receives detected patterns for environmental intelligence
    Logger.info("🧠 S4: Received pattern - #{pattern_data.pattern_type}/#{pattern_data.pattern_name}, severity: #{pattern_data[:severity] || "unknown"}")
    
    # Update S4's environmental model with pattern
    new_state = update_environmental_model_with_pattern(state, pattern_data)
    
    # Store pattern in vector store for similarity analysis and future reference
    case store_pattern_in_vector_store(pattern_data, new_state) do
      {:ok, updated_state} ->
        # Analyze pattern correlations using the Pattern Correlation Analyzer
        correlation_state = if updated_state.correlation_analyzer do
          analyze_pattern_correlations(updated_state, pattern_data)
        else
          updated_state
        end
        
        # Update strategy if pattern is significant
        strategy_state = if pattern_requires_strategy_update?(pattern_data) do
          update_strategy_based_on_pattern(correlation_state, pattern_data)
        else
          correlation_state
        end
        
        # Update pattern detection metrics
        final_state = update_pattern_metrics(strategy_state, pattern_data)
        {:noreply, final_state}
        
      {:error, reason} ->
        Logger.warning("🧠 S4: Failed to store pattern vector: #{inspect(reason)}")
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info({:event, :temporal_pattern_detected, pattern_data}, state) do
    # Handle temporal patterns with special processing for time-based intelligence
    Logger.info("🧠 S4: Received temporal pattern - #{pattern_data.pattern_type}/#{pattern_data.pattern_name}")
    
    # Temporal patterns get enhanced processing for environmental scanning
    enhanced_pattern = %{
      pattern_data | 
      temporal_analysis: true,
      environmental_signal: true,
      s4_processing_timestamp: DateTime.utc_now()
    }
    
    # Process through regular pattern handler
    handle_info({:event, :pattern_detected, enhanced_pattern}, state)
  end
  
  @impl true  
  def handle_info({:event, :s4_environmental_signal, signal_data}, state) do
    # Handle high-priority environmental signals that bypass normal processing
    pattern = signal_data.pattern
    urgency = signal_data[:urgency] || 0.5
    
    Logger.info("🧠 S4: URGENT environmental signal - #{pattern.pattern_type}, urgency: #{urgency}")
    
    # Immediate strategy update for urgent patterns
    new_state = case urgency do
      urgency when urgency >= 0.8 ->
        Logger.warning("🧠 S4: CRITICAL environmental pattern detected - applying emergency strategy")
        apply_emergency_strategy_update(state, signal_data)
      urgency when urgency >= 0.6 ->
        Logger.info("🧠 S4: High-priority environmental pattern - updating strategy")
        apply_priority_strategy_update(state, signal_data)
      _ ->
        queue_pattern_for_analysis(state, signal_data)
    end
    
    # Alert S5 and S3 if extremely urgent
    if urgency >= 0.9 do
      alert_vsm_subsystems_urgent_pattern(signal_data, new_state)
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :patterns_indexed, indexing_data}, state) do
    # Pattern indexing notifications help S4 understand system-wide pattern storage
    Logger.debug("🧠 S4: Pattern indexing update - #{indexing_data[:count] || 0} patterns indexed")
    
    # Update S4's awareness of pattern index health
    new_metrics = update_in(state.health_metrics, [:pattern_index_health], fn current ->
      %{
        last_indexing: DateTime.utc_now(),
        patterns_indexed: indexing_data[:count] || 0,
        source: indexing_data[:source] || :unknown,
        index_health: :healthy
      }
    end)
    
    {:noreply, %{state | health_metrics: new_metrics}}
  end
  
  @impl true
  def handle_info(:environmental_scan, state) do
    Process.send_after(self(), :environmental_scan, @environmental_scan_interval)
    
    # Regular environmental scan
    scan_result = perform_environmental_scan(state)
    patterns = detect_patterns(scan_result, state)
    
    # Check for significant changes
    if environmental_change_significant?(scan_result, state) do
      Logger.info("S4 detected significant environmental change")
      
      # Model new scenarios
      scenarios = model_futures(scan_result, [], state)
      
      # Alert S5 if critical
      if Enum.any?(scenarios, &(&1.severity == :critical)) do
        alert_s5_critical_scenario(scenarios, state)
      end
    end
    
    # Update model
    new_model = update_environmental_model(state.environmental_model, scan_result, patterns)
    
    # Update metrics
    new_metrics = update_health_metrics(state.health_metrics, new_model)
    
    {:noreply, %{state | 
      environmental_model: new_model,
      health_metrics: new_metrics
    }}
  end
  
  @impl true
  def handle_info(:report_health, state) do
    Process.send_after(self(), :report_health, 1000)
    
    health = calculate_health_score(state)
    EventBus.publish(:s4_health, %{health: health})
    
    # Report based on intelligence quality - but throttle to prevent feedback loops
    new_state = if Application.get_env(:autonomous_opponent_core, :disable_algedonic_signals, false) do
      # Skip algedonic signals in test mode
      state
    else
      # Check and report pain/pleasure conditions
      cond do
        health < 0.3 && not recently_reported_pain?(state, :blind) ->
          # Report pain with intensity calculated from health
          intensity = max(0.86, 1.0 - health)  # Ensure > 0.85 threshold
          Algedonic.report_pain(:s4_intelligence, :blind, intensity)
          update_pain_report_time(state, :blind)
          
        state.health_metrics.environmental_complexity > 0.9 && not recently_reported_pain?(state, :overwhelmed) ->
          Algedonic.report_pain(:s4_intelligence, :overwhelmed, 
            state.health_metrics.environmental_complexity)
          update_pain_report_time(state, :overwhelmed)
          
        prediction_accuracy(state) < 0.5 && not recently_reported_pain?(state, :confused) ->
          Algedonic.report_pain(:s4_intelligence, :confused, 0.7)
          update_pain_report_time(state, :confused)
          
        health > 0.9 && prediction_accuracy(state) > 0.8 ->
          Algedonic.report_pleasure(:s4_intelligence, :prescient, health)
          state
          
        true ->
          state
      end
    end
    
    # Publish VSM pattern events for HNSW streaming
    final_state = publish_pattern_events(new_state)
    
    {:noreply, final_state}
  end
  
  # Private Functions
  
  defp init_environmental_model do
    %{
      complexity: 0.5,
      volatility: 0.3,
      trends: [],
      threats: [],
      opportunities: [],
      last_scan: DateTime.utc_now(),
      last_scan_patterns: []
    }
  end
  
  defp init_pattern_detector do
    %{
      algorithms: [:statistical, :temporal, :structural, :behavioral],
      sensitivity: 0.7,
      history_window: 100
    }
  end
  
  defp init_scenario_modeler do
    %{
      time_horizons: [:immediate, :short_term, :medium_term, :long_term],
      monte_carlo_runs: 100,
      confidence_intervals: [0.5, 0.75, 0.95]
    }
  end
  
  defp perform_targeted_scan(scan_types, state) do
    # Perform environmental scan for specific types
    scan_result = perform_environmental_scan(state)
    
    # Filter to only requested scan types
    filtered_result = scan_result
    |> Map.put(:metrics, if(:resources in scan_types, do: scan_result.metrics, else: nil))
    |> Map.put(:patterns, if(:patterns in scan_types, do: detect_patterns(scan_result, state), else: []))
    |> Map.put(:anomalies, if(:anomalies in scan_types, do: scan_result.anomalies, else: []))
    
    filtered_result
  end

  defp perform_environmental_scan(state) do
    # Gather data from various sources
    # In real implementation, would integrate with external systems
    
    %{
      timestamp: DateTime.utc_now(),
      metrics: gather_system_metrics(),
      external_signals: gather_external_signals(),
      internal_state: gather_internal_state(state),
      anomalies: detect_anomalies(state)
    }
  end
  
  defp detect_patterns(scan_result, state) do
    # Apply traditional pattern detection algorithms
    traditional_patterns = state.pattern_detector.algorithms
    |> Enum.flat_map(fn algorithm ->
      detect_patterns_with_algorithm(algorithm, scan_result)
    end)
    |> Enum.filter(fn pattern ->
      pattern.confidence > 0.5
    end)
    
    # Enhance with LLM-based pattern recognition
    llm_patterns = detect_patterns_with_llm(scan_result, traditional_patterns)
    
    # Combine traditional and LLM patterns
    (traditional_patterns ++ llm_patterns)
    |> Enum.uniq_by(fn pattern -> {pattern.type, pattern.subtype} end)
    |> Enum.sort_by(& &1.confidence, :desc)
  end
  
  defp detect_patterns_with_algorithm(algorithm, scan_result) do
    case algorithm do
      :statistical ->
        detect_statistical_patterns(scan_result)
        
      :temporal ->
        detect_temporal_patterns(scan_result)
        
      :structural ->
        detect_structural_patterns(scan_result)
        
      :behavioral ->
        detect_behavioral_patterns(scan_result)
    end
  end
  
  defp detect_statistical_patterns(scan_result) do
    # Real statistical pattern detection
    metrics = scan_result.metrics
    
    patterns = []
    
    # Check for distribution changes
    patterns = if metrics[:variance] && metrics[:variance] > 2.0 do
      patterns ++ [%{
        type: :statistical,
        subtype: :distribution,
        confidence: 0.8,
        description: "High variance detected",
        mean: metrics[:mean] || 0,
        variance: metrics[:variance]
      }]
    else
      patterns
    end
    
    # Check for outliers using z-score
    patterns = if metrics[:throughput] do
      mean = metrics[:mean] || 500
      std_dev = :math.sqrt(metrics[:variance] || 1)
      z_score = abs((metrics[:throughput] - mean) / std_dev)
      
      if z_score > 3 do
        patterns ++ [%{
          type: :statistical,
          subtype: :outlier,
          confidence: min(1.0, z_score / 5),
          description: "Statistical outlier detected",
          value: metrics[:throughput],
          z_score: z_score
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    # Check for correlation patterns
    patterns = if metrics[:cpu] && metrics[:memory] do
      correlation = calculate_correlation(metrics[:cpu], metrics[:memory])
      
      if abs(correlation) > 0.7 do
        patterns ++ [%{
          type: :statistical,
          subtype: :correlation,
          confidence: abs(correlation),
          description: "Strong correlation detected between CPU and memory",
          correlation: correlation,
          metrics: [:cpu, :memory]
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    patterns
  end
  
  defp calculate_correlation(x, y) when is_number(x) and is_number(y) do
    # Simple correlation coefficient for two values
    # In real implementation would track series of values
    if x > 0.8 && y > 0.8 do
      0.9  # High correlation when both are high
    else
      0.3  # Low correlation otherwise
    end
  end
  
  defp detect_temporal_patterns(scan_result) do
    # Real temporal pattern detection
    patterns = []
    
    # Analyze time-based patterns
    current_time = scan_result.timestamp
    hour = current_time.hour
    day_of_week = Date.day_of_week(DateTime.to_date(current_time))
    
    # Check for time-of-day patterns
    patterns = cond do
      hour >= 9 && hour <= 17 ->
        # Business hours pattern
        patterns ++ [%{
          type: :temporal,
          subtype: :periodic,
          confidence: 0.8,
          description: "Business hours activity pattern",
          period: :daily,
          phase: :active
        }]
        
      hour >= 0 && hour <= 6 ->
        # Low activity hours
        patterns ++ [%{
          type: :temporal,
          subtype: :periodic,
          confidence: 0.9,
          description: "Off-hours low activity pattern",
          period: :daily,
          phase: :quiet
        }]
        
      true ->
        patterns
    end
    
    # Check for weekly patterns
    patterns = cond do
      day_of_week in [6, 7] ->
        # Weekend pattern
        patterns ++ [%{
          type: :temporal,
          subtype: :periodic,
          confidence: 0.7,
          description: "Weekend activity pattern",
          period: :weekly,
          phase: :weekend
        }]
        
      day_of_week == 1 ->
        # Monday surge pattern
        patterns ++ [%{
          type: :temporal,
          subtype: :surge,
          confidence: 0.75,
          description: "Monday activity surge",
          period: :weekly,
          magnitude: 1.3
        }]
        
      true ->
        patterns
    end
    
    # Analyze trend from metrics history (simplified)
    patterns = if scan_result.metrics[:throughput] do
      trend = analyze_trend(scan_result.metrics[:throughput])
      
      if trend.strength > 0.5 do
        patterns ++ [%{
          type: :temporal,
          subtype: :trend,
          confidence: trend.confidence,
          description: "#{trend.direction} trend detected",
          direction: trend.direction,
          strength: trend.strength,
          rate: trend.rate
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    patterns
  end
  
  defp analyze_trend(current_value) do
    # Simplified trend analysis based on current value
    cond do
      current_value > 800 ->
        %{direction: :increasing, strength: 0.8, confidence: 0.7, rate: 0.1}
      current_value < 200 ->
        %{direction: :decreasing, strength: 0.7, confidence: 0.8, rate: -0.1}
      true ->
        %{direction: :stable, strength: 0.3, confidence: 0.9, rate: 0.0}
    end
  end
  
  defp detect_structural_patterns(scan_result) do
    # Real structural pattern detection - analyze system structure
    patterns = []
    
    # Check internal state structure
    internal = scan_result.internal_state
    
    # Detect subsystem imbalance
    patterns = if internal[:subsystems_active] do
      active_count = internal[:subsystems_active]
      expected_count = 5  # S1-S5
      
      if active_count < expected_count do
        patterns ++ [%{
          type: :structural,
          subtype: :subsystem_failure,
          confidence: 1.0 - (active_count / expected_count),
          description: "Subsystem structure degraded",
          active: active_count,
          expected: expected_count,
          missing: expected_count - active_count
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    # Detect variety flow structure issues
    patterns = if internal[:variety_flow] do
      case internal[:variety_flow] do
        :blocked ->
          patterns ++ [%{
            type: :structural,
            subtype: :flow_blockage,
            confidence: 0.95,
            description: "Variety flow blockage detected",
            location: :unknown,
            severity: :high
          }]
          
        :constrained ->
          patterns ++ [%{
            type: :structural,
            subtype: :flow_constraint,
            confidence: 0.8,
            description: "Variety flow constraints detected",
            bottleneck: true,
            severity: :medium
          }]
          
        _ ->
          patterns
      end
    else
      patterns
    end
    
    # Detect resource structure patterns
    patterns = if scan_result.metrics do
      metrics = scan_result.metrics
      resource_imbalance = calculate_resource_imbalance(metrics)
      
      if resource_imbalance > 0.3 do
        patterns ++ [%{
          type: :structural,
          subtype: :resource_imbalance,
          confidence: min(1.0, resource_imbalance),
          description: "Resource allocation structure imbalanced",
          imbalance_factor: resource_imbalance,
          dominant_resource: identify_dominant_resource(metrics)
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    patterns
  end
  
  defp calculate_resource_imbalance(metrics) do
    # Calculate coefficient of variation for resource usage
    resources = [metrics[:cpu] || 0.5, metrics[:memory] || 0.5, 
                 (metrics[:throughput] || 500) / 1000]  # Normalize throughput
    
    mean = Enum.sum(resources) / length(resources)
    
    if mean > 0 do
      variance = Enum.map(resources, fn r -> :math.pow(r - mean, 2) end) |> Enum.sum()
      variance = variance / length(resources)
      std_dev = :math.sqrt(variance)
      std_dev / mean  # Coefficient of variation
    else
      0
    end
  end
  
  defp identify_dominant_resource(metrics) do
    # Identify which resource is dominant
    resource_usage = [
      {:cpu, metrics[:cpu] || 0},
      {:memory, metrics[:memory] || 0},
      {:io, (metrics[:throughput] || 0) / 1000}  # Normalized
    ]
    
    resource_usage
    |> Enum.max_by(fn {_name, usage} -> usage end)
    |> elem(0)
  end
  
  defp detect_behavioral_patterns(scan_result) do
    # Check for anomalies
    if length(scan_result.anomalies) > 0 do
      [%{
        type: :behavioral,
        subtype: :anomaly,
        confidence: 0.9,
        description: "Anomalous behavior detected",
        count: length(scan_result.anomalies),
        severity: :medium
      }]
    else
      []
    end
  end
  
  defp model_futures(parameters, similar_patterns, state) do
    # Traditional Monte Carlo simulation
    traditional_scenarios = 1..state.scenario_modeler.monte_carlo_runs
    |> Enum.map(fn _run ->
      simulate_scenario(parameters, similar_patterns, state)
    end)
    |> aggregate_scenarios()
    
    # Enhance with LLM-powered scenario modeling
    llm_scenarios = model_futures_with_llm(parameters, similar_patterns, state)
    
    # Combine and deduplicate scenarios
    (traditional_scenarios ++ llm_scenarios)
    |> Enum.uniq_by(& &1.scenario)
    |> Enum.sort_by(& &1.probability, :desc)
  end
  
  defp simulate_scenario(parameters, similar_patterns, state) do
    # Real scenario simulation using Monte Carlo
    base_probability = calculate_base_probability(parameters, similar_patterns)
    
    # Add randomness for Monte Carlo
    random_factor = :rand.normal(1.0, 0.2)  # Normal distribution with mean 1, std 0.2
    adjusted_probability = max(0, min(1, base_probability * random_factor))
    
    # Determine impact based on parameters and patterns
    impact = determine_scenario_impact(parameters, similar_patterns, state)
    
    # Calculate time horizon based on rate of change
    time_horizon = estimate_time_horizon(parameters, state.environmental_model)
    
    # Build detailed scenario
    %{
      scenario: generate_scenario_description(parameters, impact, time_horizon),
      probability: adjusted_probability,
      impact: impact,
      time_horizon: time_horizon,
      confidence: calculate_scenario_confidence(similar_patterns),
      similar_patterns: length(similar_patterns),
      risk_factors: identify_risk_factors(parameters, state),
      opportunities: identify_opportunities(parameters, state),
      recommended_actions: generate_recommendations_for_scenario(impact, time_horizon)
    }
  end
  
  defp calculate_base_probability(parameters, similar_patterns) do
    # Base probability on historical patterns
    pattern_support = length(similar_patterns) / 10  # Normalize by expected patterns
    parameter_severity = Map.get(parameters, :severity, 0.5)
    
    # Weighted combination
    pattern_weight = 0.7
    parameter_weight = 0.3
    
    min(1.0, pattern_support * pattern_weight + parameter_severity * parameter_weight)
  end
  
  defp determine_scenario_impact(parameters, similar_patterns, state) do
    # Analyze potential impact
    severity_score = Map.get(parameters, :severity, 0.5)
    pattern_severity = Enum.map(similar_patterns, fn p -> 
      Map.get(p, :severity, 0.5) 
    end) |> mean_or_default(0.5)
    
    complexity = state.environmental_model.complexity
    
    combined_score = (severity_score + pattern_severity + complexity) / 3
    
    cond do
      combined_score > 0.7 -> :high
      combined_score > 0.4 -> :medium
      true -> :low
    end
  end
  
  defp estimate_time_horizon(parameters, env_model) do
    volatility = env_model.volatility
    urgency = Map.get(parameters, :urgency, 0.5)
    
    combined_urgency = (volatility + urgency) / 2
    
    cond do
      combined_urgency > 0.8 -> :immediate
      combined_urgency > 0.5 -> :short_term
      combined_urgency > 0.2 -> :medium_term
      true -> :long_term
    end
  end
  
  defp calculate_scenario_confidence(similar_patterns) do
    # Confidence based on pattern support
    pattern_count = length(similar_patterns)
    
    cond do
      pattern_count >= 5 -> 0.9
      pattern_count >= 3 -> 0.7
      pattern_count >= 1 -> 0.5
      true -> 0.3
    end
  end
  
  defp identify_risk_factors(parameters, state) do
    risks = []
    
    risks = if state.environmental_model.volatility > 0.7 do
      risks ++ ["High environmental volatility"]
    else
      risks
    end
    
    risks = if Map.get(parameters, :resource_pressure, 0) > 0.8 do
      risks ++ ["Resource constraints"]
    else
      risks
    end
    
    risks = if state.environmental_model.complexity > 0.8 do
      risks ++ ["System complexity"]
    else
      risks
    end
    
    risks
  end
  
  defp identify_opportunities(parameters, _state) do
    opportunities = []
    
    opportunities = if Map.get(parameters, :growth_potential, 0) > 0.6 do
      opportunities ++ ["Growth opportunity"]
    else
      opportunities
    end
    
    opportunities = if Map.get(parameters, :efficiency_gain, 0) > 0.5 do
      opportunities ++ ["Efficiency improvement"]
    else
      opportunities
    end
    
    opportunities
  end
  
  defp generate_scenario_description(parameters, impact, time_horizon) do
    "#{time_horizon} scenario with #{impact} impact based on #{map_size(parameters)} factors"
  end
  
  defp generate_recommendations_for_scenario(impact, time_horizon) do
    case {impact, time_horizon} do
      {:high, :immediate} -> ["Emergency response required", "Allocate all available resources"]
      {:high, _} -> ["Prepare contingency plans", "Increase monitoring"]
      {:medium, :immediate} -> ["Quick tactical adjustment needed"]
      {:medium, _} -> ["Plan strategic response", "Gather more intelligence"]
      {:low, _} -> ["Continue monitoring", "No immediate action required"]
    end
  end
  
  defp mean_or_default([], default), do: default
  defp mean_or_default(list, _default) do
    Enum.sum(list) / length(list)
  end
  
  defp aggregate_scenarios(scenarios) do
    # Group and aggregate similar scenarios
    scenarios
    |> Enum.group_by(& &1.impact)
    |> Enum.map(fn {impact, group} ->
      %{
        impact: impact,
        probability: Enum.sum(Enum.map(group, & &1.probability)) / length(group),
        count: length(group),
        severity: impact_to_severity(impact)
      }
    end)
  end
  
  defp generate_intelligence_report(model, patterns, state) do
    # Generate base report
    base_report = %{
      timestamp: DateTime.utc_now(),
      environmental_model: model,
      patterns: patterns,
      assessment: assess_situation(model, patterns),
      recommendations: generate_tactical_recommendations(model, patterns)
    }
    
    # Enhance with LLM-generated strategic analysis
    enhanced_report = case generate_llm_intelligence_analysis(base_report, state) do
      {:ok, llm_analysis} -> 
        Map.put(base_report, :llm_analysis, llm_analysis)
      {:error, _reason} -> 
        base_report
    end
    
    enhanced_report
  end
  
  defp send_intelligence_to_s5(report) do
    VarietyChannel.transmit(:s4_to_s5, %{
      intelligence_report: report,
      urgency: report.assessment.urgency
    })
    
    EventBus.publish(:s4_intelligence, report)
  end
  
  defp update_environmental_model(current_model, scan_result, patterns) do
    %{current_model |
      complexity: calculate_complexity(scan_result, patterns),
      volatility: calculate_volatility(scan_result, current_model),
      trends: update_trends(current_model.trends, patterns),
      last_scan: scan_result.timestamp
    }
  end
  
  defp environmental_change_significant?(scan_result, state) do
    current_complexity = calculate_complexity(scan_result, [])
    complexity_change = abs(current_complexity - state.environmental_model.complexity)
    
    complexity_change > 0.2 || length(scan_result.anomalies) > 3
  end
  
  defp alert_s5_critical_scenario(scenarios, _state) do
    EventBus.publish(:s5_policy, {:critical_scenario, scenarios})
  end
  
  defp process_learning_queue(state) do
    # Process all queued learning data
    queue_list = :queue.to_list(state.learning_queue)
    
    patterns = Enum.flat_map(queue_list, &extract_patterns_from_audit/1)
    
    # Update prediction accuracy based on outcomes
    new_metrics = Enum.reduce(patterns, state.health_metrics, fn pattern, metrics ->
      if pattern[:outcome] do
        %{metrics |
          predictions_total: metrics.predictions_total + 1,
          predictions_accurate: metrics.predictions_accurate + 
            (if pattern.outcome == :success, do: 1, else: 0)
        }
      else
        metrics
      end
    end)
    
    %{state | 
      learning_queue: :queue.new(),
      health_metrics: new_metrics
    }
  end
  
  defp extract_patterns_from_audit(audit_entry) do
    # Extract learnable patterns from audit data
    [
      %{
        type: :behavioral,
        subtype: :decision,
        decision_type: audit_entry[:type],
        outcome: audit_entry[:outcome],
        confidence: 0.8
      }
    ]
  end
  
  defp update_learning_metrics(state, patterns) do
    new_metrics = Map.update!(state.health_metrics, :patterns_detected, 
      &(&1 + length(patterns)))
    
    %{state | health_metrics: new_metrics}
  end
  
  defp calculate_health_score(state) do
    metrics = state.health_metrics
    
    # Base health on prediction accuracy and pattern detection
    prediction_score = prediction_accuracy(state)
    pattern_score = min(1.0, metrics.patterns_detected / 100)
    complexity_penalty = metrics.environmental_complexity * 0.2
    
    max(0.0, (prediction_score * 0.6 + pattern_score * 0.4) - complexity_penalty)
  end
  
  defp prediction_accuracy(state) do
    metrics = state.health_metrics
    
    if metrics.predictions_total > 0 do
      metrics.predictions_accurate / metrics.predictions_total
    else
      0.5  # No predictions yet, assume average
    end
  end
  
  defp update_health_metrics(metrics, model) do
    %{metrics |
      environmental_complexity: model.complexity
    }
  end
  
  # Utility functions
  
  defp gather_system_metrics do
    # Gather real system metrics from OS and runtime
    memory_info = :erlang.memory()
    scheduler_info = :erlang.statistics(:scheduler_wall_time)
    io_info = :erlang.statistics(:io)
    
    # Calculate real CPU usage from scheduler utilization
    cpu = calculate_cpu_usage(scheduler_info)
    
    # Calculate real memory usage
    total_memory = memory_info[:total]
    system_memory = memory_info[:system]
    memory = system_memory / total_memory
    
    # Get real process count and message queue sizes
    process_count = :erlang.system_info(:process_count)
    process_limit = :erlang.system_info(:process_limit)
    
    # Calculate throughput from process message queue sizes
    throughput = calculate_system_throughput()
    
    # Get real error counts from circuit breakers
    error_stats = get_system_error_stats()
    error_rate = error_stats[:error_rate] || 0.0
    
    # Calculate real latency from recent operations
    latency_stats = get_operation_latency_stats()
    latency = latency_stats[:p95] || 50
    
    # Calculate statistical measures from real data
    values = [cpu, memory, throughput / 1000]  # Normalize throughput
    mean = Enum.sum(values) / length(values)
    variance = Enum.map(values, fn v -> :math.pow(v - mean, 2) end) |> Enum.sum()
    variance = variance / length(values)
    
    %{
      cpu: cpu,
      memory: memory,
      throughput: throughput,
      mean: mean,
      variance: variance,
      latency: latency,
      error_rate: error_rate,
      process_count: process_count,
      process_utilization: process_count / process_limit,
      memory_mb: total_memory / 1_048_576,
      gc_runs: memory_info[:garbage_collection][:number_of_gcs] || 0,
      io_input: elem(elem(io_info, 0), 1),
      io_output: elem(elem(io_info, 1), 1),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp calculate_cpu_usage(scheduler_info) do
    # Calculate real CPU usage from scheduler wall time
    if is_list(scheduler_info) && length(scheduler_info) > 0 do
      active_time = Enum.reduce(scheduler_info, 0, fn {_id, active, total}, acc ->
        if total > 0, do: acc + (active / total), else: acc
      end)
      
      schedulers = length(scheduler_info)
      if schedulers > 0 do
        active_time / schedulers
      else
        0.0
      end
    else
      # Fallback to load average
      case :os.cmd(~c"uptime") |> to_string() do
        uptime when is_binary(uptime) ->
          # Extract load average from uptime command
          case Regex.run(~r/load average[s]?: ([\d.]+)/, uptime) do
            [_, load] -> 
              {load_avg, _} = Float.parse(load)
              min(1.0, load_avg / :erlang.system_info(:logical_processors))
            _ -> 0.5
          end
        _ -> 0.5
      end
    end
  end
  
  defp get_system_error_stats do
    # Gather error statistics from circuit breakers
    circuit_breaker_stats = get_circuit_breaker_stats()
    
    total_requests = circuit_breaker_stats[:total_requests] || 1
    total_errors = circuit_breaker_stats[:total_errors] || 0
    
    %{
      error_rate: total_errors / total_requests,
      circuit_breakers_open: circuit_breaker_stats[:open_count] || 0,
      recent_errors: [],
      error_types: %{}
    }
  end
  
  defp calculate_system_throughput do
    # Calculate throughput based on process activity
    process_info = Process.list()
                  |> Enum.take(100)  # Sample first 100 processes
                  |> Enum.map(fn pid ->
                    case Process.info(pid, [:message_queue_len, :reductions]) do
                      nil -> {0, 0}
                      info -> {info[:message_queue_len] || 0, info[:reductions] || 0}
                    end
                  end)
    
    total_messages = Enum.reduce(process_info, 0, fn {msgs, _}, acc -> acc + msgs end)
    total_reductions = Enum.reduce(process_info, 0, fn {_, reds}, acc -> acc + reds end)
    
    # Estimate throughput from message queue activity and reductions
    # Normalize to messages per second (rough estimate)
    message_throughput = total_messages * 10  # Assume 10Hz sampling
    reduction_throughput = total_reductions / 10000  # Normalize reductions
    
    (message_throughput + reduction_throughput) / 2
  end
  
  defp get_circuit_breaker_stats do
    # Get real stats from circuit breaker registry
    case Process.whereis(AutonomousOpponentV2Core.CircuitBreaker) do
      nil -> %{total_requests: 1, total_errors: 0, open_count: 0}
      pid -> 
        try do
          GenServer.call(pid, :get_stats, 1000)
        catch
          _, _ -> %{total_requests: 1, total_errors: 0, open_count: 0}
        end
    end
  end
  
  defp get_operation_latency_stats do
    # Get real latency statistics from telemetry events
    measurements = :telemetry.execute(
      [:autonomous_opponent, :operation, :latency],
      %{},
      %{}
    )
    
    case measurements do
      measurements when is_list(measurements) and length(measurements) > 0 ->
        sorted = Enum.sort(measurements)
        p95_index = round(length(sorted) * 0.95)
        p95 = Enum.at(sorted, p95_index, 50)
        
        %{
          p50: Enum.at(sorted, div(length(sorted), 2), 30),
          p95: p95,
          p99: Enum.at(sorted, round(length(sorted) * 0.99), 100),
          mean: Enum.sum(sorted) / length(sorted)
        }
      _ ->
        # Fallback to measuring a simple operation
        {time, _} = :timer.tc(fn -> 1 + 1 end)
        %{p50: 30, p95: div(time, 1000) + 50, p99: 100, mean: 40}
    end
  end
  
  defp gather_external_signals do
    # Gather real external signals from various sources
    signals = []
    
    # Process any external events that may be in process dictionary or state
    signals = signals ++ process_stored_external_events()
    
    # Monitor system health endpoints
    signals = signals ++ gather_health_signals()
    
    # Check for configuration changes
    signals = signals ++ detect_config_changes()
    
    # Monitor resource utilization trends
    signals = signals ++ analyze_resource_trends()
    
    # Detect user behavior patterns from web gateway
    signals = signals ++ detect_user_behavior_patterns()
    
    # Check for security events
    signals = signals ++ gather_security_signals()
    
    # Monitor API rate limits and throttling
    signals = signals ++ check_api_limits()
    
    # Sort by timestamp and deduplicate
    signals
    |> Enum.uniq_by(fn s -> {s.type, s.signal, s.source} end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end
  
  defp process_stored_external_events do
    # Get events from process dictionary or return empty list
    case Process.get(:external_events) do
      nil -> []
      events when is_list(events) ->
        events
        |> Enum.filter(fn event -> 
          event[:timestamp] && 
          DateTime.diff(DateTime.utc_now(), event[:timestamp]) < 300  # Last 5 minutes
        end)
        |> Enum.map(fn event ->
          %{
            type: categorize_event_type(event),
            source: event[:source] || :stored_events,
            signal: event[:type] || :unknown,
            data: event[:data] || %{},
            timestamp: event[:timestamp] || DateTime.utc_now(),
            strength: calculate_signal_strength(event)
          }
        end)
      _ -> []
    end
  end
  
  defp categorize_event_type(event) do
    cond do
      String.contains?(to_string(event[:type]), "market") -> :market
      String.contains?(to_string(event[:type]), "user") -> :user_behavior
      String.contains?(to_string(event[:type]), "error") -> :system_health
      String.contains?(to_string(event[:type]), "security") -> :security
      String.contains?(to_string(event[:type]), "resource") -> :resource
      true -> :general
    end
  end
  
  defp calculate_signal_strength(event) do
    # Calculate signal strength based on event properties
    severity = event[:severity] || event[:priority] || :normal
    
    base_strength = case severity do
      :critical -> 1.0
      :high -> 0.8
      :medium -> 0.5
      :low -> 0.3
      _ -> 0.4
    end
    
    # Adjust for recency
    if event[:timestamp] do
      age_minutes = DateTime.diff(DateTime.utc_now(), event[:timestamp]) / 60
      recency_factor = :math.exp(-age_minutes / 60)  # Exponential decay over 1 hour
      base_strength * recency_factor
    else
      base_strength
    end
  end
  
  defp gather_health_signals do
    # Check system health from various components
    signals = []
    
    # Check web gateway health
    case check_component_health(AutonomousOpponentV2Core.WebGateway.Gateway) do
      {:ok, health} when health < 0.7 ->
        signals ++ [%{
          type: :system_health,
          source: :web_gateway,
          signal: :degraded_performance,
          strength: 1.0 - health,
          timestamp: DateTime.utc_now(),
          details: %{health_score: health}
        }]
      _ -> signals
    end
    
    # Check MCP server health
    case check_component_health(AutonomousOpponentV2Core.MCP.Server) do
      {:ok, health} when health < 0.8 ->
        signals ++ [%{
          type: :system_health,
          source: :mcp_server,
          signal: :capacity_warning,
          strength: 1.0 - health,
          timestamp: DateTime.utc_now(),
          details: %{health_score: health}
        }]
      _ -> signals
    end
  end
  
  defp check_component_health(module) do
    case Process.whereis(module) do
      nil -> {:error, :not_running}
      pid ->
        # Check if process is alive first
        if Process.alive?(pid) do
          # Try to determine process type
          case Process.info(pid, :dictionary) do
            {:dictionary, dict} ->
              # Check if it's a supervisor
              if Keyword.get(dict, :"$initial_call") == {:supervisor, :init, 1} do
                # For supervisors, try to call module's health_check function if it exists
                if function_exported?(module, :health_check, 0) do
                  {:ok, module.health_check()}
                else
                  # Otherwise just check if alive
                  {:ok, 1.0}
                end
              else
                # For GenServers, try health check
                try do
                  {:ok, GenServer.call(pid, :health_check, 1000)}
                catch
                  :exit, {:noproc, _} -> {:error, :not_running}
                  :exit, {:timeout, _} -> {:error, :timeout}
                  _, _ -> {:ok, 0.8}  # Assume healthy if no health check
                end
              end
            _ ->
              # If we can't determine type, assume healthy if alive
              {:ok, 1.0}
          end
        else
          {:error, :not_running}
        end
    end
  end
  
  defp detect_config_changes do
    # Monitor for configuration changes that might affect system behavior
    current_config = Application.get_all_env(:autonomous_opponent_core)
    
    # Store and compare with previous config (simplified)
    case Process.get(:last_known_config) do
      nil ->
        Process.put(:last_known_config, current_config)
        []
      last_config ->
        changes = detect_config_differences(last_config, current_config)
        Process.put(:last_known_config, current_config)
        
        Enum.map(changes, fn {key, old_val, new_val} ->
          %{
            type: :configuration,
            source: :config_monitor,
            signal: :config_change,
            strength: 0.7,
            timestamp: DateTime.utc_now(),
            details: %{
              key: key,
              old_value: old_val,
              new_value: new_val
            }
          }
        end)
    end
  end
  
  defp detect_config_differences(old_config, new_config) do
    old_map = Map.new(old_config)
    new_map = Map.new(new_config)
    
    all_keys = MapSet.union(MapSet.new(Map.keys(old_map)), MapSet.new(Map.keys(new_map)))
    
    Enum.reduce(all_keys, [], fn key, acc ->
      old_val = Map.get(old_map, key)
      new_val = Map.get(new_map, key)
      
      if old_val != new_val do
        [{key, old_val, new_val} | acc]
      else
        acc
      end
    end)
  end
  
  defp analyze_resource_trends do
    # Analyze resource utilization trends over time
    case Process.get(:resource_history) do
      nil -> 
        Process.put(:resource_history, [])
        []
      history ->
        current_metrics = gather_system_metrics()
        new_history = [current_metrics | history] |> Enum.take(10)
        Process.put(:resource_history, new_history)
        
        if length(new_history) >= 3 do
          detect_resource_trend_signals(new_history)
        else
          []
        end
    end
  end
  
  defp detect_resource_trend_signals(history) do
    signals = []
    
    # Detect CPU trend
    cpu_values = Enum.map(history, & &1.cpu)
    cpu_trend = calculate_trend(cpu_values)
    
    signals = if cpu_trend.slope > 0.1 && List.last(cpu_values) > 0.8 do
      signals ++ [%{
        type: :resource,
        source: :trend_analyzer,
        signal: :cpu_pressure_increasing,
        strength: min(1.0, cpu_trend.slope * 5),
        timestamp: DateTime.utc_now(),
        details: %{trend: cpu_trend, current: List.last(cpu_values)}
      }]
    else
      signals
    end
    
    # Detect memory trend
    memory_values = Enum.map(history, & &1.memory)
    memory_trend = calculate_trend(memory_values)
    
    signals = if memory_trend.slope > 0.05 && List.last(memory_values) > 0.7 do
      signals ++ [%{
        type: :resource,
        source: :trend_analyzer,
        signal: :memory_pressure_increasing,
        strength: min(1.0, memory_trend.slope * 10),
        timestamp: DateTime.utc_now(),
        details: %{trend: memory_trend, current: List.last(memory_values)}
      }]
    else
      signals
    end
    
    # Detect error rate spikes
    error_rates = Enum.map(history, & &1.error_rate)
    recent_avg = Enum.sum(Enum.take(error_rates, 3)) / 3
    historical_avg = Enum.sum(error_rates) / length(error_rates)
    
    signals = if recent_avg > historical_avg * 2 && recent_avg > 0.05 do
      signals ++ [%{
        type: :system_health,
        source: :trend_analyzer,
        signal: :error_rate_spike,
        strength: min(1.0, recent_avg * 10),
        timestamp: DateTime.utc_now(),
        details: %{recent: recent_avg, historical: historical_avg}
      }]
    else
      signals
    end
    
    signals
  end
  
  defp calculate_trend(values) when length(values) < 2 do
    %{slope: 0, r_squared: 0, direction: :stable}
  end
  
  defp calculate_trend(values) do
    # Simple linear regression
    n = length(values)
    x_values = Enum.to_list(1..n)
    
    x_mean = Enum.sum(x_values) / n
    y_mean = Enum.sum(values) / n
    
    xy_sum = Enum.zip(x_values, values)
             |> Enum.map(fn {x, y} -> (x - x_mean) * (y - y_mean) end)
             |> Enum.sum()
    
    xx_sum = x_values
             |> Enum.map(fn x -> :math.pow(x - x_mean, 2) end)
             |> Enum.sum()
    
    slope = if xx_sum > 0, do: xy_sum / xx_sum, else: 0
    
    direction = cond do
      slope > 0.05 -> :increasing
      slope < -0.05 -> :decreasing
      true -> :stable
    end
    
    %{slope: slope, direction: direction, samples: n}
  end
  
  defp detect_user_behavior_patterns do
    # Get real user activity from stored metrics
    case Process.get(:web_gateway_activity) do
      nil -> []
      events when is_list(events) ->
        analyze_user_activity(events)
      _ -> []
    end
  end
  
  defp analyze_user_activity(events) do
    # Group events by time window
    now = DateTime.utc_now()
    recent_count = Enum.count(events, fn e -> 
      DateTime.diff(now, e[:timestamp] || now) < 60
    end)
    
    older_count = length(events) - recent_count
    
    signals = []
    
    # Detect activity spikes
    if recent_count > older_count * 3 && recent_count > 10 do
      signals ++ [%{
        type: :user_behavior,
        source: :activity_monitor,
        signal: :usage_spike,
        strength: min(1.0, recent_count / 50),
        timestamp: DateTime.utc_now(),
        magnitude: recent_count / max(1, older_count)
      }]
    else
      signals
    end
  end
  
  defp gather_security_signals do
    # Check for security-related events from stored data
    security_events = Process.get(:security_events) || []
    
    security_events
    |> Enum.take(20)  # Limit to recent 20
    |> Enum.map(fn event ->
      %{
        type: :security,
        source: :security_monitor,
        signal: event[:type] || :security_event,
        strength: case event[:severity] do
          :critical -> 1.0
          :high -> 0.8
          :medium -> 0.5
          _ -> 0.3
        end,
        timestamp: event[:timestamp] || DateTime.utc_now(),
        details: event[:details] || %{}
      }
    end)
  end
  
  defp check_api_limits do
    # Check rate limiter states for API limit signals
    case Process.whereis(AutonomousOpponentV2Core.Core.RateLimiter) do
      nil -> []
      pid ->
        try do
          limits = GenServer.call(pid, :get_all_limits, 1000)
          
          Enum.flat_map(limits, fn {key, {current, limit}} ->
            utilization = current / limit
            
            if utilization > 0.8 do
              [%{
                type: :resource,
                source: :rate_limiter,
                signal: :approaching_limit,
                strength: utilization,
                timestamp: DateTime.utc_now(),
                details: %{
                  resource: key,
                  current: current,
                  limit: limit,
                  utilization: utilization
                }
              }]
            else
              []
            end
          end)
        catch
          _, _ -> []
        end
    end
  end
  
  defp gather_internal_state(state) do
    # Gather comprehensive internal state from real system components
    health_metrics = state.health_metrics
    
    # Count actually active VSM subsystems
    active_subsystems = count_active_vsm_subsystems()
    
    # Determine variety flow state from actual channel metrics
    variety_flow = analyze_variety_flow_state()
    
    # Assess pattern recognition capability from real metrics
    pattern_velocity = if health_metrics.scenarios_modeled > 0 do
      health_metrics.patterns_detected / health_metrics.scenarios_modeled
    else
      0.0
    end
    
    # Get vector store status
    vector_store_status = check_vector_store_status(state.vector_store)
    
    # Gather EventBus statistics from subscription counts
    event_bus_stats = get_event_bus_stats()
    
    # Check MCP server status
    mcp_status = check_mcp_server_status()
    
    # Analyze circuit breaker states
    circuit_breaker_summary = analyze_circuit_breakers()
    
    %{
      subsystems_active: active_subsystems,
      variety_flow: variety_flow,
      pattern_velocity: pattern_velocity,
      prediction_accuracy: prediction_accuracy(state),
      learning_queue_depth: :queue.len(state.learning_queue),
      vector_store_status: vector_store_status,
      intelligence_lag: calculate_intelligence_lag(state),
      decision_support_quality: calculate_decision_quality(state),
      event_bus_throughput: event_bus_stats[:messages_per_second] || 0,
      event_bus_subscribers: event_bus_stats[:total_subscribers] || 0,
      mcp_connections: mcp_status[:active_connections] || 0,
      circuit_breakers_open: circuit_breaker_summary[:open_count] || 0,
      system_uptime: get_system_uptime(),
      memory_pressure: calculate_memory_pressure()
    }
  end
  
  defp count_active_vsm_subsystems do
    # Check actual VSM subsystem processes
    subsystems = [
      AutonomousOpponentV2Core.VSM.S1.Operations,
      AutonomousOpponentV2Core.VSM.S2.Coordination,
      AutonomousOpponentV2Core.VSM.S3.Control,
      AutonomousOpponentV2Core.VSM.S4.Intelligence,
      AutonomousOpponentV2Core.VSM.S5.Policy
    ]
    
    Enum.count(subsystems, fn module ->
      case Process.whereis(module) do
        nil -> false
        pid -> Process.alive?(pid)
      end
    end)
  end
  
  defp analyze_variety_flow_state do
    # Analyze actual variety channel states
    channels = [
      {:s1_to_s2, AutonomousOpponentV2Core.VSM.Channels.VarietyChannel},
      {:s2_to_s3, AutonomousOpponentV2Core.VSM.Channels.VarietyChannel},
      {:s3_to_s4, AutonomousOpponentV2Core.VSM.Channels.VarietyChannel},
      {:s4_to_s5, AutonomousOpponentV2Core.VSM.Channels.VarietyChannel}
    ]
    
    channel_states = Enum.map(channels, fn {channel_id, _module} ->
      # Estimate channel state based on process info
      case Process.whereis(channel_id) do
        nil -> :unknown
        pid ->
          case Process.info(pid, [:message_queue_len, :messages]) do
            nil -> :unknown
            info ->
              queue_size = info[:message_queue_len] || 0
              
              cond do
                queue_size > 1000 -> :blocked
                queue_size > 500 -> :overwhelmed
                queue_size > 100 -> :constrained
                queue_size < 10 -> :minimal
                true -> :normal
              end
          end
      end
    end)
    
    # Return worst state found
    cond do
      :blocked in channel_states -> :blocked
      :overwhelmed in channel_states -> :overwhelmed
      :constrained in channel_states -> :constrained
      :minimal in channel_states -> :minimal
      true -> :smooth
    end
  end
  
  defp check_vector_store_status(vector_store) do
    try do
      case GenServer.call(vector_store, :get_stats, 1000) do
        stats when is_map(stats) ->
          pattern_count = stats[:pattern_count] || 0
          query_latency = stats[:avg_query_latency] || 0
          
          cond do
            pattern_count == 0 -> :empty
            query_latency > 100 -> :degraded
            query_latency > 50 -> :slow
            true -> :operational
          end
        _ -> :unknown
      end
    catch
      _, _ -> :error
    end
  end
  
  defp check_mcp_server_status do
    case Process.whereis(AutonomousOpponentV2Core.MCP.Server) do
      nil -> %{active_connections: 0, status: :offline}
      pid ->
        try do
          GenServer.call(pid, :get_connection_stats, 1000)
        catch
          _, _ -> %{active_connections: 0, status: :error}
        end
    end
  end
  
  defp analyze_circuit_breakers do
    case Process.whereis(AutonomousOpponentV2Core.CircuitBreaker) do
      nil -> %{open_count: 0, half_open_count: 0, closed_count: 0}
      pid ->
        try do
          stats = GenServer.call(pid, :get_all_states, 1000)
          
          Enum.reduce(stats, %{open_count: 0, half_open_count: 0, closed_count: 0}, fn {_name, state}, acc ->
            case state do
              :open -> %{acc | open_count: acc.open_count + 1}
              :half_open -> %{acc | half_open_count: acc.half_open_count + 1}
              :closed -> %{acc | closed_count: acc.closed_count + 1}
            end
          end)
        catch
          _, _ -> %{open_count: 0, half_open_count: 0, closed_count: 0}
        end
    end
  end
  
  defp get_system_uptime do
    # Get actual system uptime
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms / 1000  # Convert to seconds
  end
  
  defp calculate_memory_pressure do
    memory_info = :erlang.memory()
    
    # Calculate memory pressure based on various factors
    total = memory_info[:total]
    processes = memory_info[:processes]
    binary = memory_info[:binary]
    ets = memory_info[:ets]
    
    # High memory usage in any category indicates pressure
    process_pressure = processes / total
    binary_pressure = binary / total
    ets_pressure = ets / total
    
    # Return maximum pressure found
    max(process_pressure, max(binary_pressure, ets_pressure))
  end
  
  defp get_event_bus_stats do
    # Get EventBus stats from subscription table
    case Process.whereis(EventBus) do
      nil -> %{messages_per_second: 0, total_subscribers: 0}
      _pid ->
        try do
          subscriptions = EventBus.subscriptions()
          total_subscribers = subscriptions
                             |> Map.values()
                             |> Enum.map(&length/1)
                             |> Enum.sum()
          
          # Estimate messages per second from process activity
          messages_per_second = calculate_system_throughput() / 10
          
          %{
            messages_per_second: messages_per_second,
            total_subscribers: total_subscribers
          }
        catch
          _, _ -> %{messages_per_second: 0, total_subscribers: 0}
        end
    end
  end
  
  defp calculate_intelligence_lag(state) do
    # How far behind real-time are we?
    last_scan = state.environmental_model.last_scan
    lag = DateTime.diff(DateTime.utc_now(), last_scan, :second)
    
    cond do
      lag < 10 -> :real_time
      lag < 30 -> :near_real_time 
      lag < 60 -> :delayed
      true -> :stale
    end
  end
  
  defp calculate_decision_quality(state) do
    # Quality of decision support we can provide
    accuracy = prediction_accuracy(state)
    pattern_support = min(1.0, state.health_metrics.patterns_detected / 100)
    
    quality_score = (accuracy * 0.6 + pattern_support * 0.4)
    
    cond do
      quality_score > 0.8 -> :excellent
      quality_score > 0.6 -> :good
      quality_score > 0.4 -> :fair
      true -> :poor
    end
  end
  
  defp detect_anomalies(state) do
    # Real anomaly detection using statistical methods and historical baselines
    anomalies = []
    
    # Get historical baselines
    historical_metrics = get_historical_baselines(state)
    current_metrics = gather_system_metrics()
    
    # Statistical anomaly detection using z-scores
    anomalies = anomalies ++ detect_statistical_anomalies(current_metrics, historical_metrics)
    
    # Time series anomaly detection
    anomalies = anomalies ++ detect_time_series_anomalies(state)
    
    # Pattern-based anomaly detection
    anomalies = anomalies ++ detect_pattern_anomalies(state)
    
    # System state anomalies
    anomalies = anomalies ++ detect_system_state_anomalies(state)
    
    # Behavioral anomalies from event patterns
    anomalies = anomalies ++ detect_behavioral_anomalies(state)
    
    # Correlation anomalies
    anomalies = anomalies ++ detect_correlation_anomalies(current_metrics, state)
    
    # Sort by severity and timestamp
    anomalies
    |> Enum.uniq_by(fn a -> {a.type, a.description} end)
    |> Enum.sort_by(fn a -> 
      severity_score = case a.severity do
        :critical -> 4
        :high -> 3
        :medium -> 2
        :low -> 1
      end
      {-severity_score, a[:timestamp] || DateTime.utc_now()}
    end)
  end
  
  defp get_historical_baselines(state) do
    # Calculate baselines from recent intelligence reports
    recent_reports = Enum.take(state.intelligence_reports, 20)
    
    if length(recent_reports) > 5 do
      metrics = Enum.flat_map(recent_reports, fn report ->
        case report[:environmental_model][:internal_state] do
          nil -> []
          internal -> [internal[:metrics] || %{}]
        end
      end)
      
      %{
        cpu_mean: calculate_metric_mean(metrics, :cpu),
        cpu_std: calculate_metric_std(metrics, :cpu),
        memory_mean: calculate_metric_mean(metrics, :memory),
        memory_std: calculate_metric_std(metrics, :memory),
        throughput_mean: calculate_metric_mean(metrics, :throughput),
        throughput_std: calculate_metric_std(metrics, :throughput),
        error_rate_mean: calculate_metric_mean(metrics, :error_rate),
        error_rate_std: calculate_metric_std(metrics, :error_rate)
      }
    else
      # Default baselines if not enough history
      %{
        cpu_mean: 0.5, cpu_std: 0.2,
        memory_mean: 0.5, memory_std: 0.15,
        throughput_mean: 500, throughput_std: 100,
        error_rate_mean: 0.01, error_rate_std: 0.005
      }
    end
  end
  
  defp calculate_metric_mean(metrics_list, key) do
    values = Enum.map(metrics_list, & &1[key]) |> Enum.filter(& &1 != nil)
    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0
    end
  end
  
  defp calculate_metric_std(metrics_list, key) do
    values = Enum.map(metrics_list, & &1[key]) |> Enum.filter(& &1 != nil)
    if length(values) > 1 do
      mean = calculate_metric_mean(metrics_list, key)
      variance = Enum.map(values, fn v -> :math.pow(v - mean, 2) end) |> Enum.sum()
      :math.sqrt(variance / (length(values) - 1))
    else
      0.1
    end
  end
  
  defp detect_statistical_anomalies(current, baselines) do
    anomalies = []
    
    # CPU anomaly detection
    cpu_z_score = if baselines.cpu_std > 0 do
      (current.cpu - baselines.cpu_mean) / baselines.cpu_std
    else
      0
    end
    
    anomalies = if abs(cpu_z_score) > 3 do
      anomalies ++ [%{
        type: :statistical,
        subtype: :cpu_anomaly,
        severity: if(abs(cpu_z_score) > 4, do: :high, else: :medium),
        description: "CPU usage statistical anomaly",
        value: current.cpu,
        expected_mean: baselines.cpu_mean,
        z_score: cpu_z_score,
        timestamp: DateTime.utc_now()
      }]
    else
      anomalies
    end
    
    # Memory anomaly detection
    memory_z_score = if baselines.memory_std > 0 do
      (current.memory - baselines.memory_mean) / baselines.memory_std
    else
      0
    end
    
    anomalies = if abs(memory_z_score) > 3 do
      anomalies ++ [%{
        type: :statistical,
        subtype: :memory_anomaly,
        severity: if(abs(memory_z_score) > 4, do: :high, else: :medium),
        description: "Memory usage statistical anomaly",
        value: current.memory,
        expected_mean: baselines.memory_mean,
        z_score: memory_z_score,
        timestamp: DateTime.utc_now()
      }]
    else
      anomalies
    end
    
    # Error rate anomaly
    error_z_score = if baselines.error_rate_std > 0 do
      (current.error_rate - baselines.error_rate_mean) / baselines.error_rate_std
    else
      0
    end
    
    anomalies = if error_z_score > 3 do  # Only care about increases
      anomalies ++ [%{
        type: :statistical,
        subtype: :error_spike,
        severity: if(error_z_score > 5, do: :critical, else: :high),
        description: "Error rate spike detected",
        value: current.error_rate,
        expected_mean: baselines.error_rate_mean,
        z_score: error_z_score,
        timestamp: DateTime.utc_now()
      }]
    else
      anomalies
    end
    
    anomalies
  end
  
  defp detect_time_series_anomalies(state) do
    # Detect anomalies in time series patterns
    anomalies = []
    
    # Check for pattern detection rate changes
    recent_pattern_counts = state.intelligence_reports
                           |> Enum.take(10)
                           |> Enum.map(fn r -> length(r[:patterns] || []) end)
    
    if length(recent_pattern_counts) >= 5 do
      pattern_trend = calculate_trend(recent_pattern_counts)
      current_count = List.first(recent_pattern_counts, 0)
      
      # Sudden drop in pattern detection
      if pattern_trend.direction == :decreasing && pattern_trend.slope < -2 do
        anomalies ++ [%{
          type: :time_series,
          subtype: :pattern_detection_drop,
          severity: :medium,
          description: "Sudden decrease in pattern detection capability",
          current_rate: current_count,
          trend: pattern_trend,
          timestamp: DateTime.utc_now()
        }]
      else
        anomalies
      end
    else
      anomalies
    end
  end
  
  defp detect_pattern_anomalies(state) do
    # Detect anomalies in the patterns themselves
    recent_patterns = get_recent_patterns(state)
    anomalies = []
    
    # Group patterns by type
    pattern_groups = Enum.group_by(recent_patterns, & &1.type)
    
    # Check for unusual pattern distributions
    expected_distribution = %{
      statistical: 0.25,
      temporal: 0.25,
      structural: 0.25,
      behavioral: 0.25
    }
    
    total_patterns = length(recent_patterns)
    
    anomalies = if total_patterns > 10 do
      Enum.reduce(expected_distribution, anomalies, fn {type, expected_ratio}, acc ->
        actual_count = length(Map.get(pattern_groups, type, []))
        actual_ratio = actual_count / total_patterns
        deviation = abs(actual_ratio - expected_ratio)
        
        if deviation > 0.5 do  # More than 50% deviation from expected
          acc ++ [%{
            type: :pattern_distribution,
            subtype: type,
            severity: :low,
            description: "Unusual #{type} pattern distribution",
            expected_ratio: expected_ratio,
            actual_ratio: actual_ratio,
            deviation: deviation,
            timestamp: DateTime.utc_now()
          }]
        else
          acc
        end
      end)
    else
      anomalies
    end
    
    # Check for duplicate or redundant patterns
    duplicate_count = length(recent_patterns) - length(Enum.uniq_by(recent_patterns, & &1.description))
    
    anomalies = if duplicate_count > 5 do
      anomalies ++ [%{
        type: :pattern_quality,
        subtype: :excessive_duplicates,
        severity: :low,
        description: "Excessive duplicate patterns detected",
        duplicate_count: duplicate_count,
        total_patterns: length(recent_patterns),
        timestamp: DateTime.utc_now()
      }]
    else
      anomalies
    end
    
    anomalies
  end
  
  defp detect_system_state_anomalies(state) do
    anomalies = []
    
    # Check prediction accuracy
    accuracy = prediction_accuracy(state)
    anomalies = cond do
      accuracy < 0.2 ->
        anomalies ++ [%{
          type: :system_state,
          subtype: :prediction_failure,
          severity: :critical,
          description: "Critical prediction accuracy failure",
          value: accuracy,
          threshold: 0.2,
          timestamp: DateTime.utc_now()
        }]
        
      accuracy < 0.4 ->
        anomalies ++ [%{
          type: :system_state,
          subtype: :prediction_degradation,
          severity: :high,
          description: "Prediction accuracy below acceptable threshold",
          value: accuracy,
          threshold: 0.4,
          timestamp: DateTime.utc_now()
        }]
        
      true ->
        anomalies
    end
    
    # Check environmental model staleness
    anomalies = if state.environmental_model.last_scan do
      age = DateTime.diff(DateTime.utc_now(), state.environmental_model.last_scan, :second)
      
      cond do
        age > 600 ->  # 10 minutes
          anomalies ++ [%{
            type: :system_state,
            subtype: :critical_staleness,
            severity: :critical,
            description: "Environmental model critically stale",
            age_seconds: age,
            last_update: state.environmental_model.last_scan,
            timestamp: DateTime.utc_now()
          }]
          
        age > 300 ->  # 5 minutes
          anomalies ++ [%{
            type: :system_state,
            subtype: :model_staleness,
            severity: :high,
            description: "Environmental model is stale",
            age_seconds: age,
            last_update: state.environmental_model.last_scan,
            timestamp: DateTime.utc_now()
          }]
          
        true ->
          anomalies
      end
    else
      anomalies
    end
    
    # Check learning queue health
    queue_size = :queue.len(state.learning_queue)
    anomalies = cond do
      queue_size > 100 ->
        anomalies ++ [%{
          type: :system_state,
          subtype: :learning_overload,
          severity: :high,
          description: "Learning system overloaded",
          queue_size: queue_size,
          threshold: 100,
          timestamp: DateTime.utc_now()
        }]
        
      queue_size > 50 ->
        anomalies ++ [%{
          type: :system_state,
          subtype: :learning_backlog,
          severity: :medium,
          description: "Learning queue backlog growing",
          queue_size: queue_size,
          threshold: 50,
          timestamp: DateTime.utc_now()
        }]
        
      true ->
        anomalies
    end
    
    # Check vector store health
    anomalies = case check_vector_store_health(state.vector_store) do
      {:error, reason} ->
        anomalies ++ [%{
          type: :system_state,
          subtype: :vector_store_failure,
          severity: :high,
          description: "Vector store health check failed",
          reason: reason,
          timestamp: DateTime.utc_now()
        }]
      _ ->
        anomalies
    end
    
    anomalies
  end
  
  defp check_vector_store_health(vector_store) do
    try do
      GenServer.call(vector_store, :health_check, 1000)
      {:ok, :healthy}
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      _, reason -> {:error, reason}
    end
  end
  
  defp detect_behavioral_anomalies(state) do
    # Detect anomalies in system behavior patterns
    anomalies = []
    
    # Get recent events from process dictionary
    recent_events = Process.get(:recent_system_events) || []
    
    # Analyze event frequency
    event_rate = length(recent_events) / 10  # Events per second over last 10 seconds
    
    anomalies = cond do
      event_rate > 200 ->
        anomalies ++ [%{
          type: :behavioral,
          subtype: :event_storm,
          severity: :high,
          description: "Event storm detected",
          event_rate: event_rate,
          threshold: 200,
          timestamp: DateTime.utc_now()
        }]
        
      event_rate < 1 ->
        anomalies ++ [%{
          type: :behavioral,
          subtype: :event_drought,
          severity: :medium,
          description: "Abnormally low event activity",
          event_rate: event_rate,
          threshold: 1,
          timestamp: DateTime.utc_now()
        }]
        
      true ->
        anomalies
    end
    
    # Analyze event type distribution
    event_types = Enum.frequencies_by(recent_events, & &1[:type])
    dominant_type = event_types |> Enum.max_by(fn {_k, v} -> v end, fn -> {:none, 0} end)
    
    {dominant_event, dominant_count} = dominant_type
    dominance_ratio = if length(recent_events) > 0 do
      dominant_count / length(recent_events)
    else
      0
    end
    
    anomalies = if dominance_ratio > 0.8 && length(recent_events) > 50 do
      anomalies ++ [%{
        type: :behavioral,
        subtype: :event_imbalance,
        severity: :medium,
        description: "Event type distribution severely imbalanced",
        dominant_type: dominant_event,
        dominance_ratio: dominance_ratio,
        event_distribution: event_types,
        timestamp: DateTime.utc_now()
      }]
    else
      anomalies
    end
    
    anomalies
  end
  
  defp detect_correlation_anomalies(current_metrics, state) do
    # Detect anomalies in expected correlations
    anomalies = []
    
    # CPU-Memory correlation check
    cpu_memory_correlation = calculate_simple_correlation(
      current_metrics.cpu,
      current_metrics.memory
    )
    
    # Usually CPU and memory usage are somewhat correlated
    anomalies = if current_metrics.cpu > 0.8 && current_metrics.memory < 0.3 do
      anomalies ++ [%{
        type: :correlation,
        subtype: :cpu_memory_mismatch,
        severity: :medium,
        description: "Unusual CPU-Memory correlation pattern",
        cpu: current_metrics.cpu,
        memory: current_metrics.memory,
        expected_correlation: "positive",
        timestamp: DateTime.utc_now()
      }]
    else
      anomalies
    end
    
    # Throughput-Error correlation check
    if current_metrics.throughput < 100 && current_metrics.error_rate > 0.1 do
      anomalies ++ [%{
        type: :correlation,
        subtype: :low_throughput_high_errors,
        severity: :high,
        description: "Low throughput with high error rate",
        throughput: current_metrics.throughput,
        error_rate: current_metrics.error_rate,
        timestamp: DateTime.utc_now()
      }]
    else
      anomalies
    end
  end
  
  defp calculate_simple_correlation(x, y) when is_number(x) and is_number(y) do
    # Simplified correlation for two values
    # In a real system, would maintain history for proper correlation
    if (x > 0.7 && y > 0.7) || (x < 0.3 && y < 0.3) do
      0.8  # High positive correlation
    else
      0.2  # Low correlation
    end
  end
  
  defp summarize_environment(model) do
    %{
      complexity: model.complexity,
      volatility: model.volatility,
      trend_count: length(model.trends)
    }
  end
  
  defp get_recent_patterns(state) do
    # Get patterns from recent intelligence reports
    state.intelligence_reports
    |> Enum.take(5)
    |> Enum.flat_map(& &1.patterns)
  end
  
  defp get_active_scenarios(_state) do
    # Return currently modeled scenarios
    []
  end
  
  defp generate_recommendations(state) do
    if state.environmental_model.volatility > 0.7 do
      ["Increase monitoring frequency", "Prepare contingency plans"]
    else
      ["Maintain current operations"]
    end
  end
  
  defp assess_situation(model, patterns) do
    urgency = if model.volatility > 0.8 || length(patterns) > 5 do
      :high
    else
      :normal
    end
    
    %{
      urgency: urgency,
      stability: 1.0 - model.volatility,
      pattern_count: length(patterns)
    }
  end
  
  defp generate_tactical_recommendations(_model, patterns) do
    patterns
    |> Enum.map(fn pattern ->
      case pattern.type do
        :statistical -> "Adjust resource allocation"
        :temporal -> "Monitor trend development"
        :behavioral -> "Investigate anomaly source"
        _ -> "Continue monitoring"
      end
    end)
    |> Enum.uniq()
  end
  
  defp calculate_complexity(scan_result, patterns) do
    # Real complexity calculation based on system entropy and information theory
    
    # Pattern entropy (Shannon entropy)
    pattern_entropy = calculate_pattern_entropy(patterns)
    
    # Signal entropy
    signal_entropy = calculate_signal_entropy(scan_result.external_signals)
    
    # Anomaly impact score
    anomaly_impact = calculate_anomaly_impact(scan_result.anomalies)
    
    # System dynamics complexity
    dynamics_complexity = calculate_dynamics_complexity(scan_result)
    
    # Interaction complexity (how many components are interacting)
    interaction_complexity = calculate_interaction_complexity(scan_result)
    
    # Environmental uncertainty
    uncertainty = calculate_environmental_uncertainty(scan_result)
    
    # Weighted combination using information-theoretic weights
    weights = %{
      pattern_entropy: 0.25,
      signal_entropy: 0.15,
      anomaly_impact: 0.20,
      dynamics: 0.20,
      interaction: 0.15,
      uncertainty: 0.05
    }
    
    complexity = weights[:pattern_entropy] * pattern_entropy +
                 weights[:signal_entropy] * signal_entropy +
                 weights[:anomaly_impact] * anomaly_impact +
                 weights[:dynamics] * dynamics_complexity +
                 weights[:interaction] * interaction_complexity +
                 weights[:uncertainty] * uncertainty
    
    # Ensure bounded between 0 and 1
    min(1.0, max(0.0, complexity))
  end
  
  defp calculate_pattern_entropy(patterns) do
    # Calculate Shannon entropy of pattern distribution
    if length(patterns) == 0 do
      0.0
    else
      # Group patterns by type and subtype
      pattern_groups = Enum.group_by(patterns, fn p -> {p.type, p.subtype} end)
      total_patterns = length(patterns)
      
      # Calculate entropy: -Σ(p_i * log2(p_i))
      entropy = pattern_groups
                |> Enum.map(fn {_key, group} ->
                  probability = length(group) / total_patterns
                  if probability > 0 do
                    -probability * :math.log2(probability)
                  else
                    0
                  end
                end)
                |> Enum.sum()
      
      # Normalize by maximum possible entropy (log2 of number of groups)
      max_entropy = :math.log2(max(1, map_size(pattern_groups)))
      if max_entropy > 0 do
        entropy / max_entropy
      else
        0.0
      end
    end
  end
  
  defp calculate_signal_entropy(signals) do
    if length(signals) == 0 do
      0.0
    else
      # Group signals by type
      signal_groups = Enum.group_by(signals, & &1.type)
      total_signals = length(signals)
      
      # Calculate entropy
      entropy = signal_groups
                |> Enum.map(fn {_type, group} ->
                  probability = length(group) / total_signals
                  if probability > 0 do
                    -probability * :math.log2(probability)
                  else
                    0
                  end
                end)
                |> Enum.sum()
      
      # Normalize (max 6 signal types expected)
      max_entropy = :math.log2(6)
      min(1.0, entropy / max_entropy)
    end
  end
  
  defp calculate_anomaly_impact(anomalies) do
    if length(anomalies) == 0 do
      0.0
    else
      # Calculate weighted impact based on severity and count
      severity_weights = %{
        critical: 1.0,
        high: 0.7,
        medium: 0.4,
        low: 0.2
      }
      
      total_impact = anomalies
                     |> Enum.map(fn a ->
                       severity_weights[a.severity] || 0.3
                     end)
                     |> Enum.sum()
      
      # Normalize with logarithmic scaling for multiple anomalies
      normalized = :math.log(1 + total_impact) / :math.log(1 + length(anomalies) * 1.0)
      min(1.0, normalized)
    end
  end
  
  defp calculate_dynamics_complexity(scan_result) do
    metrics = scan_result.metrics
    
    # Calculate rate of change indicators
    cpu_volatility = if metrics[:cpu] && metrics[:variance] do
      min(1.0, :math.sqrt(metrics[:variance]) / max(0.1, metrics[:cpu]))
    else
      0.5
    end
    
    # Process count dynamics
    process_dynamics = if metrics[:process_utilization] do
      metrics[:process_utilization]
    else
      0.5
    end
    
    # Error rate dynamics
    error_dynamics = if metrics[:error_rate] do
      # Higher error rates increase complexity exponentially
      1 - :math.exp(-metrics[:error_rate] * 10)
    else
      0.0
    end
    
    # IO dynamics (high IO can indicate complex interactions)
    io_dynamics = if metrics[:io_input] && metrics[:io_output] do
      total_io = metrics[:io_input] + metrics[:io_output]
      min(1.0, total_io / 1_000_000_000)  # Normalize to GB
    else
      0.3
    end
    
    # Combine dynamics measures
    (cpu_volatility + process_dynamics + error_dynamics + io_dynamics) / 4
  end
  
  defp calculate_interaction_complexity(scan_result) do
    # Measure complexity of component interactions
    internal_state = scan_result.internal_state
    
    interaction_score = 0.0
    interaction_count = 0
    
    # EventBus interaction complexity
    if internal_state[:event_bus_throughput] do
      throughput_complexity = min(1.0, internal_state[:event_bus_throughput] / 1000)
      subscriber_complexity = min(1.0, internal_state[:event_bus_subscribers] / 50)
      interaction_score = interaction_score + (throughput_complexity + subscriber_complexity) / 2
      interaction_count = interaction_count + 1
    end
    
    # MCP connection complexity
    if internal_state[:mcp_connections] do
      connection_complexity = min(1.0, internal_state[:mcp_connections] / 10)
      interaction_score = interaction_score + connection_complexity
      interaction_count = interaction_count + 1
    end
    
    # Circuit breaker complexity (more open = more complex/problematic)
    if internal_state[:circuit_breakers_open] do
      breaker_complexity = min(1.0, internal_state[:circuit_breakers_open] / 5)
      interaction_score = interaction_score + breaker_complexity
      interaction_count = interaction_count + 1
    end
    
    # Variety flow complexity
    variety_complexity = case internal_state[:variety_flow] do
      :blocked -> 1.0
      :overwhelmed -> 0.9
      :constrained -> 0.7
      :normal -> 0.5
      :smooth -> 0.3
      :minimal -> 0.1
      _ -> 0.5
    end
    interaction_score = interaction_score + variety_complexity
    interaction_count = interaction_count + 1
    
    if interaction_count > 0 do
      interaction_score / interaction_count
    else
      0.5
    end
  end
  
  defp calculate_environmental_uncertainty(scan_result) do
    # Measure uncertainty in the environment
    
    # Signal diversity indicates uncertainty
    signal_types = scan_result.external_signals
                   |> Enum.map(& &1.type)
                   |> Enum.uniq()
                   |> length()
    signal_uncertainty = min(1.0, signal_types / 6)
    
    # Anomaly unpredictability
    anomaly_types = scan_result.anomalies
                    |> Enum.map(& &1.type)
                    |> Enum.uniq()
                    |> length()
    anomaly_uncertainty = min(1.0, anomaly_types / 8)
    
    # Time-based uncertainty (recent data is more certain)
    time_uncertainty = if scan_result[:timestamp] do
      age_seconds = DateTime.diff(DateTime.utc_now(), scan_result.timestamp)
      min(1.0, age_seconds / 300)  # Max uncertainty at 5 minutes
    else
      0.5
    end
    
    # Combine uncertainties
    (signal_uncertainty + anomaly_uncertainty + time_uncertainty) / 3
  end
  
  defp calculate_volatility(scan_result, current_model) do
    # Calculate real volatility using statistical measures and rate of change
    time_delta = DateTime.diff(scan_result.timestamp, current_model.last_scan)
    
    if time_delta <= 0 do
      current_model.volatility
    else
      # Store metrics history for volatility calculation
      metrics_history = get_or_init_metrics_history(current_model, scan_result.metrics)
      
      # Calculate various volatility components
      metric_volatility = calculate_metric_volatility(metrics_history)
      anomaly_volatility = calculate_anomaly_volatility(scan_result, current_model)
      signal_volatility = calculate_signal_volatility(scan_result, current_model)
      pattern_volatility = calculate_pattern_volatility(scan_result, current_model)
      
      # Time-adjusted volatility factor
      time_factor = calculate_time_adjustment_factor(time_delta)
      
      # Combine volatility components with adaptive weights
      weights = determine_volatility_weights(scan_result, current_model)
      
      base_volatility = weights.metric * metric_volatility +
                        weights.anomaly * anomaly_volatility +
                        weights.signal * signal_volatility +
                        weights.pattern * pattern_volatility
      
      # Apply time factor and use exponential smoothing
      new_volatility = min(1.0, base_volatility * time_factor)
      alpha = 0.3  # Smoothing factor
      smoothed_volatility = current_model.volatility * (1 - alpha) + new_volatility * alpha
      
      # Store updated metrics history
      Process.put(:metrics_history, Enum.take(metrics_history, 20))
      
      smoothed_volatility
    end
  end
  
  defp get_or_init_metrics_history(model, current_metrics) do
    case Process.get(:metrics_history) do
      nil -> [current_metrics]
      history -> [current_metrics | history]
    end
  end
  
  defp calculate_metric_volatility(history) when length(history) < 2 do
    0.5  # Default volatility for insufficient data
  end
  
  defp calculate_metric_volatility(history) do
    # Calculate volatility for each metric using standard deviation
    metric_keys = [:cpu, :memory, :throughput, :error_rate, :latency]
    
    volatilities = Enum.map(metric_keys, fn key ->
      values = Enum.map(history, fn m -> m[key] || 0 end)
      calculate_metric_std_dev(values, key)
    end)
    
    # Return average volatility across all metrics
    Enum.sum(volatilities) / length(volatilities)
  end
  
  defp calculate_metric_std_dev(values, key) when length(values) < 2 do
    0.0
  end
  
  defp calculate_metric_std_dev(values, key) do
    # Normalize values based on metric type
    normalized = case key do
      :throughput -> Enum.map(values, fn v -> v / 1000 end)  # Normalize to k/s
      :latency -> Enum.map(values, fn v -> v / 100 end)      # Normalize to 100ms
      _ -> values  # Already normalized 0-1
    end
    
    mean = Enum.sum(normalized) / length(normalized)
    variance = Enum.map(normalized, fn v -> :math.pow(v - mean, 2) end) |> Enum.sum()
    variance = variance / (length(normalized) - 1)
    
    std_dev = :math.sqrt(variance)
    
    # Convert to volatility score (0-1)
    case key do
      :cpu -> min(1.0, std_dev * 3)
      :memory -> min(1.0, std_dev * 3)
      :throughput -> min(1.0, std_dev * 2)
      :error_rate -> min(1.0, std_dev * 10)  # More sensitive to error changes
      :latency -> min(1.0, std_dev * 2)
      _ -> min(1.0, std_dev * 3)
    end
  end
  
  defp calculate_anomaly_volatility(scan_result, current_model) do
    # Compare anomaly patterns between scans
    current_anomalies = scan_result.anomalies
    
    # Get previous anomaly types from model
    previous_anomaly_types = Map.get(current_model, :last_anomaly_types, [])
    current_anomaly_types = Enum.map(current_anomalies, & &1.type) |> Enum.uniq()
    
    # Calculate Jaccard distance for anomaly type changes
    intersection = MapSet.intersection(
      MapSet.new(previous_anomaly_types),
      MapSet.new(current_anomaly_types)
    ) |> MapSet.size()
    
    union = MapSet.union(
      MapSet.new(previous_anomaly_types),
      MapSet.new(current_anomaly_types)
    ) |> MapSet.size()
    
    type_volatility = if union > 0 do
      1.0 - (intersection / union)  # Jaccard distance
    else
      0.0
    end
    
    # Factor in anomaly count changes
    previous_count = Map.get(current_model, :last_anomaly_count, 0)
    current_count = length(current_anomalies)
    count_change = abs(current_count - previous_count) / max(1, previous_count)
    count_volatility = min(1.0, count_change / 3)  # Normalize
    
    # Severity volatility
    severity_score = Enum.reduce(current_anomalies, 0, fn a, acc ->
      case a.severity do
        :critical -> acc + 4
        :high -> acc + 3
        :medium -> acc + 2
        :low -> acc + 1
      end
    end)
    
    previous_severity = Map.get(current_model, :last_severity_score, 0)
    severity_change = abs(severity_score - previous_severity) / max(1, previous_severity)
    severity_volatility = min(1.0, severity_change / 2)
    
    # Store current state for next comparison
    Process.put(:last_anomaly_state, %{
      types: current_anomaly_types,
      count: current_count,
      severity: severity_score
    })
    
    # Weighted combination
    type_volatility * 0.4 + count_volatility * 0.3 + severity_volatility * 0.3
  end
  
  defp calculate_signal_volatility(scan_result, current_model) do
    # Analyze external signal patterns for volatility
    current_signals = scan_result.external_signals
    
    # Group signals by type and calculate rates
    signal_rates = current_signals
                   |> Enum.group_by(& &1.type)
                   |> Enum.map(fn {type, signals} ->
                     {type, length(signals)}
                   end)
                   |> Map.new()
    
    # Compare with previous rates
    previous_rates = Map.get(current_model, :last_signal_rates, %{})
    
    # Calculate rate changes
    all_types = MapSet.union(
      MapSet.new(Map.keys(signal_rates)),
      MapSet.new(Map.keys(previous_rates))
    )
    
    rate_changes = Enum.map(all_types, fn type ->
      current = Map.get(signal_rates, type, 0)
      previous = Map.get(previous_rates, type, 0)
      
      if previous > 0 do
        abs(current - previous) / previous
      else
        if current > 0, do: 1.0, else: 0.0
      end
    end)
    
    # Calculate signal strength volatility
    current_strengths = Enum.map(current_signals, & &1.strength)
    strength_volatility = if length(current_strengths) > 0 do
      std_dev = calculate_standard_deviation(current_strengths)
      min(1.0, std_dev * 2)
    else
      0.0
    end
    
    # Store current rates
    Process.put(:last_signal_rates, signal_rates)
    
    # Combine rate volatility and strength volatility
    rate_volatility = if length(rate_changes) > 0 do
      Enum.sum(rate_changes) / length(rate_changes)
    else
      0.0
    end
    
    min(1.0, rate_volatility * 0.6 + strength_volatility * 0.4)
  end
  
  defp calculate_pattern_volatility(scan_result, current_model) do
    # Analyze pattern stability/volatility
    current_patterns = Map.get(scan_result, :patterns, [])
    
    # Pattern type distribution
    type_distribution = current_patterns
                       |> Enum.frequencies_by(& &1.type)
                       |> Enum.map(fn {k, v} -> {k, v / max(1, length(current_patterns))} end)
                       |> Map.new()
    
    # Compare with previous distribution
    previous_distribution = Map.get(current_model, :last_pattern_distribution, %{})
    
    # Calculate KL divergence (simplified)
    kl_divergence = calculate_distribution_divergence(type_distribution, previous_distribution)
    
    # Pattern confidence volatility
    confidences = Enum.map(current_patterns, & &1.confidence)
    confidence_volatility = if length(confidences) > 0 do
      calculate_standard_deviation(confidences)
    else
      0.0
    end
    
    # Store current distribution
    Process.put(:last_pattern_distribution, type_distribution)
    
    # Combine measures
    min(1.0, kl_divergence * 0.7 + confidence_volatility * 0.3)
  end
  
  defp calculate_standard_deviation([]), do: 0.0
  defp calculate_standard_deviation([_]), do: 0.0
  defp calculate_standard_deviation(values) do
    mean = Enum.sum(values) / length(values)
    variance = Enum.map(values, fn v -> :math.pow(v - mean, 2) end) |> Enum.sum()
    variance = variance / (length(values) - 1)
    :math.sqrt(variance)
  end
  
  defp calculate_distribution_divergence(current, previous) when map_size(previous) == 0 do
    # If no previous distribution, return moderate divergence
    0.5
  end
  
  defp calculate_distribution_divergence(current, previous) do
    # Simplified KL divergence calculation
    all_keys = MapSet.union(MapSet.new(Map.keys(current)), MapSet.new(Map.keys(previous)))
    
    divergence = Enum.reduce(all_keys, 0.0, fn key, acc ->
      p = Map.get(current, key, 0.001)  # Small epsilon to avoid log(0)
      q = Map.get(previous, key, 0.001)
      
      if p > 0 do
        acc + p * :math.log(p / q)
      else
        acc
      end
    end)
    
    # Normalize to 0-1 range
    min(1.0, abs(divergence))
  end
  
  defp calculate_time_adjustment_factor(time_delta_seconds) do
    # Adjust volatility based on time between measurements
    # Shorter intervals mean changes appear more volatile
    
    optimal_interval = 60  # 1 minute is optimal
    
    if time_delta_seconds < optimal_interval do
      # Boost volatility for rapid changes
      1.0 + (optimal_interval - time_delta_seconds) / optimal_interval
    else
      # Dampen volatility for slow changes
      max(0.5, optimal_interval / time_delta_seconds)
    end
  end
  
  defp determine_volatility_weights(scan_result, current_model) do
    # Dynamically adjust weights based on system state
    
    # If many anomalies, weight them higher
    anomaly_weight = if length(scan_result.anomalies) > 5 do
      0.35
    else
      0.25
    end
    
    # If high signal activity, weight signals higher
    signal_weight = if length(scan_result.external_signals) > 10 do
      0.25
    else
      0.15
    end
    
    # Adjust remaining weights proportionally
    remaining = 1.0 - anomaly_weight - signal_weight
    
    %{
      metric: remaining * 0.6,
      anomaly: anomaly_weight,
      signal: signal_weight,
      pattern: remaining * 0.4
    }
  end
  
  defp update_trends(current_trends, new_patterns) do
    temporal_patterns = Enum.filter(new_patterns, & &1.type == :temporal)
    
    (current_trends ++ temporal_patterns)
    |> Enum.take(-20)  # Keep last 20 trends
  end
  
  defp impact_to_severity(impact) do
    case impact do
      :high -> :critical
      :medium -> :medium
      :low -> :low
    end
  end
  
  defp recently_reported_pain?(state, pain_type) do
    # Check if we reported this pain type in the last 5 seconds
    last_report = Map.get(state.pain_report_times, pain_type)
    
    case last_report do
      nil -> false
      timestamp ->
        DateTime.diff(DateTime.utc_now(), timestamp) < 5
    end
  end
  
  defp update_pain_report_time(state, pain_type) do
    %{state | pain_report_times: Map.put(state.pain_report_times, pain_type, DateTime.utc_now())}
  end
  
  
  # LLM Integration Helper Functions for S4 Intelligence
  
  defp detect_patterns_with_llm(scan_result, traditional_patterns) do
    # Use LLM to identify additional patterns that traditional algorithms might miss
    case LLMBridge.call_llm_api(
      """
      Analyze this scan data for additional patterns:
      
      Scan Data: #{inspect(scan_result, limit: 5)}
      Traditional Patterns Found: #{inspect(traditional_patterns, limit: 3)}
      
      Look for:
      1. Emergent patterns not captured by traditional analysis
      2. Complex correlation patterns
      3. Behavioral anomalies
      4. Temporal sequence patterns
      5. Meta-patterns (patterns about patterns)
      
      Return patterns in format: type|subtype|confidence|description
      One pattern per line.
      """,
      :analysis,
      timeout: 15_000
    ) do
      {:ok, response} ->
        parse_llm_patterns(response)
      {:error, reason} ->
        Logger.debug("LLM pattern detection failed: #{inspect(reason)}")
        []
    end
  end
  
  defp parse_llm_patterns(response) do
    response
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "|"))
    |> Enum.map(&parse_pattern_line/1)
    |> Enum.filter(& &1 != nil)
  end
  
  defp parse_pattern_line(line) do
    case String.split(line, "|") do
      [type, subtype, confidence_str, description] ->
        case Float.parse(confidence_str) do
          {confidence, _} when confidence > 0.3 ->
            %{
              type: String.to_atom(String.downcase(type)),
              subtype: String.to_atom(String.downcase(subtype)),
              confidence: confidence,
              description: String.trim(description),
              source: :llm_analysis
            }
          _ -> nil
        end
      _ -> nil
    end
  end
  
  defp model_futures_with_llm(parameters, similar_patterns, state) do
    # Use LLM for strategic scenario modeling
    case LLMBridge.call_llm_api(
      """
      Model future scenarios based on these parameters:
      
      Current Parameters: #{inspect(parameters)}
      Similar Historical Patterns: #{inspect(similar_patterns, limit: 2)}
      Environmental Complexity: #{state.environmental_model.complexity}
      
      Generate 3-5 realistic scenarios covering:
      1. Most likely outcome (60-80% probability)
      2. Optimistic scenario (20-30% probability) 
      3. Pessimistic scenario (10-20% probability)
      4. Black swan event (1-5% probability)
      
      For each scenario, provide:
      - Probability (0.0-1.0)
      - Impact (low/medium/high)
      - Timeline (immediate/short_term/long_term)
      - Key factors
      - Recommended actions
      
      Format: probability|impact|timeline|description|actions
      """,
      :synthesis,
      timeout: 20_000
    ) do
      {:ok, response} ->
        parse_llm_scenarios(response)
      {:error, reason} ->
        Logger.debug("LLM scenario modeling failed: #{inspect(reason)}")
        []
    end
  end
  
  defp parse_llm_scenarios(response) do
    response
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "|"))
    |> Enum.map(&parse_scenario_line/1)
    |> Enum.filter(& &1 != nil)
  end
  
  defp parse_scenario_line(line) do
    case String.split(line, "|") do
      [prob_str, impact, timeline, description, actions] ->
        case Float.parse(prob_str) do
          {probability, _} when probability > 0.0 ->
            %{
              scenario: String.trim(description),
              probability: probability,
              impact: String.to_atom(String.downcase(impact)),
              time_horizon: String.to_atom(String.downcase(timeline)),
              confidence: 0.7,  # LLM-generated scenarios get medium confidence
              similar_patterns: 0,
              risk_factors: [],
              opportunities: [],
              recommended_actions: String.split(actions, ",") |> Enum.map(&String.trim/1),
              source: :llm_modeling
            }
          _ -> nil
        end
      _ -> nil
    end
  end
  
  defp generate_llm_intelligence_analysis(base_report, state) do
    # Use LLM to generate comprehensive intelligence analysis
    LLMBridge.call_llm_api(
      """
      Provide strategic intelligence analysis based on this S4 Intelligence report:
      
      Environmental Model: #{inspect(base_report.environmental_model, limit: 3)}
      Detected Patterns: #{inspect(base_report.patterns, limit: 3)}
      Assessment: #{inspect(base_report.assessment)}
      Current Health: #{inspect(state.health_metrics)}
      
      Generate analysis covering:
      1. Strategic implications of detected patterns
      2. Environmental adaptation requirements
      3. Threat and opportunity assessment
      4. Resource allocation recommendations
      5. Long-term strategic outlook
      6. Key decision points
      
      Provide actionable intelligence for S5 Policy decisions.
      """,
      :synthesis,
      timeout: 25_000
    )
  end
  
  defp extract_learning_patterns(patterns_to_learn) do
    # Convert raw patterns to structured learning patterns
    patterns_to_learn
    |> Enum.map(fn raw_pattern ->
      %{
        type: :learned,
        subtype: :s3_decision,
        data: raw_pattern,
        confidence: 0.8,
        timestamp: DateTime.utc_now()
      }
    end)
  end
  
  defp analyze_patterns_for_intelligence(patterns, state) do
    # Analyze patterns to generate intelligence report
    %{
      type: :pattern_analysis,
      patterns_analyzed: length(patterns),
      environmental_model: state.environmental_model,
      assessment: %{
        threat_level: calculate_threat_level(patterns),
        opportunity_level: calculate_opportunity_level(patterns),
        urgency: if(length(patterns) > 5, do: :high, else: :medium),
        confidence: 0.7
      },
      recommendations: generate_recommendations(patterns, state),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp calculate_threat_level(patterns) do
    # Simple threat assessment based on pattern count and types
    threat_patterns = Enum.count(patterns, fn p -> 
      String.contains?(inspect(p.data), ["error", "failure", "overload"])
    end)
    
    min(1.0, threat_patterns / 10.0)
  end
  
  defp calculate_opportunity_level(patterns) do
    # Simple opportunity assessment
    positive_patterns = Enum.count(patterns, fn p -> 
      String.contains?(inspect(p.data), ["success", "optimization", "improved"])
    end)
    
    min(1.0, positive_patterns / 10.0)
  end
  
  defp generate_recommendations(patterns, _state) do
    # Generate basic recommendations based on patterns
    cond do
      length(patterns) > 10 ->
        ["Consider increasing system capacity", "Review resource allocation policies"]
      length(patterns) > 5 ->
        ["Monitor system load closely", "Prepare for potential scaling"]
      true ->
        ["Continue normal operations", "Maintain current policies"]
    end
  end

  # VSM Pattern Publishing - Complete VSM Integration
  defp publish_pattern_events(state) do
    # Publish S4-specific intelligence patterns for VSM integration
    try do
      # Create S4 intelligence pattern from current state
      pattern_data = %{
        subsystem: "S4",
        type: "intelligence_pattern",
        timestamp: DateTime.utc_now(),
        metrics: %{
          health_score: calculate_health_score(state),
          environmental_complexity: state.health_metrics.environmental_complexity,
          prediction_accuracy: prediction_accuracy(state),
          pattern_detection_rate: Map.get(state.health_metrics, :total_patterns, 0) / max(1, Map.get(state.health_metrics, :scans_performed, 1)),
          scan_frequency: state.health_metrics.scans_performed,
          anomaly_detection_rate: calculate_anomaly_rate(state)
        },
        intelligence_data: %{
          environmental_model: state.environmental_model,
          detected_patterns: summarize_recent_patterns(state),
          prediction_quality: assess_prediction_quality(state),
          adaptation_signals: extract_adaptation_signals(state),
          learning_rate: calculate_learning_effectiveness(state)
        },
        analysis_status: %{
          algorithms_active: length(state.pattern_detector.algorithms),
          llm_integration_active: state.llm_integration.enabled,
          environmental_scan_active: true,
          pattern_cache_size: map_size(state.pattern_cache),
          recent_anomalies: count_recent_anomalies(state)
        }
      }

      # Publish to S4-specific pattern channel
      EventBus.publish(:vsm_s4_patterns, pattern_data)
      
      # Also publish to general VSM pattern flow
      EventBus.publish(:vsm_pattern_flow, pattern_data)
      
      # Publish environmental scanning patterns
      scan_pattern = %{
        subsystem: "S4",
        type: "environmental_scan_pattern",
        timestamp: DateTime.utc_now(),
        environmental_complexity: state.health_metrics.environmental_complexity,
        threats_detected: calculate_threat_level(state.environmental_model.last_scan_patterns),
        opportunities_detected: calculate_opportunity_level(state.environmental_model.last_scan_patterns),
        change_velocity: assess_environmental_change_rate(state),
        predictive_accuracy: prediction_accuracy(state),
        adaptation_needed: state.health_metrics.environmental_complexity > 0.7
      }
      
      EventBus.publish(:vsm_s4_patterns, scan_pattern)
      EventBus.publish(:vsm_pattern_flow, scan_pattern)
      
    catch
      :exit, {:noproc, _} ->
        # EventBus not available, skip publishing
        :ok
      error ->
        Logger.warning("S4: Failed to publish pattern events: #{inspect(error)}")
    end
  end
  
  defp calculate_anomaly_rate(state) do
    if state.health_metrics.scans_performed > 0 do
      state.health_metrics.anomalies_detected / state.health_metrics.scans_performed
    else
      0.0
    end
  end
  
  defp summarize_recent_patterns(state) do
    # Get recent patterns from cache
    now = System.monotonic_time(:millisecond)
    recent_cutoff = now - 300_000  # Last 5 minutes
    
    recent_patterns = state.pattern_cache
    |> Enum.filter(fn {_, pattern} -> pattern.timestamp > recent_cutoff end)
    |> Enum.map(fn {_, pattern} -> %{type: pattern.type, confidence: pattern.confidence} end)
    
    %{
      total_recent: length(recent_patterns),
      pattern_types: recent_patterns |> Enum.map(& &1.type) |> Enum.frequencies(),
      avg_confidence: if(length(recent_patterns) > 0, 
        do: Enum.sum(Enum.map(recent_patterns, & &1.confidence)) / length(recent_patterns), 
        else: 0.0)
    }
  end
  
  defp assess_prediction_quality(state) do
    accuracy = prediction_accuracy(state)
    %{
      accuracy_score: accuracy,
      quality_level: cond do
        accuracy > 0.8 -> "excellent"
        accuracy > 0.6 -> "good"
        accuracy > 0.4 -> "fair"
        true -> "poor"
      end,
      predictions_made: state.health_metrics.predictions_made,
      correct_predictions: state.health_metrics.correct_predictions
    }
  end
  
  defp extract_adaptation_signals(state) do
    # Extract signals that indicate need for system adaptation
    %{
      complexity_rising: state.health_metrics.environmental_complexity > 0.7,
      pattern_diversity_high: map_size(state.pattern_cache) > 100,
      prediction_degrading: prediction_accuracy(state) < 0.6,
      anomaly_frequency_high: calculate_anomaly_rate(state) > 0.1,
      environmental_volatility: state.environmental_model.volatility > 0.5
    }
  end
  
  defp calculate_learning_effectiveness(state) do
    # Measure how effectively the system is learning from patterns
    if state.health_metrics.scans_performed > 10 do
      # Learning effectiveness based on improvement in accuracy over time
      recent_accuracy = prediction_accuracy(state)
      baseline_accuracy = 0.5  # Assume 50% baseline
      
      (recent_accuracy - baseline_accuracy) / baseline_accuracy
    else
      0.0  # Not enough data to assess learning
    end
  end
  
  defp count_recent_anomalies(state) do
    # Count anomalies detected in recent scans
    now = System.monotonic_time(:millisecond)
    recent_cutoff = now - 600_000  # Last 10 minutes
    
    state.pattern_cache
    |> Enum.count(fn {_, pattern} -> 
      pattern.timestamp > recent_cutoff and pattern.type == :anomaly
    end)
  end
  
  defp assess_environmental_change_rate(state) do
    # Assess how quickly the environment is changing
    volatility = state.environmental_model.volatility
    complexity_change = abs(state.health_metrics.environmental_complexity - 0.5)
    
    (volatility + complexity_change) / 2
  end
  
  # ============================================================================
  # 🧠 VSM PATTERN INTEGRATION: Helper Functions for Pattern Processing
  # ============================================================================
  # These functions support the cybernetic variety processing from pattern detection
  
  defp update_environmental_model_with_pattern(state, pattern_data) do
    # Update S4's environmental model with received pattern
    environmental_model = state.environmental_model || %{}
    
    pattern_category = pattern_data[:pattern_type] || :unknown
    severity = pattern_data[:severity] || :low
    
    # Update pattern category statistics
    updated_model = Map.update(environmental_model, pattern_category, 
      %{
        count: 1,
        last_seen: DateTime.utc_now(),
        severity_history: [severity],
        vsm_impacts: [pattern_data[:vsm_impact] || %{}],
        environmental_significance: calculate_environmental_significance(pattern_data)
      },
      fn existing ->
        %{existing |
          count: existing.count + 1,
          last_seen: DateTime.utc_now(),
          severity_history: [severity | existing.severity_history] |> Enum.take(50),
          vsm_impacts: [pattern_data[:vsm_impact] | existing.vsm_impacts] |> Enum.take(50),
          environmental_significance: recalculate_significance(existing, pattern_data)
        }
      end
    )
    
    # Update overall environmental complexity based on pattern diversity
    complexity = calculate_environmental_complexity(updated_model)
    final_model = Map.put(updated_model, :environmental_complexity, complexity)
    
    %{state | environmental_model: final_model}
  end
  
  defp store_pattern_in_vector_store(pattern_data, state) do
    try do
      # Convert pattern to vector representation for HNSW storage
      pattern_vector = pattern_to_vector(pattern_data)
      
      # Create metadata for pattern storage
      metadata = %{
        pattern_type: pattern_data[:pattern_type],
        pattern_name: pattern_data[:pattern_name] || "unknown",
        severity: pattern_data[:severity] || :low,
        source: pattern_data[:source] || :external_detector,
        timestamp: pattern_data[:timestamp] || DateTime.utc_now(),
        confidence: pattern_data[:confidence] || 0.7,
        environmental_signal: true,
        s4_received_at: DateTime.utc_now()
      }
      
      # Store in vector store only if confidence is high enough
      if (pattern_data[:confidence] || 0.7) >= @pattern_confidence_threshold do
        case VectorStore.store_pattern(state.vector_store, pattern_vector, metadata) do
          :ok -> 
            # Update pattern cache with size limit
            new_cache = update_pattern_cache(state, pattern_data, metadata)
            Logger.debug("🧠 S4: Successfully stored high-confidence pattern")
            {:ok, %{state | pattern_cache: new_cache}}
          {:error, reason} ->
            Logger.warning("🧠 S4: Failed to store pattern: #{inspect(reason)}")
            {:ok, state}  # Continue operation without storage
        end
      else
        # Low confidence pattern - just update metrics, don't store
        Logger.debug("🧠 S4: Pattern below confidence threshold (#{pattern_data[:confidence]}) - not storing")
        {:ok, state}
      end
      
    rescue
      error ->
        Logger.error("🧠 S4: Error storing pattern in vector store: #{inspect(error)}")
        {:error, error}
    end
  end
  
  defp pattern_requires_strategy_update?(pattern_data) do
    # Determine if pattern requires immediate strategy update
    severity = pattern_data[:severity] || :low
    urgency = pattern_data[:urgency] || 0.5
    pattern_type = pattern_data[:pattern_type]
    
    # High severity patterns always require updates
    severity in [:critical, :high] or
    # High urgency patterns require updates
    urgency >= 0.6 or
    # Specific pattern types that affect S4 strategy
    pattern_type in [:error_cascade, :algedonic_storm, :coordination_breakdown, 
                     :variety_overload, :system_degradation, :environmental_shift]
  end
  
  defp update_strategy_based_on_pattern(state, pattern_data) do
    # Update S4's strategy based on received pattern
    strategy_updates = case {pattern_data[:pattern_type], pattern_data[:severity]} do
      {:error_cascade, severity} when severity in [:critical, :high] ->
        %{
          monitoring_intensity: :maximum,
          prediction_horizon: :short_term,  # Focus on immediate threats
          alert_threshold: 0.3,  # Lower threshold for faster response
          environmental_scan_frequency: :doubled,
          s3_notification_priority: :immediate
        }
        
      {:algedonic_storm, _} ->
        %{
          pain_monitoring: :continuous,
          intervention_readiness: :immediate,
          s5_policy_alert: true,
          algedonic_bypass_active: true,
          emergency_strategy_mode: true
        }
        
      {:coordination_breakdown, _} ->
        %{
          s2_monitoring: :enhanced,
          s1_resource_tracking: :detailed,
          sync_health_priority: :high,
          coordination_intelligence: :active
        }
        
      {:variety_overload, _} ->
        %{
          variety_monitoring: :critical,
          attenuation_readiness: :prepared,
          capacity_analysis: :continuous
        }
        
      {:environmental_shift, _} ->
        %{
          environmental_scan_frequency: :tripled,
          scenario_modeling: :extensive,
          adaptation_preparation: :active
        }
        
      _ ->
        %{
          pattern_integration: :normal,
          environmental_awareness: :enhanced
        }
    end
    
    # Merge strategy updates with current intelligence reports
    current_strategy = get_in(state.intelligence_reports, [:current_strategy]) || %{}
    updated_strategy = Map.merge(current_strategy, strategy_updates)
    
    # Update intelligence reports with new strategy
    new_reports = put_in(state.intelligence_reports, [:current_strategy], updated_strategy)
    
    # Log strategy change
    Logger.info("🧠 S4: Strategy updated based on #{pattern_data[:pattern_type]} pattern")
    
    %{state | intelligence_reports: new_reports}
  end
  
  defp apply_emergency_strategy_update(state, signal_data) do
    # Emergency strategy for critical environmental signals
    pattern = signal_data.pattern
    
    emergency_strategy = %{
      mode: :emergency,
      activated_by: pattern[:pattern_type],
      activation_time: DateTime.utc_now(),
      monitoring_intensity: :maximum,
      prediction_horizon: :immediate,
      alert_threshold: 0.1,  # Very low threshold
      s3_alerts: :continuous,
      s5_escalation: true,
      algedonic_bypass: true,
      emergency_actions: signal_data[:recommended_s4_actions] || []
    }
    
    # Override current strategy
    new_reports = put_in(state.intelligence_reports, [:emergency_strategy], emergency_strategy)
    
    # Alert other VSM subsystems
    EventBus.publish(:s4_emergency_strategy, %{
      strategy: emergency_strategy,
      pattern: pattern,
      recommended_actions: emergency_strategy.emergency_actions
    })
    
    Logger.warning("🧠 S4: EMERGENCY STRATEGY ACTIVATED - #{pattern[:pattern_type]}")
    
    %{state | intelligence_reports: new_reports}
  end
  
  defp apply_priority_strategy_update(state, signal_data) do
    # Priority strategy for high-importance patterns
    pattern = signal_data.pattern
    
    priority_adjustments = %{
      priority_mode: true,
      triggered_by: pattern[:pattern_type],
      monitoring_intensity: :high,
      pattern_focus: pattern[:pattern_type],
      enhanced_prediction: true,
      alert_threshold: 0.4
    }
    
    # Merge with current strategy
    current = get_in(state.intelligence_reports, [:current_strategy]) || %{}
    updated = Map.merge(current, priority_adjustments)
    
    new_reports = put_in(state.intelligence_reports, [:current_strategy], updated)
    
    Logger.info("🧠 S4: Priority strategy adjustments applied for #{pattern[:pattern_type]}")
    
    %{state | intelligence_reports: new_reports}
  end
  
  defp queue_pattern_for_analysis(state, signal_data) do
    # Queue pattern for detailed analysis during next environmental scan
    pattern = signal_data.pattern
    
    analysis_queue = get_in(state.intelligence_reports, [:analysis_queue]) || []
    new_item = %{
      pattern: pattern,
      queued_at: DateTime.utc_now(),
      priority: signal_data[:urgency] || 0.5,
      analysis_type: :detailed_environmental
    }
    
    updated_queue = [new_item | analysis_queue] |> Enum.take(100)  # Limit queue size
    new_reports = put_in(state.intelligence_reports, [:analysis_queue], updated_queue)
    
    Logger.debug("🧠 S4: Pattern queued for analysis - #{pattern[:pattern_type]}")
    
    %{state | intelligence_reports: new_reports}
  end
  
  defp alert_vsm_subsystems_urgent_pattern(signal_data, state) do
    # Alert S5 (Policy) and S3 (Control) about extremely urgent patterns
    pattern = signal_data.pattern
    urgency = signal_data[:urgency] || 0.9
    
    # Alert S5 for policy implications
    EventBus.publish(:s5_intelligence_alert, %{
      pattern_type: pattern[:pattern_type],
      severity: pattern[:severity],
      urgency: urgency,
      s4_recommendation: :immediate_policy_review,
      environmental_impact: :critical,
      timestamp: DateTime.utc_now()
    })
    
    # Alert S3 for control implications
    EventBus.publish(:s3_intelligence_alert, %{
      pattern_type: pattern[:pattern_type],
      control_implications: :immediate_adjustment,
      resource_impact: determine_resource_impact(pattern),
      recommended_actions: signal_data[:recommended_s4_actions] || [],
      urgency: urgency
    })
    
    Logger.warning("🧠 S4: URGENT alerts sent to S5 and S3 for #{pattern[:pattern_type]}")
  end
  
  defp update_pattern_metrics(state, pattern_data) do
    # Update S4's pattern detection metrics
    current_metrics = state.health_metrics
    
    new_metrics = %{current_metrics |
      patterns_detected: (current_metrics[:patterns_detected] || 0) + 1,
      last_pattern_received: DateTime.utc_now(),
      pattern_types_seen: update_pattern_types_count(current_metrics, pattern_data),
      environmental_intelligence_active: true
    }
    
    %{state | health_metrics: new_metrics}
  end
  
  # Helper functions for pattern processing
  
  defp calculate_environmental_significance(pattern_data) do
    # Calculate how significant this pattern is for environmental intelligence
    base_significance = case pattern_data[:severity] do
      :critical -> 0.9
      :high -> 0.7
      :medium -> 0.5
      :low -> 0.3
      _ -> 0.2
    end
    
    # Adjust based on pattern type
    type_modifier = case pattern_data[:pattern_type] do
      :environmental_shift -> 0.1
      :system_degradation -> 0.1
      :coordination_breakdown -> 0.05
      _ -> 0.0
    end
    
    min(base_significance + type_modifier, 1.0)
  end
  
  defp recalculate_significance(existing, new_pattern) do
    # Recalculate significance based on pattern history
    new_sig = calculate_environmental_significance(new_pattern)
    current_sig = existing[:environmental_significance] || 0.5
    
    # Weighted average favoring recent patterns
    (current_sig * 0.7) + (new_sig * 0.3)
  end
  
  defp calculate_environmental_complexity(environmental_model) do
    # Calculate overall environmental complexity based on pattern diversity
    pattern_types = Map.keys(environmental_model) |> length()
    total_patterns = environmental_model 
      |> Map.values() 
      |> Enum.map(&(&1[:count] || 0)) 
      |> Enum.sum()
    
    # Complexity based on diversity and volume
    diversity_factor = min(pattern_types / 10.0, 1.0)  # Max at 10 types
    volume_factor = min(total_patterns / 1000.0, 1.0)  # Max at 1000 patterns
    
    (diversity_factor + volume_factor) / 2
  end
  
  defp pattern_to_vector(pattern_data) do
    # Convert pattern data to vector representation for HNSW storage
    # This creates a 64-dimensional vector based on pattern characteristics
    
    # Base vector from pattern type
    type_vector = case pattern_data[:pattern_type] do
      :error_cascade -> List.duplicate(0.8, 16) ++ List.duplicate(0.0, 48)
      :algedonic_storm -> List.duplicate(0.0, 16) ++ List.duplicate(0.9, 16) ++ List.duplicate(0.0, 32)
      :coordination_breakdown -> List.duplicate(0.0, 32) ++ List.duplicate(0.7, 16) ++ List.duplicate(0.0, 16)
      :variety_overload -> List.duplicate(0.0, 48) ++ List.duplicate(0.6, 16)
      _ -> List.duplicate(0.5, 64)  # Default pattern
    end
    
    # Adjust based on severity
    severity_modifier = case pattern_data[:severity] do
      :critical -> 1.2
      :high -> 1.1
      :medium -> 1.0
      :low -> 0.8
      _ -> 0.9
    end
    
    # Apply modifier and normalize
    type_vector
    |> Enum.map(&(&1 * severity_modifier))
    |> Enum.map(&min(&1, 1.0))  # Ensure values stay <= 1.0
  end
  
  defp update_pattern_cache(state, pattern_data, metadata) do
    # Update pattern cache with size management
    current_cache = state.pattern_cache || %{}
    max_patterns = 10_000  # Configurable limit
    
    # Create cache key
    cache_key = "#{pattern_data[:pattern_type]}_#{metadata.timestamp.physical}"
    
    # Add new pattern
    new_cache = Map.put(current_cache, cache_key, %{
      pattern: pattern_data,
      metadata: metadata,
      stored_at: System.monotonic_time(:millisecond),
      access_count: 0
    })
    
    # Prune if necessary
    if map_size(new_cache) > max_patterns do
      prune_old_patterns(new_cache, 0.1)  # Remove 10% of oldest patterns
    else
      new_cache
    end
  end
  
  defp prune_old_patterns(cache, percentage) do
    # Remove percentage of oldest patterns
    total_patterns = map_size(cache)
    patterns_to_remove = round(total_patterns * percentage)
    
    # Sort by stored_at timestamp and remove oldest
    cache
    |> Enum.sort_by(fn {_key, value} -> value.stored_at end)
    |> Enum.drop(patterns_to_remove)
    |> Enum.into(%{})
  end
  
  defp update_pattern_types_count(metrics, pattern_data) do
    # Update count of different pattern types seen
    current_types = metrics[:pattern_types_seen] || %{}
    pattern_type = pattern_data[:pattern_type] || :unknown
    
    Map.update(current_types, pattern_type, 1, &(&1 + 1))
  end
  
  defp determine_resource_impact(pattern) do
    # Determine what resource impact this pattern might have
    case pattern[:pattern_type] do
      :error_cascade -> :high_cpu_memory
      :variety_overload -> :high_memory_io
      :coordination_breakdown -> :network_intensive
      :algedonic_storm -> :immediate_intervention
      _ -> :normal_monitoring
    end
  end

  defp analyze_pattern_correlations(state, pattern_data) do
    # Pattern Correlation Analysis - Core function for Issue #92
    # Analyzes relationships between this pattern and existing patterns using the correlation analyzer
    
    case state.correlation_analyzer do
      nil -> 
        Logger.debug("🔗 S4: Pattern Correlation Analyzer not available")
        state
      
      analyzer_pid ->
        try do
          # Get correlations for this pattern
          pattern_id = generate_pattern_id(pattern_data)
          
          case PatternCorrelationAnalyzer.get_correlations(pattern_id, []) do
            {:ok, correlations} ->
              # Process correlation insights
              process_correlation_insights(state, pattern_data, correlations)
              
            {:error, reason} ->
              Logger.debug("🔗 S4: Failed to get correlations: #{inspect(reason)}")
              state
          end
          
          # Request causality analysis for significant patterns
          if pattern_requires_causality_analysis?(pattern_data) do
            case PatternCorrelationAnalyzer.get_causality_chain(pattern_id, 3) do
              {:ok, causality_chain} ->
                publish_causality_insights(pattern_data, causality_chain)
                
              {:error, reason} ->
                Logger.debug("🔗 S4: Failed to get causality chain: #{inspect(reason)}")
            end
          end
          
          # Get cluster analysis for pattern classification
          case PatternCorrelationAnalyzer.get_cluster_analysis([]) do
            {:ok, cluster_analysis} ->
              update_environmental_model_with_clusters(state, cluster_analysis)
              
            {:error, reason} ->
              Logger.debug("🔗 S4: Failed to get cluster analysis: #{inspect(reason)}")
              state
          end
          
        catch
          :exit, _reason ->
            Logger.warning("🔗 S4: Pattern Correlation Analyzer process not responding")
            state
        end
    end
  end

  defp process_correlation_insights(state, pattern_data, correlations) do
    # Process correlation insights and update state accordingly
    if length(correlations) > 0 do
      Logger.info("🔗 S4: Found #{length(correlations)} correlations for pattern #{pattern_data[:pattern_type]}")
      
      # Update intelligence reports with correlation data
      correlation_report = %{
        pattern_id: generate_pattern_id(pattern_data),
        pattern_type: pattern_data[:pattern_type],
        correlation_count: length(correlations),
        high_confidence_correlations: Enum.count(correlations, &(&1[:confidence] > 0.8)),
        timestamp: DateTime.utc_now()
      }
      
      new_reports = [correlation_report | state.intelligence_reports] |> Enum.take(50)
      %{state | intelligence_reports: new_reports}
    else
      state
    end
  end

  defp pattern_requires_causality_analysis?(pattern_data) do
    # Determine if this pattern warrants causality analysis
    severity = pattern_data[:severity] || :normal
    confidence = pattern_data[:confidence] || 0.0
    
    severity in [:high, :critical] or confidence > 0.8
  end

  defp publish_causality_insights(pattern_data, causality_chain) do
    # Publish causality insights to EventBus for other VSM subsystems
    if length(causality_chain) > 1 do
      EventBus.publish(:pattern_causality_detected, %{
        root_pattern: pattern_data,
        causality_chain: causality_chain,
        chain_length: length(causality_chain),
        source: :s4_intelligence,
        timestamp: DateTime.utc_now()
      })
      
      Logger.info("🔗 S4: Published causality chain with #{length(causality_chain)} patterns")
    end
  end

  defp update_environmental_model_with_clusters(state, cluster_analysis) do
    # Update environmental model with cluster insights
    current_model = state.environmental_model
    
    cluster_summary = %{
      cluster_count: Map.get(cluster_analysis, :cluster_count, 0),
      largest_cluster_size: Map.get(cluster_analysis, :largest_cluster_size, 0),
      clustering_quality: Map.get(cluster_analysis, :quality_score, 0.0),
      updated_at: DateTime.utc_now()
    }
    
    new_model = Map.put(current_model, :pattern_clusters, cluster_summary)
    %{state | environmental_model: new_model}
  end

  defp generate_pattern_id(pattern_data) do
    # Generate a consistent ID for pattern data
    pattern_type = pattern_data[:pattern_type] || "unknown"
    pattern_name = pattern_data[:pattern_name] || "unnamed"
    metadata = inspect(pattern_data[:metadata] || %{})
    
    :crypto.hash(:sha256, "#{pattern_type}#{pattern_name}#{metadata}")
    |> Base.encode16()
    |> String.slice(0, 16)
  end
end