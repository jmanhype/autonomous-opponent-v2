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
    :health_metrics
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
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to control commands and external requests
    EventBus.subscribe(:external_requests)
    EventBus.subscribe(:s3_control)
    EventBus.subscribe(:s5_policy)  # Policy constraints
    
    # Start health monitoring
    Process.send_after(self(), :report_health, 1000)
    
    state = %__MODULE__{
      circuit_breaker: nil,
      rate_limiter: nil,
      operation_workers: [],  # Initialize as empty list for now
      variety_buffer: :queue.new(),
      current_load: 0,
      control_mode: :normal,
      health_metrics: %{
        processed: 0,
        rejected: 0,
        failed: 0,
        latency_avg: 0
      }
    }
    
    Logger.info("S1 Operations online - ready to absorb variety")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:process, request}, _from, state) do
    start_time = System.monotonic_time()
    
    # First line of defense: Rate limiting (variety attenuation)
    case RateLimiter.consume(:s1_rate_limiter, 1) do
      {:ok, _tokens_remaining} ->
        # Second line: Circuit breaker (system protection)
        result = CircuitBreaker.call(:s1_circuit_breaker, fn ->
          do_process_request(request, state)
        end)
        
        # Update metrics
        latency = System.monotonic_time() - start_time
        new_state = update_health_metrics(state, result, latency)
        
        # Check if we're in pain
        check_pain_threshold(new_state)
        
        {:reply, result, new_state}
        
      {:error, :rate_limited} ->
        # Too much variety - attenuate
        new_state = increment_rejected(state)
        
        # Report variety overload
        if state.health_metrics.rejected > 100 do
          Algedonic.report_pain(:s1_operations, :rejection_rate, 0.9)
        end
        
        {:reply, {:error, :rate_limited}, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_state, _from, state) do
    operational_state = %{
      load: state.current_load,
      mode: state.control_mode,
      health: calculate_health_score(state),
      circuit_breaker: CircuitBreaker.get_state(:s1_circuit_breaker),
      rate_limiter: RateLimiter.get_state(:s1_rate_limiter),
      metrics: state.health_metrics
    }
    
    {:reply, operational_state, state}
  end
  
  @impl true
  def handle_call(:calculate_health, _from, state) do
    health_score = calculate_health_score(state)
    {:reply, health_score, state}
  end
  
  @impl true
  def handle_cast({:control_command, command}, state) do
    # S3 is telling us what to do - this CLOSES THE CONTROL LOOP
    Logger.info("S1 received control command: #{inspect(command.type)}")
    
    new_state = case command.type do
      :throttle ->
        # S3 says slow down
        # Update rate limiter if it exists
        if Process.whereis(:s1_rate_limiter) do
          RateLimiter.update_rate(:s1_rate_limiter, command.params.rate)
        end
        %{state | control_mode: :throttled}
        
      :circuit_break ->
        # S3 says stop accepting new work
        # Force open circuit breaker if it exists
        if Process.whereis(AutonomousOpponentV2Core.Core.CircuitBreaker) do
          CircuitBreaker.force_open(:s1_circuit_breaker)
        end
        %{state | control_mode: :protective}
        
      :resume_normal ->
        # S3 says we're good
        CircuitBreaker.force_close(:s1_circuit_breaker)
        RateLimiter.reset(:s1_rate_limiter)
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
  def handle_info(:report_health, state) do
    Process.send_after(self(), :report_health, 1000)
    
    health_score = calculate_health_score(state)
    
    # Report to monitoring
    EventBus.publish(:s1_health, %{health: health_score})
    
    # Check thresholds
    cond do
      health_score < 0.15 ->
        Algedonic.report_pain(:s1_operations, :health, 1.0 - health_score)
        
      health_score > 0.9 ->
        Algedonic.report_pleasure(:s1_operations, :performance, health_score)
        
      true ->
        :ok
    end
    
    {:noreply, state}
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
  
  defp check_pain_threshold(state) do
    health = calculate_health_score(state)
    
    cond do
      health < 0.15 ->
        Algedonic.report_pain(:s1_operations, :health_critical, 1.0 - health)
        
      state.current_load > 0.85 ->
        Algedonic.report_pain(:s1_operations, :overload, state.current_load)
        
      true ->
        :ok
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