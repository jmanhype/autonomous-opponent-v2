defmodule AutonomousOpponent.Core.CircuitBreaker do
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
  
  alias AutonomousOpponentV2.EventBus
  
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
    :metrics_table
  ]
  
  @impl true
  def init(opts) do
    # Create ETS table for metrics
    table_name = :"#{opts[:name]}_metrics"
    :ets.new(table_name, [:named_table, :public, :set, {:write_concurrency, true}])
    
    # Initialize metrics
    :ets.insert(table_name, {:total_calls, 0})
    :ets.insert(table_name, {:total_failures, 0})
    :ets.insert(table_name, {:total_successes, 0})
    :ets.insert(table_name, {:state_transitions, []})
    
    state = %__MODULE__{
      name: opts[:name],
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      failure_threshold: opts[:failure_threshold] || 5,
      recovery_time_ms: opts[:recovery_time_ms] || 60_000,
      timeout_ms: opts[:timeout_ms] || 5_000,
      half_open_test_in_progress: false,
      metrics_table: table_name
    }
    
    # Publish initialization event
    EventBus.publish(:circuit_breaker_initialized, %{
      name: state.name,
      config: %{
        failure_threshold: state.failure_threshold,
        recovery_time_ms: state.recovery_time_ms,
        timeout_ms: state.timeout_ms
      }
    })
    
    {:ok, state}
  end
  
  # WISDOM: Closed state handler - normal operation with vigilance
  # When closed, we trust but verify. Execute the function but watch for failures.
  # Task.async gives us timeout control - critical for circuit breakers. Without
  # timeouts, slow services become service denials. The try/rescue/catch ensures
  # we capture ALL failure modes, not just exceptions. Every failure is data.
  @impl true
  def handle_call({:call, fun}, from, %{state: :closed} = state) do
    # Circuit is closed, execute the function with timeout protection
    task = Task.async(fn -> 
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
  def handle_call({:call, fun}, from, %{state: :half_open, half_open_test_in_progress: false} = state) do
    # Half-open state - allow one test call
    new_state = %{state | half_open_test_in_progress: true}
    
    # Execute the test call with same vigilance as closed state
    task = Task.async(fn -> 
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
  
  def handle_call({:call, _fun}, _from, %{state: :half_open, half_open_test_in_progress: true} = state) do
    # Another call while test is in progress
    {:reply, {:error, :circuit_half_open_busy}, state}
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
    new_state = %{state | 
      state: :closed,
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
  
  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def handle_info(_info, state) do
    {:noreply, state}
  end
  
  # Private functions
  
  defp handle_success(state) do
    update_metrics(state, :success)
    
    # Reset failure count on success
    %{state | 
      failure_count: 0,
      success_count: state.success_count + 1
    }
  end
  
  # WISDOM: Failure handling - counting strikes before you're out
  # Each failure increments the count, bringing us closer to opening. The
  # threshold (default 5) gives services multiple chances - everyone has bad
  # moments. But persistent failure indicates systemic issues requiring protection.
  # Recording last_failure_time enables recovery timeout. Time heals all wounds.
  defp handle_failure(state, error) do
    new_failure_count = state.failure_count + 1
    update_metrics(state, :failure)
    
    new_state = %{state | 
      failure_count: new_failure_count,
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
    Logger.warn("Circuit breaker #{state.name} opening due to: #{inspect(reason)}")
    
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
    
    # Record state transition for learning
    record_state_transition(state, :open)
    
    %{state | 
      state: :open,
      half_open_test_in_progress: false
    }
  end
  
  defp transition_to_half_open(state) do
    Logger.info("Circuit breaker #{state.name} transitioning to half-open")
    
    EventBus.publish(:circuit_breaker_half_open, %{
      name: state.name,
      recovery_time_ms: state.recovery_time_ms
    })
    
    record_state_transition(state, :half_open)
    
    %{state | 
      state: :half_open,
      half_open_test_in_progress: false
    }
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
    
    record_state_transition(state, :closed)
    
    %{state | 
      state: :closed,
      failure_count: 0,  # Forgive all past failures
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
      nil -> false  # Never failed, no need to reset
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
    :ets.update_element(state.metrics_table, :state_transitions, 
      {2, fn transitions -> [transition | Enum.take(transitions, 99)] end})
  end
end