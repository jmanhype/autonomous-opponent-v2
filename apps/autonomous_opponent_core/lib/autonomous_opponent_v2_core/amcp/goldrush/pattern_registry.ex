defmodule AutonomousOpponentV2Core.AMCP.Goldrush.PatternRegistry do
  @moduledoc """
  Registry for managing and activating VSM patterns from the pattern library.
  
  This module acts as the bridge between the VSM Pattern Library and the
  PatternMatcher, handling pattern registration, activation, and lifecycle.
  
  Features:
  - Dynamic pattern loading from VSM Pattern Library
  - Pattern compilation and optimization
  - Priority-based pattern evaluation
  - Pattern performance tracking
  - Algedonic response coordination
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.AMCP.Goldrush.{PatternMatcher, VSMPatternLibrary}
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: AlgedonicChannel
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Core.Metrics
  
  @default_pattern_config %{
    auto_activate_critical: true,
    performance_tracking: true,
    algedonic_integration: true,
    early_warning_enabled: true
  }
  
  defstruct [
    :patterns,           # Map of pattern_name => compiled_pattern
    :active_patterns,    # Set of currently active pattern names
    :pattern_stats,      # Performance statistics per pattern
    :config,            # Configuration options
    :evaluation_order,   # Priority-ordered list of patterns
    :algedonic_mapping  # Pattern => algedonic response mapping
  ]
  
  # ============================================================================
  # PUBLIC API
  # ============================================================================
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Load all patterns from a specific domain.
  """
  def load_domain_patterns(domain) when domain in [:cybernetic, :integration, :technical, :distributed] do
    GenServer.call(__MODULE__, {:load_domain_patterns, domain})
  end
  
  @doc """
  Load all critical patterns across all domains.
  """
  def load_critical_patterns do
    GenServer.call(__MODULE__, :load_critical_patterns)
  end
  
  @doc """
  Activate a specific pattern for monitoring.
  """
  def activate_pattern(pattern_name) do
    GenServer.call(__MODULE__, {:activate_pattern, pattern_name})
  end
  
  @doc """
  Deactivate a pattern from monitoring.
  """
  def deactivate_pattern(pattern_name) do
    GenServer.call(__MODULE__, {:deactivate_pattern, pattern_name})
  end
  
  @doc """
  Get all active patterns.
  """
  def active_patterns do
    GenServer.call(__MODULE__, :get_active_patterns)
  end
  
  @doc """
  Get pattern performance statistics.
  """
  def pattern_stats(pattern_name \\ nil) do
    GenServer.call(__MODULE__, {:get_pattern_stats, pattern_name})
  end
  
  @doc """
  Evaluate an event against all active patterns.
  Returns list of matched patterns with their responses.
  """
  def evaluate_event(event) do
    GenServer.call(__MODULE__, {:evaluate_event, event})
  end
  
  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================
  
  @impl true
  def init(opts) do
    config = Map.merge(@default_pattern_config, Map.new(opts))
    
    state = %__MODULE__{
      patterns: %{},
      active_patterns: MapSet.new(),
      pattern_stats: %{},
      config: config,
      evaluation_order: [],
      algedonic_mapping: %{}
    }
    
    # Subscribe to relevant events
    EventBus.subscribe(:vsm_events)
    EventBus.subscribe(:system_events)
    
    # Auto-load critical patterns if configured
    if config.auto_activate_critical do
      send(self(), :auto_load_critical)
    end
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:load_domain_patterns, domain}, _from, state) do
    patterns = VSMPatternLibrary.patterns_by_domain(domain)
    
    {loaded_patterns, new_state} = Enum.reduce(patterns, {[], state}, fn {name, pattern}, {loaded, st} ->
      case compile_and_store_pattern(name, pattern, st) do
        {:ok, updated_state} ->
          {[name | loaded], updated_state}
        {:error, reason} ->
          Logger.error("Failed to compile pattern #{name}: #{inspect(reason)}")
          {loaded, st}
      end
    end)
    
    {:reply, {:ok, loaded_patterns}, new_state}
  end
  
  @impl true
  def handle_call(:load_critical_patterns, _from, state) do
    critical_patterns = VSMPatternLibrary.patterns_by_severity(:critical)
    
    {loaded_patterns, new_state} = Enum.reduce(critical_patterns, {[], state}, fn {name, pattern}, {loaded, st} ->
      case compile_and_store_pattern(name, pattern, st) do
        {:ok, updated_state} ->
          # Auto-activate critical patterns
          {:ok, activated_state} = activate_pattern_internal(name, updated_state)
          {[name | loaded], activated_state}
        {:error, reason} ->
          Logger.error("Failed to compile critical pattern #{name}: #{inspect(reason)}")
          {loaded, st}
      end
    end)
    
    {:reply, {:ok, loaded_patterns}, new_state}
  end
  
  @impl true
  def handle_call({:activate_pattern, pattern_name}, _from, state) do
    case activate_pattern_internal(pattern_name, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:deactivate_pattern, pattern_name}, _from, state) do
    new_state = %{state |
      active_patterns: MapSet.delete(state.active_patterns, pattern_name),
      evaluation_order: List.delete(state.evaluation_order, pattern_name)
    }
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_active_patterns, _from, state) do
    active_with_details = state.active_patterns
    |> Enum.map(fn name ->
      pattern = Map.get(state.patterns, name)
      stats = Map.get(state.pattern_stats, name, %{})
      
      %{
        name: name,
        pattern: pattern,
        stats: stats
      }
    end)
    
    {:reply, active_with_details, state}
  end
  
  @impl true
  def handle_call({:get_pattern_stats, nil}, _from, state) do
    {:reply, state.pattern_stats, state}
  end
  
  @impl true
  def handle_call({:get_pattern_stats, pattern_name}, _from, state) do
    stats = Map.get(state.pattern_stats, pattern_name, %{})
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:evaluate_event, event}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Evaluate event against all active patterns in priority order
    matches = state.evaluation_order
    |> Enum.reduce([], fn pattern_name, acc ->
      pattern = Map.get(state.patterns, pattern_name)
      
      case evaluate_single_pattern(pattern, event, state) do
        {:match, context} ->
          match_result = %{
            pattern_name: pattern_name,
            pattern: pattern,
            context: context,
            algedonic_response: Map.get(state.algedonic_mapping, pattern_name)
          }
          
          # Update stats
          update_pattern_stats(pattern_name, :match, state)
          
          # Trigger algedonic response if configured
          if state.config.algedonic_integration && match_result.algedonic_response do
            trigger_algedonic_response(match_result)
          end
          
          [match_result | acc]
          
        :no_match ->
          update_pattern_stats(pattern_name, :no_match, state)
          acc
      end
    end)
    |> Enum.reverse()
    
    evaluation_time = System.monotonic_time(:microsecond) - start_time
    
    # Track overall evaluation performance
    Metrics.increment_counter(:pattern_evaluations_total)
    Metrics.record_histogram(:pattern_evaluation_time, evaluation_time)
    
    {:reply, {:ok, matches}, state}
  end
  
  @impl true
  def handle_call({:get_pattern, pattern_name}, _from, state) do
    pattern = Map.get(state.patterns, pattern_name)
    {:reply, pattern, state}
  end
  
  @impl true
  def handle_info(:auto_load_critical, state) do
    # Direct load instead of calling self
    critical_patterns = VSMPatternLibrary.patterns_by_severity(:critical)
    
    {loaded_patterns, new_state} = Enum.reduce(critical_patterns, {[], state}, fn {name, pattern}, {loaded, st} ->
      case compile_and_store_pattern(name, pattern, st) do
        {:ok, updated_state} ->
          # Auto-activate critical patterns
          {:ok, activated_state} = activate_pattern_internal(name, updated_state)
          {[name | loaded], activated_state}
        {:error, reason} ->
          Logger.error("Failed to compile critical pattern #{name}: #{inspect(reason)}")
          {loaded, st}
      end
    end)
    
    if length(loaded_patterns) > 0 do
      Logger.info("Auto-loaded #{length(loaded_patterns)} critical VSM patterns")
    else
      Logger.error("Failed to auto-load any critical patterns")
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus, event}, state) do
    # Asynchronously evaluate events from EventBus
    Task.start(fn ->
      case evaluate_event(event) do
        {:ok, matches} when matches != [] ->
          Logger.debug("Pattern matches for event: #{inspect(matches)}")
        _ ->
          :ok
      end
    end)
    
    {:noreply, state}
  end
  
  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================
  
  defp compile_and_store_pattern(name, pattern_def, state) do
    # Convert VSM pattern to PatternMatcher format
    matcher_pattern = VSMPatternLibrary.to_pattern_matcher_format(name, pattern_def)
    
    # Ensure the pattern has a name field for later reference
    matcher_pattern_with_name = Map.put(matcher_pattern, :pattern_name, name)
    
    # Compile the pattern
    case PatternMatcher.compile_pattern(matcher_pattern_with_name) do
      {:ok, compiled_pattern} ->
        # Store the original pattern name in the compiled pattern
        compiled_pattern_with_name = Map.put(compiled_pattern, :pattern_name, name)
        new_patterns = Map.put(state.patterns, name, compiled_pattern_with_name)
        
        # Store algedonic mapping if present
        new_algedonic = if algedonic = pattern_def[:algedonic_response] do
          Map.put(state.algedonic_mapping, name, algedonic)
        else
          state.algedonic_mapping
        end
        
        # Initialize stats
        new_stats = Map.put_new(state.pattern_stats, name, %{
          matches: 0,
          no_matches: 0,
          evaluation_time_sum: 0,
          evaluation_count: 0,
          first_seen: DateTime.utc_now(),
          last_match: nil
        })
        
        new_state = %{state |
          patterns: new_patterns,
          algedonic_mapping: new_algedonic,
          pattern_stats: new_stats
        }
        
        {:ok, new_state}
        
      error ->
        error
    end
  end
  
  defp activate_pattern_internal(pattern_name, state) do
    if Map.has_key?(state.patterns, pattern_name) do
      pattern = Map.get(state.patterns, pattern_name)
      severity = get_pattern_severity(pattern)
      
      new_active = MapSet.put(state.active_patterns, pattern_name)
      new_order = update_evaluation_order(state.evaluation_order, pattern_name, severity)
      
      new_state = %{state |
        active_patterns: new_active,
        evaluation_order: new_order
      }
      
      {:ok, new_state}
    else
      {:error, :pattern_not_found}
    end
  end
  
  defp evaluate_single_pattern(pattern, event, state) do
    start_time = System.monotonic_time(:microsecond)
    
    result = try do
      # The pattern from VSMPatternLibrary needs proper name field
      pattern_with_name = Map.put(pattern, :name, Map.get(pattern.metadata, :name, :unknown))
      PatternMatcher.match_event(pattern_with_name, event)
    rescue
      error ->
        Logger.error("Pattern evaluation error: #{inspect(error)}")
        :no_match
    end
    
    evaluation_time = System.monotonic_time(:microsecond) - start_time
    
    # Track per-pattern performance if enabled
    if state.config.performance_tracking do
      Metrics.record_histogram(:per_pattern_evaluation_time, evaluation_time)
    end
    
    result
  end
  
  defp update_pattern_stats(pattern_name, result, _state) do
    GenServer.cast(self(), {:update_stats, pattern_name, result})
  end
  
  @impl true
  def handle_cast({:update_stats, pattern_name, result}, state) do
    stats = Map.get(state.pattern_stats, pattern_name, %{})
    
    updated_stats = case result do
      :match ->
        %{stats |
          matches: (stats[:matches] || 0) + 1,
          last_match: DateTime.utc_now()
        }
      :no_match ->
        %{stats |
          no_matches: (stats[:no_matches] || 0) + 1
        }
    end
    
    new_pattern_stats = Map.put(state.pattern_stats, pattern_name, updated_stats)
    {:noreply, %{state | pattern_stats: new_pattern_stats}}
  end
  
  defp trigger_algedonic_response(match_result) do
    %{
      pattern_name: pattern_name,
      algedonic_response: response,
      context: context
    } = match_result
    
    # Publish algedonic signal
    algedonic_event = %{
      type: :pattern_triggered_pain,
      pattern: pattern_name,
      pain_level: response.pain_level,
      urgency: response.urgency,
      target: response.target,
      bypass_hierarchy: Map.get(response, :bypass_hierarchy, false),
      context: context,
      timestamp: DateTime.utc_now()
    }
    
    # Use AlgedonicChannel if available, otherwise EventBus
    try do
      AlgedonicChannel.report_pain(pattern_name, response.pain_level, urgency: response.urgency)
    rescue
      _ ->
        EventBus.publish(:algedonic_signals, algedonic_event)
    end
    
    # Log critical algedonic signals
    if response.pain_level >= 0.8 do
      Logger.warning("Critical algedonic signal from pattern #{pattern_name}: pain=#{response.pain_level}")
    end
  end
  
  defp get_pattern_severity(pattern) do
    pattern.metadata[:severity] || :medium
  end
  
  
  defp update_evaluation_order(current_order, pattern_name, severity) do
    # Remove if already present
    filtered = List.delete(current_order, pattern_name)
    
    # Insert based on severity priority
    priority_index = case severity do
      :critical -> 0
      :high -> 1
      :medium -> 2
      :low -> 3
      _ -> 4
    end
    
    # Simple insertion based on priority - avoid calling self during initialization
    case priority_index do
      0 -> [pattern_name | filtered]  # Critical goes first
      1 -> 
        {critical, rest} = Enum.split_with(filtered, &String.contains?(to_string(&1), "critical"))
        critical ++ [pattern_name | rest]
      _ -> filtered ++ [pattern_name]  # Others go at end
    end
  end
  
end