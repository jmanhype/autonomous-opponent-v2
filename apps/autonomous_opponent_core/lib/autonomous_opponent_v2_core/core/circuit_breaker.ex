defmodule AutonomousOpponentV2Core.Core.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern implementation for VSM algedonic system.
  Prevents cascade failures in cybernetic control loops.

  States:
  - :closed - Normal operation, calls pass through
  - :open - Circuit broken, calls fail fast
  - :half_open - Testing if service recovered

  Integrates with EventBus for algedonic pain/pleasure signals.

  ## Wisdom Preservation

  ### Why Circuit Breaker Exists
  The circuit breaker is the VSM's "immune system" - it prevents sick subsystems
  from infecting healthy ones. Beer recognized that in complex systems, failures
  cascade. One slow service makes its callers slow, which makes their callers slow,
  until the entire system grinds to a halt. The circuit breaker breaks this chain.

  ### Design Decisions & Rationale

  1. **Three States (Closed/Open/Half-Open)**: Mirrors electrical circuits. Closed
     = current flows (normal). Open = no current (protection). Half-open = testing
     recovery (hope). This simple state machine handles complex failure patterns.

  2. **Failure Threshold (Default 5)**: Not 1 (too sensitive) or 10 (too tolerant).
     5 failures indicates a pattern, not a glitch. Based on telecom standards where
     5 dropped calls triggers investigation.

  3. **Recovery Time (Default 60s)**: One minute recovery. Long enough for transient
     issues to resolve (network hiccups, GC pauses), short enough to retry quickly.
     Matches human attention spans - we notice minute-long outages.

  4. **Algedonic Integration**: Circuit breaks generate pain signals, recovery generates
     pleasure. This isn't anthropomorphism but cybernetic feedback. The system literally
     "feels" its health state and responds viscerally.

  5. **ETS for Metrics**: In-memory metrics for speed. Circuit breakers must be FAST -
     they're in the hot path. ETS gives us concurrent reads/writes without bottlenecks.
     Trade-off: Metrics lost on restart, but circuit state is transient anyway.
  """
  use GenServer
  require Logger

  alias AutonomousOpponentV2Core.EventBus

  # Configuration constants to avoid magic numbers
  @max_pain_signals 100
  @pain_decay_half_life_ms 30_000  # 30 seconds
  @pain_history_retention_ms 24 * 60 * 60 * 1000  # 24 hours
  @default_pain_threshold 0.8
  @default_pain_window_ms 60_000  # 1 minute
  @default_failure_threshold 5
  @default_recovery_time_ms 60_000  # 1 minute
  @default_timeout_ms 5_000  # 5 seconds

  # Client API

  @doc """
  Starts a circuit breaker with the given options.

  Options:
    - name: The registered name for the circuit breaker
    - failure_threshold: Number of failures before opening (default: 5)
    - recovery_time_ms: Time to wait before trying half-open (default: 60_000)
    - timeout_ms: Call timeout before considering failure (default: 5_000)
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Execute a function through the circuit breaker.
  Returns {:ok, result} or {:error, reason}
  """
  def call(name, fun) when is_function(fun, 0) do
    GenServer.call(name, {:call, fun})
  catch
    :exit, {:timeout, _} ->
      {:error, :circuit_timeout}
  end

  @doc """
  Get current circuit breaker state and metrics
  """
  def get_state(name) do
    GenServer.call(name, :get_state)
  end

  @doc """
  Reset the circuit breaker manually
  """
  def reset(name) do
    GenServer.call(name, :reset)
  end
  
  @doc """
  Force the circuit breaker open (for testing/emergency)
  """
  def force_open(name) do
    GenServer.call(name, :force_open)
  end
  
  @doc """
  Force the circuit breaker closed (for testing/recovery)
  """
  def force_close(name) do
    GenServer.call(name, :force_close)
  end

  @doc """
  Record a failure for the circuit breaker (for external failure reporting)
  """
  def record_failure(name) do
    GenServer.cast(name, :record_failure)
  end
  
  @doc """
  Initialize a circuit breaker by name.
  Creates or ensures a circuit breaker process exists.
  """
  def initialize(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    initialize(name)
  end

  def initialize(name) when is_atom(name) do
    # Check if the circuit breaker already exists
    case Process.whereis(name) do
      nil ->
        # Start a new circuit breaker
        case start_link(name: name) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end
      _pid ->
        # Already exists
        :ok
    end
  end

  # Server callbacks

  defstruct [
    :name,
    :state,
    :failure_count,
    :success_count,
    :last_failure_time,
    :failure_threshold,
    :recovery_time_ms,
    :timeout_ms,
    :half_open_test_in_progress,
    :metrics_table,
    # ALGEDONIC ENHANCEMENT: Pain awareness
    :pain_threshold,         # Intensity threshold for forced opening
    :pain_window_ms,         # Time window for pain signal accumulation
    :pain_response_enabled,  # Feature flag for pain-triggered opening
    :pain_learning_data,     # Historical pain → failure correlations
    :error_count,           # Count of consecutive pain processing errors
    :degraded_mode          # Whether circuit is in degraded mode due to errors
  ]

  @impl true
  def init(opts) do
    # Create ETS table for metrics
    table_name = :"circuit_breaker_#{opts[:name]}_metrics"
    :ets.new(table_name, [:named_table, :public, :set, {:write_concurrency, true}])

    # Initialize metrics
    :ets.insert(table_name, {:total_calls, 0})
    :ets.insert(table_name, {:total_failures, 0})
    :ets.insert(table_name, {:total_successes, 0})
    :ets.insert(table_name, {:state_transitions, []})
    :ets.insert(table_name, {:pain_triggered_opens, 0})
    :ets.insert(table_name, {:pain_predictions_correct, 0})
    :ets.insert(table_name, {:pain_predictions_total, 0})

    # ALGEDONIC AWAKENING: Subscribe to the system's pain
    EventBus.subscribe(:algedonic_pain)
    EventBus.subscribe(:emergency_algedonic)
    
    # Create pain tracking table for high-volume scenarios
    pain_table = :"circuit_breaker_#{opts[:name]}_pain"
    case :ets.info(pain_table) do
      :undefined -> :ets.new(pain_table, [:ordered_set, :public, {:write_concurrency, true}])
      _ -> pain_table  # Table already exists (e.g., after GenServer restart)
    end

    state = %__MODULE__{
      name: opts[:name],
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      failure_threshold: opts[:failure_threshold] || @default_failure_threshold,
      recovery_time_ms: opts[:recovery_time_ms] || @default_recovery_time_ms,
      timeout_ms: opts[:timeout_ms] || @default_timeout_ms,
      half_open_test_in_progress: false,
      metrics_table: table_name,
      # ALGEDONIC CONFIGURATION
      pain_threshold: opts[:pain_threshold] || @default_pain_threshold,
      pain_window_ms: opts[:pain_window_ms] || @default_pain_window_ms,
      pain_response_enabled: opts[:pain_response_enabled] || true,
      pain_learning_data: %{
        pain_table: pain_table,
        correlation_strength: 0.0
      },
      error_count: 0,
      degraded_mode: false
    }

    # Skip EventBus publish during initialization to avoid startup issues
    # EventBus.publish(:circuit_breaker_initialized, %{
    #   name: state.name,
    #   config: %{
    #     failure_threshold: state.failure_threshold,
    #     recovery_time_ms: state.recovery_time_ms,
    #     timeout_ms: state.timeout_ms
    #   }
    # })

    {:ok, state}
  end

  # WISDOM: Closed state handler - normal operation with vigilance
  # When closed, we trust but verify. Execute the function but watch for failures.
  # Task.async gives us timeout control - critical for circuit breakers. Without
  # timeouts, slow services become service denials. The try/rescue/catch ensures
  # we capture ALL failure modes, not just exceptions. Every failure is data.
  @impl true
  def handle_call({:call, fun}, _from, %{state: :closed} = state) do
    # Check if we're in degraded mode
    if state.degraded_mode do
      # In degraded mode, be more conservative
      Logger.warning("Circuit breaker #{state.name} operating in degraded mode")
    end
    
    # Circuit is closed, execute the function with timeout protection
    task =
      Task.async(fn ->
        try do
          {:ok, fun.()}
        rescue
          e -> {:error, e}
        catch
          :exit, reason -> {:error, {:exit, reason}}
          :throw, value -> {:error, {:throw, value}}
        end
      end)

    # WISDOM: Task.yield with timeout - the safety net
    # yield waits up to timeout_ms, then returns nil. Task.shutdown ensures
    # we don't leak processes. This pattern prevents zombie processes.
    case Task.yield(task, state.timeout_ms) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        # Success - reset failure count (forgive past sins)
        new_state = handle_success(state)
        {:reply, {:ok, result}, new_state}

      {:ok, {:error, error}} ->
        # Function returned error - count towards threshold
        new_state = handle_failure(state, error)
        {:reply, {:error, error}, new_state}

      nil ->
        # Timeout - as bad as error, maybe worse
        new_state = handle_failure(state, :timeout)
        {:reply, {:error, :timeout}, new_state}
    end
  end

  # WISDOM: Open state handler - fail fast with hope
  # When open, we reject calls immediately - this is the whole point. BUT we
  # always check if recovery time has passed. This automatic recovery attempt
  # is crucial - manual intervention doesn't scale. Systems must self-heal.
  # Note: we still return error even when transitioning to half-open - the
  # caller doesn't get a free pass just because we're hopeful.
  def handle_call({:call, _fun}, _from, %{state: :open} = state) do
    # Circuit is open, check if we should transition to half-open
    if should_attempt_reset?(state) do
      new_state = transition_to_half_open(state)
      {:reply, {:error, :circuit_open}, new_state}
    else
      # Still in recovery period - fail fast
      update_metrics(state, :rejected)
      {:reply, {:error, :circuit_open}, state}
    end
  end

  # WISDOM: Half-open state - the delicate test of recovery
  # Half-open is the circuit breaker's moment of hope. We allow ONE call through
  # as a test. If it succeeds, we trust again (closed). If it fails, back to
  # protection (open). The half_open_test_in_progress flag ensures only one
  # guinea pig at a time - we don't sacrifice multiple calls to test recovery.
  # This is cautious optimism encoded in software.
  def handle_call(
        {:call, fun},
        _from,
        %{state: :half_open, half_open_test_in_progress: false} = state
      ) do
    # Half-open state - allow one test call
    new_state = %{state | half_open_test_in_progress: true}

    # Execute the test call with same vigilance as closed state
    task =
      Task.async(fn ->
        try do
          {:ok, fun.()}
        rescue
          e -> {:error, e}
        catch
          :exit, reason -> {:error, {:exit, reason}}
          :throw, value -> {:error, {:throw, value}}
        end
      end)

    # WISDOM: Binary decision point - recovery or relapse
    # This single call determines the circuit's fate. Success = full recovery.
    # Failure = back to isolation. No second chances in half-open state.
    case Task.yield(task, state.timeout_ms) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        # Success - service recovered! Close the circuit
        final_state = transition_to_closed(new_state)
        {:reply, {:ok, result}, final_state}

      {:ok, {:error, error}} ->
        # Failed - not recovered yet, back to open
        final_state = transition_to_open(new_state, error)
        {:reply, {:error, error}, final_state}

      nil ->
        # Timeout - still sick, back to open
        final_state = transition_to_open(new_state, :timeout)
        {:reply, {:error, :timeout}, final_state}
    end
  end

  def handle_call(
        {:call, _fun},
        _from,
        %{state: :half_open, half_open_test_in_progress: true} = state
      ) do
    # Another call while test is in progress
    {:reply, {:error, :circuit_half_open_busy}, state}
  end
  
  def handle_call(:health_check, _from, state) do
    # Health is based on circuit state
    health = case state.state do
      :closed -> 1.0
      :half_open -> 0.5
      :open -> 0.0
    end
    
    {:reply, health, state}
  end

  def handle_call(:get_state, _from, state) do
    metrics = get_metrics(state)

    reply = %{
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      last_failure_time: state.last_failure_time,
      metrics: metrics
    }

    {:reply, reply, state}
  end

  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        last_failure_time: nil,
        half_open_test_in_progress: false
    }

    # Publish reset event
    EventBus.publish(:circuit_breaker_reset, %{
      name: state.name,
      previous_state: state.state
    })

    {:reply, :ok, new_state}
  end
  
  def handle_call(:force_open, _from, state) do
    new_state = %{
      state
      | state: :open,
        last_failure_time: System.monotonic_time(:millisecond),
        half_open_test_in_progress: false
    }
    
    EventBus.publish(:circuit_breaker_opened, %{
      name: state.name,
      forced: true
    })
    
    {:reply, :ok, new_state}
  end
  
  def handle_call(:force_close, _from, state) do
    new_state = %{
      state
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        last_failure_time: nil,
        half_open_test_in_progress: false
    }
    
    EventBus.publish(:circuit_breaker_closed, %{
      name: state.name,
      forced: true
    })
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:record_failure, state) do
    new_state = handle_failure(state, :external_failure)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:event_bus_hlc, event}, state) do
    # WISDOM: HLC format - the future of causally ordered pain
    # Hybrid Logical Clocks ensure pain signals maintain causal ordering
    # If pain A caused pain B, we WILL process them in that order
    case event.type do
      :algedonic_pain ->
        # HLC timestamp is the event.timestamp itself in new format
        handle_algedonic_pain(event.data, event.timestamp.physical, event.timestamp, state)
      :emergency_algedonic ->
        # EMERGENCY BYPASS: Maximum pain demands immediate response
        handle_emergency_pain(event.data, state)
      _ ->
        {:noreply, state}
    end
  end

  # Legacy EventBus format - still supported but will be deprecated
  def handle_info({:event_bus, event_type, data}, state) do
    case event_type do
      :algedonic_pain ->
        # Convert to standardized format
        timestamp = System.monotonic_time(:millisecond)
        handle_algedonic_pain(data, timestamp, nil, state)
      :emergency_algedonic ->
        handle_emergency_pain(data, state)
      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  # ALGEDONIC PAIN PROCESSING - The Heart of Cybernetic Feeling
  defp handle_algedonic_pain(data, timestamp, hlc, state) do
    # Skip if pain response is disabled (for testing/maintenance)
    unless state.pain_response_enabled do
      {:noreply, state}
    else
      try do
        # Validate and normalize pain signal
        pain_signal = normalize_pain_signal(data, timestamp, hlc)
        
        # Check if this pain is relevant to us
        if relevant_pain_signal?(pain_signal, state) do
          # WISDOM: Not all pain is our pain
          # We must distinguish between pain we can act on vs ambient suffering
          new_state = process_pain_signal(pain_signal, state)
          
          # Clear error count on successful processing
          final_state = if new_state.error_count > 0 do
            %{new_state | error_count: 0, degraded_mode: false}
          else
            new_state
          end
          
          {:noreply, final_state}
        else
          # Track for learning even if not actionable
          record_ambient_pain(pain_signal, state)
          {:noreply, state}
        end
      rescue
        error ->
          # Pain processing errors trigger degraded mode
          Logger.error("Circuit breaker #{state.name} error processing pain: #{inspect(error)}")
          :telemetry.execute(
            [:circuit_breaker, :pain_processing, :error],
            %{count: 1},
            %{name: state.name, error: error}
          )
          
          # Increment error count and check for degraded mode
          new_error_count = state.error_count + 1
          degraded = new_error_count >= 3  # Three strikes
          
          if degraded and not state.degraded_mode do
            Logger.warning("Circuit breaker #{state.name} entering degraded mode due to pain processing errors")
            EventBus.publish(:circuit_breaker_degraded, %{
              name: state.name,
              reason: :pain_processing_errors,
              error_count: new_error_count
            })
          end
          
          {:noreply, %{state | error_count: new_error_count, degraded_mode: degraded}}
      end
    end
  end

  # EMERGENCY PAIN - When the System Screams
  defp handle_emergency_pain(data, state) do
    Logger.error("EMERGENCY ALGEDONIC SIGNAL received by #{state.name}: #{inspect(data)}")
    
    # Emergency pain ALWAYS forces circuit open
    # This is the system's emergency brake
    new_state = transition_to_open(state, {:emergency_pain, data})
    
    # Propagate emergency to dependent circuits
    EventBus.publish(:circuit_breaker_emergency_cascade, %{
      source: state.name,
      original_pain: data,
      timestamp: System.monotonic_time(:millisecond)
    })
    
    {:noreply, new_state}
  end

  # PAIN SIGNAL NORMALIZATION - Making Pain Comprehensible
  defp normalize_pain_signal(data, timestamp, hlc) do
    %{
      # Core pain attributes
      intensity: calculate_pain_intensity(data),
      source: data[:source] || :unknown,
      metric: data[:metric] || :general,
      reason: data[:reason] || data[:message] || "unspecified pain",
      
      # Temporal attributes
      timestamp: timestamp,
      hlc: hlc,
      
      # Context for learning
      affected_services: data[:affected_services] || [],
      cascading: data[:cascading] || false,
      
      # Original data for deep analysis
      raw_data: data
    }
  end

  # PAIN INTENSITY CALCULATION - Quantifying Suffering
  defp calculate_pain_intensity(data) do
    # Multiple ways to express pain intensity
    cond do
      # Direct intensity value (0.0 to 1.0)
      is_number(data[:intensity]) ->
        max(0.0, min(1.0, data[:intensity]))
      
      # Severity levels mapped to intensity
      data[:severity] == :critical -> 1.0
      data[:severity] == :high -> 0.8
      data[:severity] == :medium -> 0.5
      data[:severity] == :low -> 0.2
      
      # Legacy pain levels
      data[:pain_level] == "AGONY" -> 1.0
      data[:pain_level] == "SEVERE" -> 0.8
      data[:pain_level] == "MODERATE" -> 0.5
      
      # Default moderate pain
      true -> 0.5
    end
  end

  # PAIN RELEVANCE - Is This Our Pain to Bear?
  defp relevant_pain_signal?(signal, state) do
    cond do
      # Our own pain creates feedback loops - ignore
      signal.source == :circuit_breaker and signal.raw_data[:name] == state.name ->
        false
      
      # Pain explicitly targeting us
      state.name in signal.affected_services ->
        true
      
      # Cascading pain from dependent services
      signal.cascading and dependent_service?(signal.source, state) ->
        true
      
      # System-wide pain affects everyone
      signal.raw_data[:scope] == :system_wide ->
        true
      
      # Pain from services we protect
      protected_service?(signal.source, state) ->
        true
      
      # Default: not our problem
      true ->
        false
    end
  end

  # PAIN SIGNAL PROCESSING - The Cybernetic Response
  defp process_pain_signal(signal, state) do
    # Use ETS for efficient pain signal storage
    pain_table = state.pain_learning_data.pain_table
    cutoff_time = signal.timestamp - state.pain_window_ms
    
    # Store signal in ETS with timestamp as key
    signal_id = {signal.timestamp, :erlang.unique_integer([:monotonic])}
    :ets.insert(pain_table, {signal_id, signal})
    
    # Clean old signals atomically
    :ets.select_delete(pain_table, [
      {{{:"$1", :_}, :_}, [{:<, :"$1", cutoff_time}], [true]}
    ])
    
    # Get recent signals for metrics calculation
    recent_signals = :ets.select(pain_table, [
      {{{:"$1", :_}, :"$2"}, [{:>=, :"$1", cutoff_time}], [:"$2"]}
    ])
    |> Enum.sort_by(& &1.timestamp, :desc)
    |> Enum.take(@max_pain_signals)
    
    # Calculate aggregate pain metrics
    pain_metrics = calculate_pain_metrics(recent_signals, state)
    
    # Update state with new pain data
    new_state = %{state | 
      pain_learning_data: update_pain_learning(pain_metrics, state.pain_learning_data)
    }
    
    # DECISION POINT: Should we break the circuit?
    cond do
      # Already open - pain confirms our decision
      state.state == :open ->
        reinforce_open_decision(new_state, signal)
      
      # Immediate pain threshold exceeded
      pain_metrics.max_intensity >= state.pain_threshold ->
        Logger.warning("Circuit breaker #{state.name} opening due to pain intensity: #{pain_metrics.max_intensity}")
        transition_to_open(new_state, {:algedonic_pain, pain_metrics})
      
      # Sustained moderate pain
      pain_metrics.sustained_pain > 0.6 and pain_metrics.signal_count >= 3 ->
        Logger.warning("Circuit breaker #{state.name} opening due to sustained pain")
        transition_to_open(new_state, {:sustained_pain, pain_metrics})
      
      # Rapid pain escalation
      pain_metrics.escalation_rate > 0.5 ->
        Logger.warning("Circuit breaker #{state.name} opening due to rapid pain escalation")
        transition_to_open(new_state, {:pain_escalation, pain_metrics})
      
      # Not enough pain to act, but remember it
      true ->
        new_state
    end
  end

  # PAIN METRICS CALCULATION - Understanding Patterns of Suffering
  defp calculate_pain_metrics(signals, _state) do
    case signals do
      [] -> 
        %{
          max_intensity: 0.0,
          avg_intensity: 0.0,
          signal_count: 0,
          sustained_pain: 0.0,
          escalation_rate: 0.0
        }
      
      _ ->
        intensities = Enum.map(signals, & &1.intensity)
        
        # Time-weighted average for sustained pain
        now = System.monotonic_time(:millisecond)
        weighted_sum = signals
          |> Enum.map(fn s -> 
            age_ms = now - s.timestamp
            weight = :math.exp(-age_ms / @pain_decay_half_life_ms)
            s.intensity * weight
          end)
          |> Enum.sum()
        
        # Escalation detection
        escalation = if length(signals) >= 2 do
          [newest | rest] = signals
          oldest = List.last(rest) || newest
          time_diff = max(1, newest.timestamp - oldest.timestamp)
          (newest.intensity - oldest.intensity) / (time_diff / 1000)
        else
          0.0
        end
        
        %{
          max_intensity: Enum.max(intensities),
          avg_intensity: Enum.sum(intensities) / length(intensities),
          signal_count: length(signals),
          sustained_pain: weighted_sum / length(signals),
          escalation_rate: max(0.0, escalation)
        }
    end
  end

  # PAIN LEARNING - The System Remembers
  defp update_pain_learning(metrics, learning_data) do
    # Track pain patterns for future prediction
    pain_entry = {
      System.monotonic_time(:millisecond),
      metrics
    }
    
    :ets.insert(learning_data.pain_table, pain_entry)
    
    # Clean old entries
    cutoff = System.monotonic_time(:millisecond) - @pain_history_retention_ms
    :ets.select_delete(learning_data.pain_table, [
      {{:"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])
    
    # Update correlation strength (will be used in Phase 2)
    %{learning_data | correlation_strength: calculate_correlation_strength(learning_data)}
  end

  # CORRELATION STRENGTH - Learning Pain Patterns
  defp calculate_correlation_strength(learning_data) do
    # TODO: Implement ML-based correlation in Phase 3
    # For now, simple heuristic
    recent_entries = :ets.tab2list(learning_data.pain_table)
      |> Enum.take(-10)
      |> Enum.map(fn {_, metrics} -> metrics end)
    
    case recent_entries do
      [] -> 0.0
      entries ->
        # High correlation if pain consistently precedes failures
        avg_intensity = entries
          |> Enum.map(& &1.max_intensity)
          |> Enum.sum()
          |> Kernel./(length(entries))
        
        min(1.0, avg_intensity * 1.2)  # Boost correlation for consistent pain
    end
  end

  # DEPENDENT SERVICE CHECK - Do We Protect This Service?
  defp dependent_service?(source, state) do
    # Check if the source is a known dependent service
    # This could be expanded with a proper dependency graph
    case {source, state.name} do
      # Common patterns: database depends on connection pool
      {:database, :connection_pool} -> true
      {:api_gateway, :auth_service} -> true
      {:web_server, :database} -> true
      # Service-specific dependencies could be configured
      _ -> 
        # Check if explicitly configured as dependent
        dependent_services = Application.get_env(:autonomous_opponent_core, :circuit_dependencies, %{})
        source in Map.get(dependent_services, state.name, [])
    end
  end

  # PROTECTED SERVICE CHECK - Is This Under Our Protection?
  defp protected_service?(source, state) do
    # Services that this circuit breaker explicitly protects
    case state.name do
      :external_api_breaker -> source in [:openai, :anthropic, :google_ai]
      :database_breaker -> source in [:postgres, :redis, :elasticsearch]
      :messaging_breaker -> source in [:amqp, :kafka, :pubsub]
      _ ->
        # Check configuration for additional protected services
        protected = Application.get_env(:autonomous_opponent_core, :protected_services, %{})
        source in Map.get(protected, state.name, [])
    end
  end

  # AMBIENT PAIN RECORDING - Even Distant Pain Teaches
  defp record_ambient_pain(signal, state) do
    # Track all pain for system-wide learning
    :telemetry.execute(
      [:circuit_breaker, :ambient_pain],
      %{intensity: signal.intensity},
      %{
        name: state.name,
        source: signal.source,
        metric: signal.metric
      }
    )
  end

  # REINFORCE OPEN DECISION - Pain Validates Our Protection
  defp reinforce_open_decision(state, signal) do
    # Reset recovery timer when pain confirms we should stay open
    if signal.intensity > 0.7 do
      %{state | last_failure_time: System.monotonic_time(:millisecond)}
    else
      state
    end
  end

  # Private functions

  defp handle_success(state) do
    update_metrics(state, :success)

    # Reset failure count on success
    %{state | failure_count: 0, success_count: state.success_count + 1}
  end

  # WISDOM: Failure handling - counting strikes before you're out
  # Each failure increments the count, bringing us closer to opening. The
  # threshold (default 5) gives services multiple chances - everyone has bad
  # moments. But persistent failure indicates systemic issues requiring protection.
  # Recording last_failure_time enables recovery timeout. Time heals all wounds.
  defp handle_failure(state, error) do
    new_failure_count = state.failure_count + 1
    update_metrics(state, :failure)

    new_state = %{
      state
      | failure_count: new_failure_count,
        last_failure_time: System.monotonic_time(:millisecond)
    }

    # WISDOM: Threshold check - the breaking point
    # When failures reach threshold, we break the circuit. This protects both
    # the failing service (gives it space to recover) and calling services
    # (fail fast instead of waiting). It's protective isolation, not punishment.
    if new_failure_count >= state.failure_threshold do
      transition_to_open(new_state, error)
    else
      new_state
    end
  end

  # WISDOM: Opening the circuit - the moment of protection
  # Opening the circuit is an act of compassion - we protect both the failing
  # service and its dependents. The algedonic pain signal is crucial - it tells
  # the VSM that something hurts. This isn't just logging, it's the system
  # feeling pain and responding. Beer's insight: organisms that can't feel pain
  # can't protect themselves.
  defp transition_to_open(state, reason) do
    # Log the opening with appropriate severity
    case reason do
      {:emergency_pain, _} ->
        Logger.error("EMERGENCY: Circuit breaker #{state.name} forced open by emergency pain signal")
      {:algedonic_pain, metrics} ->
        Logger.warning("Circuit breaker #{state.name} opening due to pain (intensity: #{metrics.max_intensity})")
        # Track pain-triggered openings for learning
        :ets.update_counter(state.metrics_table, :pain_triggered_opens, 1)
      _ ->
        Logger.warning("Circuit breaker #{state.name} opening due to: #{inspect(reason)}")
    end

    # WISDOM: Algedonic pain - the system's cry for help
    # This pain signal triggers visceral response throughout the VSM. S5 feels
    # this immediately, bypassing normal channels. It's the difference between
    # knowing about pain intellectually and feeling it directly.
    EventBus.publish(:algedonic_pain, %{
      source: :circuit_breaker,
      name: state.name,
      severity: :high,
      reason: reason,
      timestamp: System.monotonic_time(:millisecond)
    })
    
    # Also publish specific circuit breaker event for metrics
    EventBus.publish(:circuit_breaker_opened, %{
      name: state.name,
      reason: reason,
      timestamp: System.monotonic_time(:millisecond)
    })

    # Record state transition for learning
    record_state_transition(state, :open)

    %{state | state: :open, half_open_test_in_progress: false}
  end

  defp transition_to_half_open(state) do
    Logger.info("Circuit breaker #{state.name} transitioning to half-open")

    EventBus.publish(:circuit_breaker_half_open, %{
      name: state.name,
      recovery_time_ms: state.recovery_time_ms
    })

    record_state_transition(state, :half_open)

    %{state | state: :half_open, half_open_test_in_progress: false}
  end

  # WISDOM: Closing the circuit - the joy of recovery
  # Closing the circuit after successful half-open test is a moment of systemic
  # joy. The algedonic pleasure signal reinforces the healing. This isn't
  # anthropomorphism - it's cybernetic learning. Systems that feel pleasure
  # when healing repeat behaviors that lead to healing. Beer understood:
  # pain teaches what to avoid, pleasure teaches what to seek.
  defp transition_to_closed(state) do
    Logger.info("Circuit breaker #{state.name} closing - service recovered")

    # WISDOM: Algedonic pleasure - celebrating recovery
    # This pleasure signal tells the VSM something good happened. S5 learns
    # from this - whatever actions led to recovery should be remembered and
    # repeated. It's positive reinforcement at the system level.
    EventBus.publish(:algedonic_pleasure, %{
      source: :circuit_breaker,
      name: state.name,
      reason: :service_recovered,
      timestamp: System.monotonic_time(:millisecond)
    })
    
    # Also publish specific circuit breaker event for metrics
    EventBus.publish(:circuit_breaker_closed, %{
      name: state.name,
      timestamp: System.monotonic_time(:millisecond)
    })

    record_state_transition(state, :closed)

    %{
      state
      | state: :closed,
        # Forgive all past failures
        failure_count: 0,
        half_open_test_in_progress: false
    }
  end

  # WISDOM: Recovery timing - knowing when to try again
  # Time-based recovery is simple but effective. After recovery_time_ms, we
  # try again. This automatic retry is crucial - manual intervention doesn't
  # scale. The monotonic_time ensures we're immune to clock adjustments.
  # Systems must self-heal, and time is often the best medicine.
  defp should_attempt_reset?(state) do
    case state.last_failure_time do
      # Never failed, no need to reset
      nil ->
        false

      last_failure ->
        current_time = System.monotonic_time(:millisecond)
        # Has enough time passed to try again?
        current_time - last_failure >= state.recovery_time_ms
    end
  end

  defp update_metrics(state, result) do
    :ets.update_counter(state.metrics_table, :total_calls, 1)

    case result do
      :success -> :ets.update_counter(state.metrics_table, :total_successes, 1)
      :failure -> :ets.update_counter(state.metrics_table, :total_failures, 1)
      :rejected -> :ets.update_counter(state.metrics_table, :total_failures, 1)
    end
  end

  defp get_metrics(state) do
    %{
      total_calls: :ets.lookup_element(state.metrics_table, :total_calls, 2),
      total_failures: :ets.lookup_element(state.metrics_table, :total_failures, 2),
      total_successes: :ets.lookup_element(state.metrics_table, :total_successes, 2),
      state_transitions: :ets.lookup_element(state.metrics_table, :state_transitions, 2)
    }
  end

  # WISDOM: State transition recording - learning from history
  # Every state change is recorded. This isn't just logging - it's organizational
  # memory. By tracking transitions, we can see patterns: Does this circuit break
  # often? At specific times? After certain events? The 100-transition limit
  # prevents memory bloat while preserving useful history. Those who forget
  # history are doomed to repeat outages.
  defp record_state_transition(state, new_state) do
    transition = %{
      from: state.state,
      to: new_state,
      timestamp: System.monotonic_time(:millisecond)
    }

    # Keep last 100 transitions - enough for pattern analysis
    :ets.update_element(
      state.metrics_table,
      :state_transitions,
      {2, fn transitions -> [transition | Enum.take(transitions, 99)] end}
    )
  end
end
