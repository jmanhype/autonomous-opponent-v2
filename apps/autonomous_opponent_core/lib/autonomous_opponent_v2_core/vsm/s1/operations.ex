defmodule AutonomousOpponentV2Core.VSM.S1.Operations do
  @moduledoc """
  System 1: Operations - The muscles and sensory organs of the VSM.
  
  This is where the rubber meets the road. S1 DOES THINGS.
  It absorbs environmental variety using CircuitBreaker and RateLimiter
  as integrated components, not isolated modules.
  
  Key responsibilities:
  - Absorb external variety (using RateLimiter)
  - Protect system stability (using CircuitBreaker)
  - Execute control commands from S3
  - Report operational state to S2
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Core.{CircuitBreaker, RateLimiter}
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: Algedonic
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  
  defstruct [
    :circuit_breaker,
    :rate_limiter,
    :operation_workers,
    :variety_buffer,
    :current_load,
    :control_mode,
    :health_metrics,
    :variety_tracker,
    :system_capacity,
    :request_history,
    :pattern_frequencies,
    :entropy_window,
    :logical_clock,
    :event_log,
    :event_order
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def process_request(request) do
    GenServer.call(__MODULE__, {:process, request})
  end
  
  def execute_control_command(command) do
    GenServer.cast(__MODULE__, {:control_command, command})
  end
  
  def get_operational_state do
    GenServer.call(__MODULE__, :get_state)
  end
  
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end
  
  def calculate_health do
    GenServer.call(__MODULE__, :calculate_health)
  end

  def get_variety_metrics do
    GenServer.call(__MODULE__, :get_variety_metrics)
  end

  def get_system_capacity do
    GenServer.call(__MODULE__, :get_system_capacity)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to control commands and external requests
    EventBus.subscribe(:external_requests)
    EventBus.subscribe(:s3_control)
    EventBus.subscribe(:s5_policy)  # Policy constraints
    
    # Start our own circuit breaker and rate limiter
    {:ok, circuit_breaker} = CircuitBreaker.start_link(
      name: :"s1_circuit_breaker_#{System.unique_integer([:positive])}",
      failure_threshold: 5,
      recovery_time_ms: 60_000,
      timeout_ms: 5_000
    )
    
    {:ok, rate_limiter} = RateLimiter.start_link(
      name: :"s1_rate_limiter_#{System.unique_integer([:positive])}",
      bucket_size: 100,
      refill_rate: 10,
      refill_interval_ms: 100
    )
    
    # Start health monitoring
    Process.send_after(self(), :report_health, 1000)
    Process.send_after(self(), :measure_system_resources, 5000)
    Process.send_after(self(), :calculate_entropy, 2000)
    
    state = %__MODULE__{
      circuit_breaker: circuit_breaker,
      rate_limiter: rate_limiter,
      operation_workers: [],  # Initialize as empty list for now
      variety_buffer: :queue.new(),
      current_load: 0,
      control_mode: :normal,
      health_metrics: %{
        processed: 0,
        rejected: 0,
        failed: 0,
        latency_avg: 0,
        memory_usage: 0,
        cpu_usage: 0,
        io_wait: 0
      },
      variety_tracker: %{
        request_types: %{},
        error_patterns: %{},
        timing_patterns: [],
        data_shapes: %{},
        source_addresses: %{}
      },
      system_capacity: %{
        max_entropy: 10.0,  # bits - will be calibrated
        current_entropy: 0.0,
        cpu_cores: System.schedulers_online(),
        memory_limit: get_memory_limit(),
        io_capacity: 1000,  # operations per second
        theoretical_max_requests: 10000  # will be adjusted based on measurements
      },
      request_history: :queue.new(),
      pattern_frequencies: %{},
      entropy_window: [],  # sliding window of entropy measurements
      # Hybrid timestamp tracking (following design principles)
      logical_clock: 0,
      event_log: %{},  # content-hash => event data
      event_order: []   # ordered list of content hashes
    }
    
    Logger.info("S1 Operations online - ready to absorb variety")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:process, request}, _from, state) do
    start_time = System.monotonic_time()
    
    # Track variety before processing
    state_with_variety = track_request_variety(state, request)
    
    # Check if variety exceeds capacity
    variety_ratio = calculate_variety_ratio(state_with_variety)
    
    # Implement real variety attenuation based on capacity
    cond do
      variety_ratio > 0.95 ->
        # System overwhelmed - emergency attenuation
        new_state = increment_rejected(state_with_variety)
        Algedonic.report_pain(:s1_operations, :variety_overload, variety_ratio)
        {:reply, {:error, :variety_overload}, new_state}
        
      variety_ratio > 0.8 ->
        # High variety - selective attenuation
        if should_attenuate_request(request, state_with_variety) do
          new_state = increment_rejected(state_with_variety)
          {:reply, {:error, :attenuated}, new_state}
        else
          process_with_protection(request, state_with_variety, start_time)
        end
        
      true ->
        # Normal processing
        process_with_protection(request, state_with_variety, start_time)
    end
  end
  
  @impl true
  def handle_call(:get_state, _from, state) do
    operational_state = %{
      load: calculate_real_load(state),
      mode: state.control_mode,
      health: calculate_health_score(state),
      circuit_breaker: if state.circuit_breaker do
        CircuitBreaker.get_state(state.circuit_breaker)
      else
        %{state: :unknown, metrics: %{}}
      end,
      rate_limiter: if state.rate_limiter do
        RateLimiter.get_state(state.rate_limiter)
      else
        %{tokens: 0, bucket_size: 0}
      end,
      metrics: state.health_metrics,
      variety: %{
        current_entropy: state.system_capacity.current_entropy,
        max_entropy: state.system_capacity.max_entropy,
        variety_ratio: calculate_variety_ratio(state)
      },
      capacity: state.system_capacity
    }
    
    {:reply, operational_state, state}
  end
  
  @impl true
  def handle_call(:calculate_health, _from, state) do
    health_score = calculate_health_score(state)
    {:reply, health_score, state}
  end

  @impl true
  def handle_call(:get_variety_metrics, _from, state) do
    metrics = %{
      entropy: state.system_capacity.current_entropy,
      max_entropy: state.system_capacity.max_entropy,
      variety_ratio: calculate_variety_ratio(state),
      request_diversity: calculate_request_diversity(state),
      pattern_frequencies: state.pattern_frequencies,
      attenuation_active: calculate_variety_ratio(state) > 0.8
    }
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:get_system_capacity, _from, state) do
    {:reply, state.system_capacity, state}
  end
  
  @impl true
  def handle_cast({:control_command, command}, state) do
    # S3 is telling us what to do - this CLOSES THE CONTROL LOOP
    Logger.info("S1 received control command: #{inspect(command.type)}")
    
    new_state = case command.type do
      :throttle ->
        # S3 says slow down
        # Update rate limiter if it exists
        if state.rate_limiter do
          RateLimiter.update_rate(state.rate_limiter, command.params.rate)
        end
        %{state | control_mode: :throttled}
        
      :circuit_break ->
        # S3 says stop accepting new work
        # Force open circuit breaker if it exists
        if state.circuit_breaker do
          CircuitBreaker.force_open(state.circuit_breaker)
        end
        %{state | control_mode: :protective}
        
      :resume_normal ->
        # S3 says we're good
        if state.circuit_breaker do
          CircuitBreaker.force_close(state.circuit_breaker)
        end
        if state.rate_limiter do
          RateLimiter.reset(state.rate_limiter)
        end
        %{state | control_mode: :normal}
        
      :emergency_stop ->
        # S5 or Algedonic says STOP EVERYTHING
        Algedonic.emergency_scream(:s1_operations, "EMERGENCY STOP COMMANDED")
        %{state | control_mode: :emergency_stop}
        
      _ ->
        Logger.warning("Unknown control command: #{inspect(command)}")
        state
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
  def handle_info({:event, :external_requests, requests}, state) do
    # Bulk variety absorption
    results = Enum.map(requests, fn request ->
      handle_call({:process, request}, nil, state)
    end)
    
    # Aggregate results and update state
    new_state = aggregate_bulk_results(results, state)
    
    # Report to S2 for coordination
    VarietyChannel.transmit(:s1_to_s2, %{
      volume: length(requests),
      success_rate: calculate_success_rate(results),
      current_load: new_state.current_load,
      timestamp: DateTime.utc_now()
    })
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :s5_policy, _policy_update}, state) do
    # Handle policy updates from S5
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :all_subsystems, _broadcast}, state) do
    # Handle system-wide broadcasts
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :s1_operations, control_data}, state) do
    # Handle control commands from S3 via variety channel
    Logger.info("S1 received control via variety channel: #{inspect(control_data.variety_type)}")
    
    if control_data.variety_type == :control do
      # Process each control command
      new_state = Enum.reduce(control_data.commands, state, fn command, acc_state ->
        {:noreply, updated_state} = handle_cast({:control_command, command}, acc_state)
        updated_state
      end)
      
      # Report back to S2 about control execution
      VarietyChannel.transmit(:s1_to_s2, %{
        control_executed: true,
        commands_processed: length(control_data.commands),
        emergency: control_data[:bypass_buffers] || false,
        timestamp: DateTime.utc_now()
      })
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:report_health, state) do
    Process.send_after(self(), :report_health, 1000)
    
    health_score = calculate_health_score(state)
    
    # Report to monitoring with real metrics
    EventBus.publish(:s1_health, %{
      health: health_score,
      variety_ratio: calculate_variety_ratio(state),
      system_load: calculate_real_load(state),
      entropy: state.system_capacity.current_entropy
    })
    
    # Check thresholds based on real measurements
    cond do
      health_score < 0.15 ->
        Algedonic.report_pain(:s1_operations, :health, 1.0 - health_score)
        
      health_score > 0.9 and calculate_variety_ratio(state) < 0.5 ->
        Algedonic.report_pleasure(:s1_operations, :performance, health_score)
        
      true ->
        :ok
    end
    
    {:noreply, state}
  end

  @impl true
  def handle_info(:measure_system_resources, state) do
    Process.send_after(self(), :measure_system_resources, 5000)
    
    # Measure real system resources
    new_metrics = measure_system_resources(state.health_metrics)
    new_capacity = update_system_capacity(state.system_capacity, new_metrics)
    
    new_state = %{state | 
      health_metrics: new_metrics,
      system_capacity: new_capacity
    }
    
    # Check resource-based pain signals
    if new_metrics.cpu_usage > 0.9 or new_metrics.memory_usage > 0.85 do
      Algedonic.report_pain(:s1_operations, :resource_exhaustion, 
        max(new_metrics.cpu_usage, new_metrics.memory_usage))
    end
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:calculate_entropy, state) do
    Process.send_after(self(), :calculate_entropy, 2000)
    
    # Calculate Shannon entropy from actual request patterns
    entropy = calculate_shannon_entropy(state.variety_tracker)
    
    # Update sliding window
    window = Enum.take([entropy | state.entropy_window], 30)
    avg_entropy = Enum.sum(window) / length(window)
    
    new_capacity = %{state.system_capacity | 
      current_entropy: avg_entropy,
      max_entropy: calibrate_max_entropy(state)
    }
    
    new_state = %{state | 
      system_capacity: new_capacity,
      entropy_window: window
    }
    
    # Report variety measurements
    VarietyChannel.transmit(:s1_variety_metrics, %{
      entropy: avg_entropy,
      max_entropy: new_capacity.max_entropy,
      variety_ratio: calculate_variety_ratio(new_state),
      timestamp: DateTime.utc_now()
    })
    
    {:noreply, new_state}
  end
  
  # Private Functions
  
  # Operation workers started in init
  
  defp do_process_request(request, state) do
    # This is where actual work happens
    # In reality, this would delegate to worker processes
    
    case state.control_mode do
      :emergency_stop ->
        if Application.get_env(:autonomous_opponent_core, :disable_algedonic_signals, false) do
          # Algedonic signals disabled - continue processing despite emergency stop
          {:ok, execute_operation(request)}
        else
          {:error, :emergency_stop}
        end
        
      :throttled ->
        # Reduced processing
        Process.sleep(10)
        {:ok, process_with_constraints(request)}
        
      _ ->
        # Normal processing
        {:ok, execute_operation(request)}
    end
  end
  
  defp process_with_constraints(request) do
    %{result: "processed_with_constraints", request: request}
  end
  
  defp execute_operation(request) do
    %{result: "processed", request: request}
  end
  
  # Circuit breaker handlers commented out (unused)
  # defp handle_circuit_open(reason) do
  #   Logger.warning("S1 Circuit breaker OPEN: #{inspect(reason)}")
  #   Algedonic.report_pain(:s1_operations, :circuit_breaker, 0.95)
  # end
  # 
  # defp handle_circuit_close(_reason) do
  #   Logger.info("S1 Circuit breaker closed - resuming normal operations")
  # end
  
  defp update_health_metrics(state, {:ok, _}, latency) do
    metrics = state.health_metrics
    new_metrics = %{metrics |
      processed: metrics.processed + 1,
      latency_avg: calculate_moving_average(metrics.latency_avg, latency)
    }
    
    %{state | 
      health_metrics: new_metrics,
      current_load: calculate_load(new_metrics)
    }
  end
  
  defp update_health_metrics(state, {:error, _}, _latency) do
    metrics = state.health_metrics
    new_metrics = %{metrics | failed: metrics.failed + 1}
    
    %{state | 
      health_metrics: new_metrics,
      current_load: calculate_load(new_metrics)
    }
  end
  
  defp increment_rejected(state) do
    metrics = state.health_metrics
    new_metrics = %{metrics | rejected: metrics.rejected + 1}
    %{state | health_metrics: new_metrics}
  end
  
  defp calculate_health_score(state) do
    metrics = state.health_metrics
    total = metrics.processed + metrics.rejected + metrics.failed
    
    if total == 0 do
      1.0
    else
      success_rate = metrics.processed / total
      rejection_penalty = metrics.rejected / total * 0.5
      failure_penalty = metrics.failed / total * 2.0
      
      max(0.0, success_rate - rejection_penalty - failure_penalty)
    end
  end
  
  defp calculate_load(metrics) do
    # Simple load calculation
    metrics.processed / 1000
  end

  # New real implementation functions

  defp get_memory_limit do
    # Get system memory limit in MB
    try do
      case :memsup.get_system_memory_data() do
        data when is_list(data) ->
          total_memory = Keyword.get(data, :total_memory, 0)
          div(total_memory, 1024 * 1024)
        _ ->
          # Try alternative method
          memory_data = :erlang.memory()
          total = Keyword.get(memory_data, :total, 0)
          div(total, 1024 * 1024)
      end
    rescue
      _ -> 4096  # Default 4GB if can't determine
    end
  end

  defp track_request_variety(state, request) do
    tracker = state.variety_tracker
    
    # Generate content-based ID (following design principles)
    content_hash = generate_content_hash(request)
    
    # Increment logical clock for hybrid timestamp
    new_logical_clock = state.logical_clock + 1
    
    # Create event record with hybrid timestamp
    event = %{
      content_hash: content_hash,
      logical_time: new_logical_clock,
      physical_time: System.system_time(:nanosecond),
      request: request,
      timestamp: DateTime.utc_now()  # For compatibility
    }
    
    # Extract variety dimensions from request
    request_type = extract_request_type(request)
    data_shape = extract_data_shape(request)
    source = extract_source_address(request)
    
    # Update frequency counts
    new_tracker = %{tracker |
      request_types: Map.update(tracker.request_types, request_type, 1, &(&1 + 1)),
      data_shapes: Map.update(tracker.data_shapes, data_shape, 1, &(&1 + 1)),
      source_addresses: Map.update(tracker.source_addresses, source, 1, &(&1 + 1)),
      timing_patterns: Enum.take([System.system_time(:millisecond) | tracker.timing_patterns], 1000)
    }
    
    # Update pattern frequencies for entropy calculation
    pattern = {request_type, data_shape}
    new_frequencies = Map.update(state.pattern_frequencies, pattern, 1, &(&1 + 1))
    
    # Add to event log with content-based key
    new_event_log = Map.put(state.event_log, content_hash, event)
    
    # Maintain event order (bounded to prevent memory issues)
    new_event_order = [content_hash | state.event_order] |> Enum.take(10000)
    
    # Add to request history (bounded queue)
    history = :queue.in({request, System.system_time()}, state.request_history)
    bounded_history = if :queue.len(history) > 10000 do
      {_, new_q} = :queue.out(history)
      new_q
    else
      history
    end
    
    %{state | 
      variety_tracker: new_tracker,
      pattern_frequencies: new_frequencies,
      request_history: bounded_history,
      logical_clock: new_logical_clock,
      event_log: new_event_log,
      event_order: new_event_order
    }
  end

  defp generate_content_hash(request) do
    # Generate deterministic content-based hash (following design principles)
    # This ensures same content always produces same ID
    request
    |> :erlang.term_to_binary([:deterministic])
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end
  
  defp extract_request_type(request) when is_map(request) do
    cond do
      Map.has_key?(request, :type) -> request.type
      Map.has_key?(request, :action) -> request.action
      Map.has_key?(request, :method) -> request.method
      true -> :unknown
    end
  end
  defp extract_request_type(_), do: :generic

  defp extract_data_shape(request) when is_map(request) do
    keys = Map.keys(request) |> Enum.sort() |> Enum.join(":")
    :crypto.hash(:md5, keys) |> Base.encode16(case: :lower) |> String.slice(0..7)
  end
  defp extract_data_shape(_), do: "unknown"

  defp extract_source_address(request) when is_map(request) do
    Map.get(request, :source, Map.get(request, :from, "internal"))
  end
  defp extract_source_address(_), do: "unknown"

  defp calculate_variety_ratio(state) do
    current = state.system_capacity.current_entropy
    max = state.system_capacity.max_entropy
    
    if max > 0 do
      min(1.0, current / max)
    else
      0.0
    end
  end

  defp should_attenuate_request(request, state) do
    # Intelligent attenuation based on request patterns
    request_type = extract_request_type(request)
    
    # Get frequency of this request type
    type_count = Map.get(state.variety_tracker.request_types, request_type, 0)
    total_requests = Enum.sum(Map.values(state.variety_tracker.request_types))
    
    if total_requests > 0 do
      frequency = type_count / total_requests
      
      # Attenuate high-frequency, low-priority requests
      case request_type do
        :health_check when frequency > 0.3 -> true
        :status when frequency > 0.4 -> true
        :ping when frequency > 0.2 -> true
        _ -> frequency > 0.6  # Attenuate any request type over 60% frequency
      end
    else
      false
    end
  end

  defp process_with_protection(request, state, start_time) do
    # First line of defense: Rate limiting
    rate_limiter_result = if state.rate_limiter do
      RateLimiter.consume(state.rate_limiter, 1)
    else
      {:ok, 100}  # Default to allowing if no rate limiter
    end
    
    case rate_limiter_result do
      {:ok, _tokens_remaining} ->
        # Second line: Circuit breaker
        result = if state.circuit_breaker do
          CircuitBreaker.call(state.circuit_breaker, fn ->
            do_process_request(request, state)
          end)
        else
          # No circuit breaker, process directly
          do_process_request(request, state)
        end
        
        # Update metrics with real timing
        latency = System.monotonic_time() - start_time
        new_state = update_health_metrics(state, result, latency)
        
        # Check if we're in pain based on real metrics
        check_pain_threshold(new_state)
        
        {:reply, result, new_state}
        
      {:error, :rate_limited} ->
        new_state = increment_rejected(state)
        
        # Report real rejection pain
        rejection_rate = state.health_metrics.rejected / 
          max(1, state.health_metrics.processed + state.health_metrics.rejected)
        
        if rejection_rate > 0.1 do
          Algedonic.report_pain(:s1_operations, :rejection_rate, rejection_rate)
        end
        
        {:reply, {:error, :rate_limited}, new_state}
    end
  end

  defp calculate_real_load(state) do
    # Combine multiple factors for real load calculation
    cpu_weight = 0.4
    memory_weight = 0.3
    io_weight = 0.2
    queue_weight = 0.1
    
    queue_depth = :queue.len(state.variety_buffer)
    queue_load = min(1.0, queue_depth / 1000)
    
    (state.health_metrics.cpu_usage * cpu_weight) +
    (state.health_metrics.memory_usage * memory_weight) +
    (state.health_metrics.io_wait * io_weight) +
    (queue_load * queue_weight)
  end

  defp calculate_shannon_entropy(variety_tracker) do
    # Calculate Shannon entropy H = -Σ(p_i * log2(p_i))
    
    # Combine all variety sources
    all_patterns = [
      Map.to_list(variety_tracker.request_types),
      Map.to_list(variety_tracker.data_shapes),
      Map.to_list(variety_tracker.source_addresses)
    ] |> List.flatten()
    
    if length(all_patterns) == 0 do
      0.0
    else
      # Calculate total occurrences
      total = all_patterns |> Enum.map(fn {_, count} -> count end) |> Enum.sum()
      
      if total == 0 do
        0.0
      else
        # Calculate entropy
        all_patterns
        |> Enum.map(fn {_, count} ->
          probability = count / total
          if probability > 0 do
            -probability * :math.log2(probability)
          else
            0.0
          end
        end)
        |> Enum.sum()
      end
    end
  end

  defp calculate_request_diversity(state) do
    # Calculate diversity as ratio of unique patterns to total
    unique_types = map_size(state.variety_tracker.request_types)
    unique_shapes = map_size(state.variety_tracker.data_shapes)
    unique_sources = map_size(state.variety_tracker.source_addresses)
    
    total_requests = state.health_metrics.processed + state.health_metrics.rejected
    
    if total_requests > 0 do
      (unique_types + unique_shapes + unique_sources) / (total_requests * 0.01)
    else
      0.0
    end
  end

  defp measure_system_resources(current_metrics) do
    # Get real CPU usage
    cpu_usage = try do
      case :cpu_sup.util() do
        usage when is_number(usage) -> usage / 100.0
        _ -> current_metrics.cpu_usage
      end
    rescue
      _ -> current_metrics.cpu_usage
    end
    
    # Get real memory usage
    memory_usage = try do
      case :memsup.get_memory_data() do
        data when is_list(data) ->
          total = Keyword.get(data, :total_memory, 1)
          free = Keyword.get(data, :free_memory, 0)
          if total > 0 do
            (total - free) / total
          else
            current_metrics.memory_usage
          end
        _ ->
          # Try alternative method using erlang:memory
          memory_info = :erlang.memory()
          total = Keyword.get(memory_info, :total, 1)
          system = Keyword.get(memory_info, :system, 0)
          processes = Keyword.get(memory_info, :processes, 0)
          used = system + processes
          if total > 0, do: used / total, else: current_metrics.memory_usage
      end
    rescue
      _ -> current_metrics.memory_usage
    end
    
    # Estimate I/O wait from scheduler utilization
    io_wait = estimate_io_wait()
    
    %{current_metrics |
      cpu_usage: cpu_usage,
      memory_usage: memory_usage,
      io_wait: io_wait
    }
  end

  defp estimate_io_wait do
    # Use scheduler utilization as proxy for I/O wait
    try do
      wall_time = :erlang.statistics(:scheduler_wall_time_all)
      
      active = case wall_time do
        data when is_list(data) ->
          data
          |> Enum.map(fn 
            {_, active, total} when total > 0 -> active / total
            _ -> 0.0
          end)
          |> Enum.sum()
        _ -> 0.0
      end
      
      schedulers = System.schedulers_online()
      avg_utilization = if schedulers > 0, do: active / schedulers, else: 0.0
      
      # Get CPU usage safely
      cpu_usage = case :cpu_sup.util() do
        {:ok, usage} -> usage / 100.0
        _ -> 0.0
      end
      
      # High utilization with low CPU suggests I/O wait
      max(0.0, avg_utilization - cpu_usage)
    rescue
      _ -> 0.0
    end
  end

  defp update_system_capacity(capacity, metrics) do
    # Adjust capacity based on actual resource availability
    cpu_capacity = (1.0 - metrics.cpu_usage) * capacity.cpu_cores * 1000
    memory_capacity = (1.0 - metrics.memory_usage) * capacity.memory_limit * 10
    io_capacity = (1.0 - metrics.io_wait) * 1000
    
    theoretical_max = min(cpu_capacity, min(memory_capacity, io_capacity))
    
    %{capacity | theoretical_max_requests: round(theoretical_max)}
  end

  defp calibrate_max_entropy(state) do
    # Calibrate maximum entropy based on system capacity and historical data
    
    # Base entropy on number of unique patterns we can handle
    unique_patterns = map_size(state.pattern_frequencies)
    
    # Theoretical maximum based on capacity
    capacity_factor = :math.log2(state.system_capacity.theoretical_max_requests + 1)
    
    # Historical maximum from sliding window
    historical_max = if length(state.entropy_window) > 0 do
      Enum.max(state.entropy_window)
    else
      0.0
    end
    
    # Take weighted combination
    base_entropy = :math.log2(unique_patterns + 1)
    
    max(base_entropy, historical_max * 1.2) * min(1.0, capacity_factor / 10)
  end
  
  defp check_pain_threshold(state) do
    health = calculate_health_score(state)
    variety_ratio = calculate_variety_ratio(state)
    real_load = calculate_real_load(state)
    
    cond do
      # Critical health based on real metrics
      health < 0.15 ->
        Algedonic.report_pain(:s1_operations, :health_critical, 1.0 - health)
        
      # Variety overload - too much entropy
      variety_ratio > 0.9 ->
        Algedonic.report_pain(:s1_operations, :variety_overload, variety_ratio)
        
      # System overload based on real resource usage
      real_load > 0.85 ->
        Algedonic.report_pain(:s1_operations, :system_overload, real_load)
        
      # Memory pressure
      state.health_metrics.memory_usage > 0.9 ->
        Algedonic.report_pain(:s1_operations, :memory_pressure, state.health_metrics.memory_usage)
        
      # High rejection rate indicates capacity issues
      rejection_rate(state) > 0.2 ->
        Algedonic.report_pain(:s1_operations, :high_rejection, rejection_rate(state))
        
      true ->
        :ok
    end
  end
  
  defp rejection_rate(state) do
    total = state.health_metrics.processed + state.health_metrics.rejected
    if total > 0 do
      state.health_metrics.rejected / total
    else
      0.0
    end
  end
  
  defp aggregate_bulk_results(results, state) do
    # Aggregate state from bulk processing
    successful = Enum.count(results, fn {_, res} -> 
      match?({:ok, {:ok, _}}, res) 
    end)
    
    failed = Enum.count(results, fn {_, res} ->
      match?({:ok, {:error, _}}, res) or match?(nil, res)
    end)
    
    metrics = state.health_metrics
    new_metrics = %{metrics |
      processed: metrics.processed + successful,
      failed: metrics.failed + failed
    }
    
    %{state | 
      health_metrics: new_metrics,
      current_load: calculate_load(new_metrics)
    }
  end
  
  defp calculate_success_rate(results) do
    total = length(results)
    success = Enum.count(results, fn {_, result, _} -> 
      match?({:ok, _}, elem(result, 0))
    end)
    
    if total > 0, do: success / total, else: 1.0
  end
  
  defp calculate_moving_average(current, new_value) do
    current * 0.9 + new_value * 0.1
  end

  # Worker system commented out (unused)
  # defp start_operation_workers do
  #   # Start worker processes for parallel request processing
  #   worker_count = System.schedulers_online()
  #   
  #   for i <- 1..worker_count do
  #     Task.start_link(fn ->
  #       Process.register(self(), :"s1_worker_#{i}")
  #       operation_worker_loop()
  #     end)
  #   end
  # end

  # defp operation_worker_loop do
  #   receive do
  #     {:process_request, request, from} ->
  #       result = execute_operation(request)
  #       GenServer.reply(from, result)
  #       operation_worker_loop()
  #     
  #     :shutdown ->
  #       :ok
  #       
  #     _ ->
  #       operation_worker_loop()
  #   end
  # end
end