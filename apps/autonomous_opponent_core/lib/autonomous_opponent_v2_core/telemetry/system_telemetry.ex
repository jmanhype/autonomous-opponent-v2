defmodule AutonomousOpponentV2Core.Telemetry.SystemTelemetry do
  @moduledoc """
  Central telemetry setup for the Autonomous Opponent system.
  
  Registers handlers, configures reporters, and provides a unified
  interface for system-wide observability.
  """
  
  require Logger
  
  @doc """
  Attaches all telemetry handlers for the system.
  """
  def setup do
    attach_consciousness_handlers()
    attach_vsm_handlers()
    attach_event_bus_handlers()
    attach_llm_handlers()
    attach_web_handlers()
    attach_system_handlers()
    
    Logger.info("Telemetry handlers attached successfully")
  end
  
  # Consciousness telemetry handlers
  defp attach_consciousness_handlers do
    events = [
      [:consciousness, :state_change],
      [:consciousness, :decision_made],
      [:consciousness, :reflection_completed],
      [:consciousness, :awareness_level_changed]
    ]
    
    :telemetry.attach_many(
      "consciousness-handlers",
      events,
      &handle_consciousness_event/4,
      nil
    )
  end
  
  # VSM telemetry handlers
  defp attach_vsm_handlers do
    # S1 Operations
    :telemetry.attach_many(
      "vsm-s1-handlers",
      [
        [:vsm, :s1, :operation, :start],
        [:vsm, :s1, :operation, :stop],
        [:vsm, :s1, :operation, :exception],
        [:vsm, :s1, :variety_absorbed]
      ],
      &handle_vsm_event/4,
      nil
    )
    
    # S2 Coordination
    :telemetry.attach_many(
      "vsm-s2-handlers",
      [
        [:vsm, :s2, :coordination, :start],
        [:vsm, :s2, :coordination, :stop],
        [:vsm, :s2, :anti_oscillation_triggered]
      ],
      &handle_vsm_event/4,
      nil
    )
    
    # S3 Control
    :telemetry.attach_many(
      "vsm-s3-handlers",
      [
        [:vsm, :s3, :control, :start],
        [:vsm, :s3, :control, :stop],
        [:vsm, :s3, :resource_allocated],
        [:vsm, :s3, :optimization_completed]
      ],
      &handle_vsm_event/4,
      nil
    )
    
    # S4 Intelligence
    :telemetry.attach_many(
      "vsm-s4-handlers",
      [
        [:vsm, :s4, :intelligence, :start],
        [:vsm, :s4, :intelligence, :stop],
        [:vsm, :s4, :environmental_scan],
        [:vsm, :s4, :threat_detected],
        [:vsm, :s4, :opportunity_identified]
      ],
      &handle_vsm_event/4,
      nil
    )
    
    # S5 Policy
    :telemetry.attach_many(
      "vsm-s5-handlers",
      [
        [:vsm, :s5, :policy, :start],
        [:vsm, :s5, :policy, :stop],
        [:vsm, :s5, :policy_updated],
        [:vsm, :s5, :constraint_violation]
      ],
      &handle_vsm_event/4,
      nil
    )
    
    # Algedonic
    :telemetry.attach_many(
      "vsm-algedonic-handlers",
      [
        [:vsm, :algedonic, :pain_signal],
        [:vsm, :algedonic, :pleasure_signal],
        [:vsm, :algedonic, :bypass_activated]
      ],
      &handle_vsm_event/4,
      nil
    )
  end
  
  # EventBus telemetry handlers
  defp attach_event_bus_handlers do
    events = [
      [:event_bus, :publish],
      [:event_bus, :subscribe],
      [:event_bus, :unsubscribe],
      [:event_bus, :broadcast],
      [:event_bus, :message_dropped]
    ]
    
    :telemetry.attach_many(
      "event-bus-handlers",
      events,
      &handle_event_bus_event/4,
      nil
    )
  end
  
  # LLM telemetry handlers
  defp attach_llm_handlers do
    events = [
      [:llm, :request, :start],
      [:llm, :request, :stop],
      [:llm, :request, :exception],
      [:llm, :cache, :hit],
      [:llm, :cache, :miss],
      [:llm, :token_usage],
      [:llm, :rate_limit],
      [:llm, :provider_switch]
    ]
    
    :telemetry.attach_many(
      "llm-handlers",
      events,
      &handle_llm_event/4,
      nil
    )
  end
  
  # Web telemetry handlers
  defp attach_web_handlers do
    events = [
      [:phoenix, :router_dispatch, :start],
      [:phoenix, :router_dispatch, :stop],
      [:phoenix, :live_view, :mount, :start],
      [:phoenix, :live_view, :mount, :stop],
      [:phoenix, :live_view, :handle_event, :start],
      [:phoenix, :live_view, :handle_event, :stop],
      [:phoenix, :live_component, :update, :start],
      [:phoenix, :live_component, :update, :stop]
    ]
    
    :telemetry.attach_many(
      "web-handlers",
      events,
      &handle_web_event/4,
      nil
    )
  end
  
  # System-wide telemetry handlers
  defp attach_system_handlers do
    events = [
      [:vm, :memory],
      [:vm, :total_run_queue_lengths],
      [:vm, :system_counts],
      [:system, :health_check],
      [:system, :circuit_breaker, :opened],
      [:system, :circuit_breaker, :closed],
      [:system, :rate_limit, :exceeded]
    ]
    
    :telemetry.attach_many(
      "system-handlers",
      events,
      &handle_system_event/4,
      nil
    )
  end
  
  # Handler implementations
  
  defp handle_consciousness_event([:consciousness, :state_change], measurements, metadata, _config) do
    Logger.info("Consciousness state changed", 
      from_state: metadata[:from_state],
      to_state: metadata[:to_state],
      duration: measurements[:duration]
    )
  end
  
  defp handle_consciousness_event([:consciousness, :decision_made], measurements, metadata, _config) do
    Logger.debug("Consciousness decision made",
      decision_type: metadata[:decision_type],
      confidence: measurements[:confidence],
      duration: measurements[:duration]
    )
  end
  
  defp handle_consciousness_event([:consciousness, :reflection_completed], measurements, metadata, _config) do
    Logger.info("Consciousness reflection completed",
      insights_count: measurements[:insights_count],
      duration: measurements[:duration]
    )
  end
  
  defp handle_consciousness_event([:consciousness, :awareness_level_changed], measurements, metadata, _config) do
    Logger.info("Consciousness awareness level changed",
      from_level: metadata[:from_level],
      to_level: metadata[:to_level],
      triggers: metadata[:triggers]
    )
  end
  
  defp handle_vsm_event(event, measurements, metadata, _config) do
    case event do
      [:vsm, subsystem, :operation, :start] ->
        Logger.debug("VSM #{subsystem} operation started",
          operation: metadata[:operation],
          input_variety: measurements[:input_variety]
        )
        
      [:vsm, subsystem, :operation, :stop] ->
        Logger.debug("VSM #{subsystem} operation completed",
          operation: metadata[:operation],
          duration: measurements[:duration],
          output_variety: measurements[:output_variety]
        )
        
      [:vsm, subsystem, :operation, :exception] ->
        Logger.error("VSM #{subsystem} operation failed",
          operation: metadata[:operation],
          error: metadata[:error],
          duration: measurements[:duration]
        )
        
      [:vsm, :s1, :variety_absorbed] ->
        Logger.info("VSM S1 variety absorbed",
          input_variety: measurements[:input_variety],
          absorbed_variety: measurements[:absorbed_variety],
          efficiency: measurements[:efficiency]
        )
        
      [:vsm, :s2, :anti_oscillation_triggered] ->
        Logger.warn("VSM S2 anti-oscillation triggered",
          oscillation_type: metadata[:oscillation_type],
          damping_factor: measurements[:damping_factor]
        )
        
      [:vsm, :s3, :resource_allocated] ->
        Logger.info("VSM S3 resource allocated",
          resource_type: metadata[:resource_type],
          amount: measurements[:amount],
          utilization: measurements[:utilization]
        )
        
      [:vsm, :s4, :threat_detected] ->
        Logger.warn("VSM S4 threat detected",
          threat_type: metadata[:threat_type],
          severity: measurements[:severity],
          confidence: measurements[:confidence]
        )
        
      [:vsm, :s4, :opportunity_identified] ->
        Logger.info("VSM S4 opportunity identified",
          opportunity_type: metadata[:opportunity_type],
          potential_value: measurements[:potential_value],
          confidence: measurements[:confidence]
        )
        
      [:vsm, :s5, :policy_updated] ->
        Logger.info("VSM S5 policy updated",
          policy_domain: metadata[:policy_domain],
          changes_count: measurements[:changes_count]
        )
        
      [:vsm, :s5, :constraint_violation] ->
        Logger.error("VSM S5 constraint violation",
          constraint_type: metadata[:constraint_type],
          violation_severity: measurements[:severity]
        )
        
      [:vsm, :algedonic, signal_type] when signal_type in [:pain_signal, :pleasure_signal] ->
        Logger.warn("VSM algedonic #{signal_type} received",
          source: metadata[:source],
          intensity: measurements[:intensity],
          bypass_activated: metadata[:bypass_activated]
        )
        
      _ ->
        Logger.debug("VSM event: #{inspect(event)}",
          measurements: measurements,
          metadata: metadata
        )
    end
  end
  
  defp handle_event_bus_event([:event_bus, action], measurements, metadata, _config) do
    case action do
      :publish ->
        Logger.debug("EventBus message published",
          topic: metadata[:topic],
          size: measurements[:message_size],
          subscriber_count: measurements[:subscriber_count]
        )
        
      :broadcast ->
        Logger.debug("EventBus broadcast completed",
          topic: metadata[:topic],
          recipients: measurements[:recipient_count],
          duration: measurements[:duration]
        )
        
      :message_dropped ->
        Logger.warn("EventBus message dropped",
          topic: metadata[:topic],
          reason: metadata[:reason],
          queue_size: measurements[:queue_size]
        )
        
      _ ->
        Logger.debug("EventBus #{action}",
          topic: metadata[:topic] || "N/A",
          measurements: measurements
        )
    end
  end
  
  defp handle_llm_event([:llm, :request, :start], measurements, metadata, _config) do
    Logger.debug("LLM request started",
      provider: metadata[:provider],
      model: metadata[:model],
      prompt_tokens: measurements[:prompt_tokens]
    )
  end
  
  defp handle_llm_event([:llm, :request, :stop], measurements, metadata, _config) do
    Logger.info("LLM request completed",
      provider: metadata[:provider],
      model: metadata[:model],
      duration: measurements[:duration],
      total_tokens: measurements[:total_tokens],
      cost: measurements[:estimated_cost]
    )
  end
  
  defp handle_llm_event([:llm, :request, :exception], _measurements, metadata, _config) do
    Logger.error("LLM request failed",
      provider: metadata[:provider],
      model: metadata[:model],
      error: metadata[:error]
    )
  end
  
  defp handle_llm_event([:llm, :cache, action], measurements, metadata, _config) do
    Logger.debug("LLM cache #{action}",
      key: metadata[:cache_key],
      ttl: measurements[:ttl] || "N/A"
    )
  end
  
  defp handle_llm_event([:llm, :rate_limit], measurements, metadata, _config) do
    Logger.warn("LLM rate limit hit",
      provider: metadata[:provider],
      retry_after: measurements[:retry_after]
    )
  end
  
  defp handle_llm_event([:llm, :provider_switch], _measurements, metadata, _config) do
    Logger.info("LLM provider switched",
      from: metadata[:from_provider],
      to: metadata[:to_provider],
      reason: metadata[:reason]
    )
  end
  
  defp handle_llm_event(event, measurements, metadata, _config) do
    Logger.debug("LLM event: #{inspect(event)}",
      measurements: measurements,
      metadata: metadata
    )
  end
  
  defp handle_web_event([:phoenix, :router_dispatch, :stop], measurements, metadata, _config) do
    Logger.info("HTTP request",
      method: metadata[:method],
      path: metadata[:path],
      status: metadata[:status],
      duration_ms: measurements[:duration] / 1_000_000
    )
  end
  
  defp handle_web_event([:phoenix, :live_view, :mount, :stop], measurements, metadata, _config) do
    Logger.debug("LiveView mounted",
      view: metadata[:socket].view,
      duration_ms: measurements[:duration] / 1_000_000
    )
  end
  
  defp handle_web_event([:phoenix, :live_view, :handle_event, :stop], measurements, metadata, _config) do
    Logger.debug("LiveView event handled",
      event: metadata[:event],
      duration_ms: measurements[:duration] / 1_000_000
    )
  end
  
  defp handle_web_event(_event, _measurements, _metadata, _config), do: :ok
  
  defp handle_system_event([:vm, :memory], measurements, _metadata, _config) do
    Logger.info("VM memory stats",
      total_mb: measurements[:total] / 1_024_1024,
      processes_mb: measurements[:processes] / 1_024_1024,
      binary_mb: measurements[:binary] / 1_024_1024
    )
  end
  
  defp handle_system_event([:system, :health_check], measurements, metadata, _config) do
    Logger.info("System health check",
      status: metadata[:status],
      checks_passed: measurements[:checks_passed],
      total_checks: measurements[:total_checks],
      duration: measurements[:duration]
    )
  end
  
  defp handle_system_event([:system, :circuit_breaker, action], measurements, metadata, _config) do
    Logger.warn("Circuit breaker #{action}",
      name: metadata[:name],
      failure_count: measurements[:failure_count] || 0,
      threshold: measurements[:threshold] || "N/A"
    )
  end
  
  defp handle_system_event([:system, :rate_limit, :exceeded], measurements, metadata, _config) do
    Logger.warn("Rate limit exceeded",
      key: metadata[:key],
      limit: measurements[:limit],
      window: measurements[:window]
    )
  end
  
  defp handle_system_event(_event, _measurements, _metadata, _config), do: :ok
  
  @doc """
  Emit a custom telemetry event.
  """
  def emit(event_name, measurements, metadata \\ %{}) do
    :telemetry.execute(event_name, measurements, metadata)
  end
  
  @doc """
  Measure the duration of a function and emit telemetry.
  """
  def measure(event_name, metadata \\ %{}, fun) do
    start_time = System.monotonic_time()
    
    try do
      result = fun.()
      duration = System.monotonic_time() - start_time
      
      :telemetry.execute(
        event_name ++ [:stop],
        %{duration: duration},
        Map.put(metadata, :status, :ok)
      )
      
      result
    rescue
      error ->
        duration = System.monotonic_time() - start_time
        
        :telemetry.execute(
          event_name ++ [:exception],
          %{duration: duration},
          Map.merge(metadata, %{status: :error, error: error})
        )
        
        reraise error, __STACKTRACE__
    end
  end
  
  @doc """
  Start a telemetry span.
  """
  def start_span(event_name, metadata \\ %{}) do
    start_time = System.monotonic_time()
    start_metadata = metadata
      |> Map.put(:telemetry_span_context, make_ref())
      |> Map.put(:start_time, start_time)
    
    :telemetry.execute(event_name ++ [:start], %{system_time: System.system_time()}, start_metadata)
    start_metadata
  end
  
  @doc """
  Stop a telemetry span.
  """
  def stop_span(event_name, start_metadata, measurements \\ %{}) do
    # Calculate duration using monotonic time
    duration = case start_metadata[:start_time] do
      nil -> 0
      start_time -> System.monotonic_time() - start_time
    end
    
    :telemetry.execute(
      event_name ++ [:stop],
      Map.merge(measurements, %{duration: duration}),
      start_metadata
    )
  end
end