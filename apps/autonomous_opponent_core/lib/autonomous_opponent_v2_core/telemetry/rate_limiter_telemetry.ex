defmodule AutonomousOpponentV2Core.Telemetry.RateLimiterTelemetry do
  @moduledoc """
  Comprehensive telemetry for distributed rate limiting.
  
  Tracks:
  - Rate limit checks (allowed/denied)
  - Redis operations (latency, errors)
  - Circuit breaker state changes
  - Fallback usage
  - VSM integration metrics
  - Security audit events
  """
  
  require Logger
  
  @metrics [
    # Rate limiter operation metrics
    {:counter, "rate_limiter.checks.total",
     event_name: [:distributed_rate_limiter, :check],
     measurement: :count,
     tags: [:rule, :result]},
     
    {:histogram, "rate_limiter.checks.duration",
     event_name: [:distributed_rate_limiter, :check],
     measurement: :duration,
     unit: {:native, :millisecond},
     tags: [:rule, :mode]},
     
    {:counter, "rate_limiter.violations.total",
     event_name: [:distributed_rate_limiter, :violation],
     measurement: :count,
     tags: [:rule, :severity]},
     
    # Redis operation metrics
    {:histogram, "redis.command.duration",
     event_name: [:autonomous_opponent, :redis, :command],
     measurement: :duration,
     unit: {:native, :millisecond},
     tags: [:operation, :success]},
     
    {:counter, "redis.errors.total",
     event_name: [:autonomous_opponent, :redis, :error],
     measurement: :count,
     tags: [:error_type]},
     
    {:gauge, "redis.pool.size",
     event_name: [:autonomous_opponent, :redis, :pool],
     measurement: :size},
     
    # Circuit breaker metrics
    {:counter, "circuit_breaker.trips.total",
     event_name: [:circuit_breaker, :trip],
     measurement: :count,
     tags: [:circuit, :reason]},
     
    {:counter, "circuit_breaker.state_changes.total",
     event_name: [:circuit_breaker, :state_change],
     measurement: :count,
     tags: [:circuit, :from_state, :to_state]},
     
    # Fallback metrics
    {:counter, "rate_limiter.fallback.usage",
     event_name: [:distributed_rate_limiter, :fallback],
     measurement: :count,
     tags: [:reason]},
     
    # VSM integration metrics
    {:counter, "vsm.rate_limiter.adaptations",
     event_name: [:vsm, :rate_limiter, :adaptation],
     measurement: :count,
     tags: [:subsystem, :direction]},
     
    {:gauge, "vsm.rate_limiter.limits",
     event_name: [:vsm, :rate_limiter, :limits],
     measurement: :limit,
     tags: [:subsystem]},
     
    {:histogram, "vsm.rate_limiter.utilization",
     event_name: [:vsm, :rate_limiter, :utilization],
     measurement: :percentage,
     unit: :percent,
     tags: [:subsystem]}
  ]
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
  
  def start_link(_opts) do
    # Attach telemetry handlers
    :ok = attach_handlers()
    
    # Return :ignore since this is not a process
    :ignore
  end
  
  @doc """
  Returns the list of metrics definitions for this module
  """
  def metrics, do: @metrics
  
  @doc """
  Attaches all telemetry handlers for rate limiting
  """
  def attach_handlers do
    handlers = [
      {[:distributed_rate_limiter, :check], &handle_rate_limit_check/4},
      {[:distributed_rate_limiter, :violation], &handle_violation/4},
      {[:distributed_rate_limiter, :stats], &handle_stats/4},
      {[:autonomous_opponent, :redis, :command], &handle_redis_command/4},
      {[:autonomous_opponent, :redis, :pipeline], &handle_redis_pipeline/4},
      {[:circuit_breaker, :call], &handle_circuit_breaker/4},
      {[:vsm, :rate_limiter, :adaptation], &handle_vsm_adaptation/4}
    ]
    
    Enum.each(handlers, fn {event, handler} ->
      :telemetry.attach(
        "#{__MODULE__}.#{Enum.join(event, ".")}",
        event,
        handler,
        nil
      )
    end)
  end
  
  # Handler functions
  
  defp handle_rate_limit_check(event, measurements, metadata, _config) do
    # Log check results
    result = if metadata.success, do: "allowed", else: "denied"
    mode = if Map.get(metadata, :fallback, false), do: "fallback", else: "redis"
    
    Logger.debug("Rate limit check: #{metadata.rule} - #{result} (#{mode})",
      measurements: measurements,
      metadata: metadata
    )
    
    # Emit custom metrics
    :telemetry.execute(
      [:distributed_rate_limiter, :check],
      %{count: 1, duration: measurements.duration},
      Map.merge(metadata, %{result: result, mode: mode})
    )
    
    # Track high utilization
    if usage = metadata[:usage] do
      utilization = usage.current / usage.max * 100
      
      if utilization > 80 do
        Logger.warning("High rate limit utilization: #{metadata.rule} at #{round(utilization)}%")
      end
    end
  end
  
  defp handle_violation(event, measurements, metadata, _config) do
    # Security audit for violations
    Logger.warning("Rate limit violation",
      rule: metadata.rule,
      identifier_hash: metadata.identifier_hash,
      node: metadata.node,
      context: metadata.context
    )
    
    # Track violation patterns
    :telemetry.execute(
      [:distributed_rate_limiter, :violation],
      %{count: 1},
      Map.merge(metadata, %{
        severity: calculate_violation_severity(metadata)
      })
    )
  end
  
  defp handle_stats(_event, measurements, metadata, _config) do
    # Periodic stats emission
    mode = measurements.mode
    
    Logger.info("Rate limiter stats",
      name: metadata.name,
      node: metadata.node,
      mode: mode,
      redis_calls: measurements.redis_calls,
      fallback_calls: measurements.fallback_calls,
      circuit_opens: measurements.circuit_opens
    )
    
    # Calculate fallback ratio
    total_calls = measurements.redis_calls + measurements.fallback_calls
    if total_calls > 0 do
      fallback_ratio = measurements.fallback_calls / total_calls * 100
      
      if fallback_ratio > 50 do
        Logger.warning("High fallback usage: #{round(fallback_ratio)}% of calls using fallback")
      end
    end
  end
  
  defp handle_redis_command(_event, measurements, metadata, _config) do
    # Track Redis latency
    if measurements.duration > 10_000_000 do  # 10ms in nanoseconds
      Logger.warning("Slow Redis command: #{inspect(metadata.metadata)} took #{measurements.duration / 1_000_000}ms")
    end
    
    # Track errors
    unless metadata.success do
      :telemetry.execute(
        [:autonomous_opponent, :redis, :error],
        %{count: 1},
        %{error_type: classify_redis_error(metadata)}
      )
    end
  end
  
  defp handle_redis_pipeline(_event, measurements, metadata, _config) do
    # Track pipeline performance
    commands_per_ms = metadata.metadata / (measurements.duration / 1_000_000)
    
    Logger.debug("Redis pipeline: #{metadata.metadata} commands, #{round(commands_per_ms)} cmds/ms")
  end
  
  defp handle_circuit_breaker(_event, measurements, metadata, _config) do
    if metadata.circuit == :redis_circuit do
      case metadata.result do
        {:error, :circuit_open} ->
          Logger.error("Redis circuit breaker open - falling back to local rate limiting")
          
          :telemetry.execute(
            [:distributed_rate_limiter, :fallback],
            %{count: 1},
            %{reason: :circuit_open}
          )
          
        {:ok, _} when metadata.state == :half_open ->
          Logger.info("Redis circuit breaker testing connection in half-open state")
          
        _ ->
          :ok
      end
    end
  end
  
  defp handle_vsm_adaptation(_event, measurements, metadata, _config) do
    Logger.info("VSM rate limit adaptation",
      subsystem: metadata.subsystem,
      direction: metadata.direction,
      old_limit: metadata.old_limit,
      new_limit: metadata.new_limit,
      reason: metadata.reason
    )
    
    # Emit metrics for limit changes
    :telemetry.execute(
      [:vsm, :rate_limiter, :limits],
      %{limit: metadata.new_limit},
      %{subsystem: metadata.subsystem}
    )
  end
  
  # Helper functions
  
  defp calculate_violation_severity(metadata) do
    usage = metadata[:usage] || %{}
    current = usage[:current] || 0
    max = usage[:max] || 1
    
    ratio = current / max
    
    cond do
      ratio > 2.0 -> :critical
      ratio > 1.5 -> :high
      ratio > 1.2 -> :medium
      true -> :low
    end
  end
  
  defp classify_redis_error(metadata) do
    case metadata[:error] do
      %Redix.ConnectionError{} -> :connection_error
      %Redix.Error{message: "NOSCRIPT" <> _} -> :script_not_found
      %Redix.Error{message: "OOM" <> _} -> :out_of_memory
      %Redix.Error{message: "LOADING" <> _} -> :loading
      %Redix.Error{} -> :command_error
      :timeout -> :timeout
      _ -> :unknown
    end
  end
  
  @doc """
  Emits a test event for each metric type (useful for testing dashboards)
  """
  def emit_test_events do
    # Rate limit check
    :telemetry.execute(
      [:distributed_rate_limiter, :check],
      %{count: 1, duration: 1_500_000},  # 1.5ms
      %{rule: :test_rule, result: "allowed", mode: "redis"}
    )
    
    # Redis command
    :telemetry.execute(
      [:autonomous_opponent, :redis, :command],
      %{duration: 500_000},  # 0.5ms
      %{operation: :eval, success: true}
    )
    
    # VSM adaptation
    :telemetry.execute(
      [:vsm, :rate_limiter, :adaptation],
      %{count: 1},
      %{
        subsystem: :s1,
        direction: :increase,
        old_limit: 100,
        new_limit: 110,
        reason: :low_utilization
      }
    )
    
    Logger.info("Test telemetry events emitted")
  end
end