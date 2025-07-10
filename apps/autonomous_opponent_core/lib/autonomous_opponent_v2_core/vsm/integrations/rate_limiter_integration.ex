defmodule AutonomousOpponentV2Core.VSM.Integrations.RateLimiterIntegration do
  @moduledoc """
  Integrates distributed rate limiting with VSM subsystems.
  
  This module creates adaptive rate limiting based on VSM principles:
  - S1 Operations get highest capacity for variety absorption
  - S2 Coordination prevents oscillations through synchronized limits
  - S3 Control adjusts limits based on system health
  - S4 Intelligence learns patterns and predicts load
  - S5 Policy sets overall capacity constraints
  
  Implements Beer's cybernetic principles through dynamic variety attenuation.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Core.DistributedRateLimiter
  alias AutonomousOpponentV2Core.VSM.{S1, S2, S3, S4, S5}
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  
  @adaptation_interval 10_000  # 10 seconds
  @pain_threshold 0.8         # 80% utilization triggers pain
  @pleasure_threshold 0.3     # 30% utilization triggers pleasure
  
  defstruct [
    :rate_limiter,
    :subsystem_limits,
    :adaptation_enabled,
    :last_adaptation,
    :metrics,
    :timer_ref
  ]
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Check rate limit for a VSM subsystem with cybernetic feedback
  """
  def check_subsystem_limit(subsystem, identifier, cost \\ 1) do
    GenServer.call(__MODULE__, {:check_limit, subsystem, identifier, cost})
  end
  
  @doc """
  Get current limits and usage for all subsystems
  """
  def get_subsystem_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  @doc """
  Enable/disable adaptive rate limiting
  """
  def set_adaptation(enabled) when is_boolean(enabled) do
    GenServer.cast(__MODULE__, {:set_adaptation, enabled})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Subscribe to VSM events
    EventBus.subscribe(:vsm_algedonic_signal)
    EventBus.subscribe(:vsm_variety_overflow)
    EventBus.subscribe(:vsm_channel_capacity_change)
    EventBus.subscribe(:distributed_rate_limited)
    EventBus.subscribe(:distributed_rate_limit_allowed)
    
    # Initial subsystem limits based on VSM hierarchy
    subsystem_limits = %{
      s1: %{window_ms: 1_000, max_requests: 100, priority: 1.0},
      s2: %{window_ms: 1_000, max_requests: 50, priority: 0.8},
      s3: %{window_ms: 1_000, max_requests: 20, priority: 0.6},
      s4: %{window_ms: 60_000, max_requests: 100, priority: 0.4},
      s5: %{window_ms: 300_000, max_requests: 50, priority: 0.2}
    }
    
    state = %__MODULE__{
      rate_limiter: opts[:rate_limiter] || :vsm_rate_limiter,
      subsystem_limits: subsystem_limits,
      adaptation_enabled: opts[:adaptation_enabled] || true,
      last_adaptation: DateTime.utc_now(),
      metrics: init_metrics()
    }
    
    # Start adaptation timer
    {:ok, timer_ref} = :timer.send_interval(@adaptation_interval, :adapt_limits)
    
    {:ok, %{state | timer_ref: timer_ref}}
  end
  
  @impl true
  def handle_call({:check_limit, subsystem, identifier, cost}, _from, state) do
    # Map subsystem atom to rate limit rule
    rule_name = subsystem_to_rule(subsystem)
    
    # Check distributed rate limit
    result = DistributedRateLimiter.check_and_track(
      state.rate_limiter,
      identifier,
      rule_name,
      cost
    )
    
    # Update metrics
    state = update_metrics(state, subsystem, result)
    
    # Generate cybernetic feedback
    generate_feedback(subsystem, result, state)
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = Enum.map(state.subsystem_limits, fn {subsystem, limits} ->
      usage = Map.get(state.metrics, subsystem, %{allowed: 0, limited: 0})
      total = usage.allowed + usage.limited
      utilization = if limits.max_requests > 0 do
        total / limits.max_requests
      else
        0.0
      end
      
      {subsystem, %{
        limits: limits,
        usage: usage,
        utilization: utilization
      }}
    end)
    |> Map.new()
    
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_cast({:set_adaptation, enabled}, state) do
    Logger.info("VSM rate limiter adaptation #{if enabled, do: "enabled", else: "disabled"}")
    {:noreply, %{state | adaptation_enabled: enabled}}
  end
  
  @impl true
  def handle_info(:adapt_limits, state) do
    if state.adaptation_enabled do
      state = adapt_limits_based_on_vsm(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event_bus, %{type: :vsm_algedonic_signal, data: signal}}, state) do
    # React to algedonic signals
    state = case signal.type do
      :pain -> handle_pain_signal(signal, state)
      :pleasure -> handle_pleasure_signal(signal, state)
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event_bus, %{type: :vsm_variety_overflow, data: overflow}}, state) do
    # Tighten rate limits when variety overflow detected
    Logger.warning("VSM variety overflow detected: #{inspect(overflow)}")
    
    subsystem = overflow.subsystem
    state = if Map.has_key?(state.subsystem_limits, subsystem) do
      update_in(state.subsystem_limits[subsystem].max_requests, &(round(&1 * 0.8)))
    else
      state
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event_bus, %{type: :vsm_channel_capacity_change, data: change}}, state) do
    # Adjust rate limits based on channel capacity changes
    state = adjust_limits_for_channel_capacity(change, state)
    {:noreply, state}
  end
  
  # Private functions
  
  defp init_metrics do
    %{
      s1: %{allowed: 0, limited: 0},
      s2: %{allowed: 0, limited: 0},
      s3: %{allowed: 0, limited: 0},
      s4: %{allowed: 0, limited: 0},
      s5: %{allowed: 0, limited: 0}
    }
  end
  
  defp subsystem_to_rule(subsystem) do
    case subsystem do
      :s1 -> :s1_operations
      :s2 -> :s2_coordination
      :s3 -> :s3_control
      :s4 -> :s4_intelligence
      :s5 -> :s5_policy
      _ -> :unknown
    end
  end
  
  defp update_metrics(state, subsystem, result) do
    case result do
      {:ok, _} ->
        update_in(state.metrics[subsystem].allowed, &(&1 + 1))
        
      {:error, :rate_limited, _} ->
        update_in(state.metrics[subsystem].limited, &(&1 + 1))
        
      _ ->
        state
    end
  end
  
  defp generate_feedback(subsystem, result, state) do
    case result do
      {:error, :rate_limited, usage} ->
        # Generate pain signal when rate limited
        intensity = calculate_pain_intensity(usage)
        
        EventBus.publish(:algedonic_pain, %{
          source: :rate_limiter_integration,
          subsystem: subsystem,
          severity: intensity_to_severity(intensity),
          reason: :rate_limit_exceeded,
          usage: usage,
          timestamp: DateTime.utc_now()
        })
        
      {:ok, usage} ->
        # Check if we should generate pleasure signal (underutilization)
        if usage.remaining > usage.max * (1 - @pleasure_threshold) do
          EventBus.publish(:algedonic_pleasure, %{
            source: :rate_limiter_integration,
            subsystem: subsystem,
            reason: :capacity_available,
            usage: usage,
            timestamp: DateTime.utc_now()
          })
        end
        
      _ ->
        :ok
    end
  end
  
  defp calculate_pain_intensity(%{current: current, max: max}) do
    min(1.0, current / max)
  end
  
  defp intensity_to_severity(intensity) when intensity >= 0.9, do: :critical
  defp intensity_to_severity(intensity) when intensity >= 0.7, do: :high
  defp intensity_to_severity(intensity) when intensity >= 0.5, do: :medium
  defp intensity_to_severity(_), do: :low
  
  defp adapt_limits_based_on_vsm(state) do
    # Get current system state from VSM subsystems
    system_health = get_system_health()
    
    # Calculate new limits based on VSM feedback
    new_limits = Enum.map(state.subsystem_limits, fn {subsystem, limits} ->
      metrics = Map.get(state.metrics, subsystem, %{allowed: 0, limited: 0})
      total_requests = metrics.allowed + metrics.limited
      rejection_rate = if total_requests > 0 do
        metrics.limited / total_requests
      else
        0.0
      end
      
      # Adaptive algorithm based on Beer's principles
      new_max = cond do
        # High rejection rate - system under stress, reduce variety
        rejection_rate > 0.2 ->
          round(limits.max_requests * 0.9)
          
        # Low utilization - system has spare capacity
        total_requests < limits.max_requests * 0.3 ->
          round(limits.max_requests * 1.1)
          
        # Optimal range - maintain current limits
        true ->
          limits.max_requests
      end
      
      # Apply system health factor
      new_max = round(new_max * system_health.capacity_factor)
      
      # Ensure minimum viable limits
      new_max = max(new_max, minimum_limit_for_subsystem(subsystem))
      
      {subsystem, %{limits | max_requests: new_max}}
    end)
    |> Map.new()
    
    # Update distributed rate limiter with new rules
    update_rate_limiter_rules(state.rate_limiter, new_limits)
    
    # Reset metrics for next interval
    %{state | 
      subsystem_limits: new_limits,
      metrics: init_metrics(),
      last_adaptation: DateTime.utc_now()
    }
  end
  
  defp get_system_health do
    # In a real implementation, this would query VSM subsystems
    # For now, return a mock health status
    %{
      s1_load: 0.7,
      s2_coordination: :stable,
      s3_resources: :adequate,
      s4_threats: :none,
      s5_compliance: :within_policy,
      capacity_factor: 1.0
    }
  end
  
  defp minimum_limit_for_subsystem(subsystem) do
    case subsystem do
      :s1 -> 10   # S1 needs minimum operational capacity
      :s2 -> 5    # S2 needs minimum coordination capacity
      :s3 -> 2    # S3 needs minimum control capacity
      :s4 -> 5    # S4 needs minimum intelligence capacity
      :s5 -> 1    # S5 needs minimum policy capacity
      _ -> 1
    end
  end
  
  defp update_rate_limiter_rules(rate_limiter, new_limits) do
    # This would update the distributed rate limiter with new rules
    # For now, just log the changes
    Logger.info("Updating VSM rate limits: #{inspect(new_limits)}")
    
    # In production, this would call:
    # DistributedRateLimiter.update_rules(rate_limiter, format_rules(new_limits))
  end
  
  defp handle_pain_signal(signal, state) do
    if signal.source != :rate_limiter_integration do
      # External pain signal - tighten limits
      subsystem = signal[:subsystem] || :s1
      
      if Map.has_key?(state.subsystem_limits, subsystem) do
        factor = case signal.severity do
          :critical -> 0.5
          :high -> 0.7
          :medium -> 0.85
          :low -> 0.95
          _ -> 1.0
        end
        
        update_in(state.subsystem_limits[subsystem].max_requests, &(round(&1 * factor)))
      else
        state
      end
    else
      state
    end
  end
  
  defp handle_pleasure_signal(signal, state) do
    if signal.source != :rate_limiter_integration do
      # External pleasure signal - relax limits slightly
      subsystem = signal[:subsystem] || :s1
      
      if Map.has_key?(state.subsystem_limits, subsystem) do
        update_in(state.subsystem_limits[subsystem].max_requests, &(round(&1 * 1.05)))
      else
        state
      end
    else
      state
    end
  end
  
  defp adjust_limits_for_channel_capacity(change, state) do
    # Adjust rate limits based on variety channel capacity
    # This ensures rate limits don't exceed channel capacity
    
    channel_map = %{
      "s1_to_s2" => {:s1, :s2},
      "s2_to_s3" => {:s2, :s3},
      "s3_to_s4" => {:s3, :s4},
      "s4_to_s5" => {:s4, :s5}
    }
    
    case Map.get(channel_map, change.channel_id) do
      {from_subsystem, _to_subsystem} ->
        # Ensure rate limit doesn't exceed channel capacity
        new_max = min(
          state.subsystem_limits[from_subsystem].max_requests,
          change.new_capacity
        )
        
        update_in(state.subsystem_limits[from_subsystem].max_requests, fn _ -> new_max end)
        
      nil ->
        state
    end
  end
end