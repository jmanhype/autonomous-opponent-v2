defmodule AutonomousOpponentV2Web.TelemetryDashboard do
  @moduledoc """
  Phoenix LiveDashboard telemetry configuration for Autonomous Opponent.
  
  Provides comprehensive metrics for:
  - Consciousness state and operations
  - VSM subsystem performance
  - EventBus message flow
  - LLM API usage and costs
  - Web request metrics
  - System health and performance
  """
  
  use Supervisor
  import Telemetry.Metrics
  
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end
  
  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  def metrics do
    [
      # Consciousness Metrics
      consciousness_metrics(),
      
      # VSM Metrics
      vsm_metrics(),
      
      # EventBus Metrics
      event_bus_metrics(),
      
      # LLM Metrics
      llm_metrics(),
      
      # Phoenix Metrics
      phoenix_metrics(),
      
      # VM Metrics
      vm_metrics()
    ]
    |> List.flatten()
  end
  
  defp consciousness_metrics do
    [
      # Consciousness State
      last_value("consciousness.state_change.duration",
        unit: {:native, :millisecond},
        description: "Time to change consciousness state",
        tags: [:from_state, :to_state]
      ),
      
      counter("consciousness.state_change.count",
        description: "Number of consciousness state changes",
        tags: [:from_state, :to_state]
      ),
      
      # Consciousness Operations
      summary("consciousness.get_state.duration",
        unit: {:native, :millisecond},
        description: "Time to get consciousness state"
      ),
      
      counter("consciousness.dialog_exchange.count",
        description: "Number of dialog exchanges",
        tags: [:conversation_id]
      ),
      
      distribution("consciousness.dialog_exchange.message_length",
        description: "Length of dialog messages",
        unit: :byte,
        reporter_options: [buckets: [100, 500, 1000, 5000, 10000]]
      ),
      
      counter("consciousness.reflection_completed.count",
        description: "Number of completed reflections",
        tags: [:aspect]
      ),
      
      distribution("consciousness.reflection_completed.insights_count",
        description: "Number of insights per reflection",
        reporter_options: [buckets: [1, 3, 5, 10, 20]]
      ),
      
      counter("consciousness.existential_inquiry.count",
        description: "Number of existential inquiries"
      ),
      
      # Awareness Levels
      last_value("consciousness.awareness_level_changed.delta",
        description: "Change in awareness level",
        tags: [:from_level, :to_level]
      )
    ]
  end
  
  defp vsm_metrics do
    [
      # S1 Operations
      summary("vsm.s1.operation.duration",
        unit: {:native, :millisecond},
        description: "S1 operation duration",
        tags: [:operation]
      ),
      
      counter("vsm.s1.operation.start.count",
        description: "S1 operations started",
        tags: [:operation]
      ),
      
      counter("vsm.s1.operation.stop.count",
        description: "S1 operations completed",
        tags: [:operation]
      ),
      
      counter("vsm.s1.operation.exception.count",
        description: "S1 operations failed",
        tags: [:operation, :error]
      ),
      
      distribution("vsm.s1.variety_absorbed.efficiency",
        description: "S1 variety absorption efficiency",
        tags: [:server_name],
        reporter_options: [buckets: [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]]
      ),
      
      last_value("vsm.s1.variety_absorbed.input_variety",
        description: "Input variety to S1",
        tags: [:server_name]
      ),
      
      last_value("vsm.s1.variety_absorbed.absorbed_variety",
        description: "Variety absorbed by S1",
        tags: [:server_name]
      ),
      
      counter("vsm.s1.variety_buffer_overflow.count",
        description: "S1 variety buffer overflows"
      ),
      
      # S2 Coordination
      counter("vsm.s2.anti_oscillation_triggered.count",
        description: "S2 anti-oscillation triggers",
        tags: [:oscillation_type]
      ),
      
      last_value("vsm.s2.anti_oscillation_triggered.damping_factor",
        description: "S2 damping factor applied"
      ),
      
      # S3 Control
      counter("vsm.s3.resource_allocated.count",
        description: "S3 resource allocations",
        tags: [:resource_type]
      ),
      
      distribution("vsm.s3.resource_allocated.amount",
        description: "S3 resource allocation amounts",
        tags: [:resource_type]
      ),
      
      last_value("vsm.s3.resource_allocated.utilization",
        description: "S3 resource utilization",
        tags: [:resource_type]
      ),
      
      # S4 Intelligence
      counter("vsm.s4.threat_detected.count",
        description: "S4 threats detected",
        tags: [:threat_type]
      ),
      
      distribution("vsm.s4.threat_detected.severity",
        description: "S4 threat severity",
        tags: [:threat_type],
        reporter_options: [buckets: [0.1, 0.3, 0.5, 0.7, 0.9]]
      ),
      
      counter("vsm.s4.opportunity_identified.count",
        description: "S4 opportunities identified",
        tags: [:opportunity_type]
      ),
      
      # S5 Policy
      counter("vsm.s5.policy_updated.count",
        description: "S5 policy updates",
        tags: [:policy_domain]
      ),
      
      counter("vsm.s5.constraint_violation.count",
        description: "S5 constraint violations",
        tags: [:constraint_type]
      ),
      
      # Algedonic
      counter("vsm.algedonic.pain_signal.count",
        description: "Algedonic pain signals",
        tags: [:source]
      ),
      
      counter("vsm.algedonic.pleasure_signal.count",
        description: "Algedonic pleasure signals",
        tags: [:source]
      ),
      
      distribution("vsm.algedonic.pain_signal.intensity",
        description: "Pain signal intensity",
        tags: [:source],
        reporter_options: [buckets: [0.1, 0.3, 0.5, 0.7, 0.9]]
      )
    ]
  end
  
  defp event_bus_metrics do
    [
      counter("event_bus.publish.count",
        description: "Events published",
        tags: [:topic]
      ),
      
      distribution("event_bus.publish.message_size",
        description: "Event message size",
        unit: :byte,
        tags: [:topic],
        reporter_options: [buckets: [100, 500, 1000, 5000, 10000]]
      ),
      
      counter("event_bus.subscribe.count",
        description: "Subscriptions created",
        tags: [:event_type]
      ),
      
      counter("event_bus.unsubscribe.count",
        description: "Subscriptions removed",
        tags: [:event_type]
      ),
      
      summary("event_bus.broadcast.duration",
        unit: {:native, :nanosecond},
        description: "Time to broadcast event",
        tags: [:topic]
      ),
      
      last_value("event_bus.broadcast.recipient_count",
        description: "Number of broadcast recipients",
        tags: [:topic]
      ),
      
      counter("event_bus.message_dropped.count",
        description: "Messages dropped",
        tags: [:topic, :reason]
      ),
      
      last_value("event_bus.subscription_added.subscriber_count",
        description: "Current subscriber count",
        tags: [:event_type]
      )
    ]
  end
  
  defp llm_metrics do
    [
      # Request metrics
      summary("llm.request.duration",
        unit: {:native, :millisecond},
        description: "LLM request duration",
        tags: [:provider, :model, :intent]
      ),
      
      counter("llm.request.start.count",
        description: "LLM requests started",
        tags: [:provider, :model]
      ),
      
      counter("llm.request.stop.count",
        description: "LLM requests completed",
        tags: [:provider, :model, :status]
      ),
      
      counter("llm.request.exception.count",
        description: "LLM request failures",
        tags: [:provider, :model, :error]
      ),
      
      # Token usage
      distribution("llm.token_usage.prompt_tokens",
        description: "Prompt token count",
        tags: [:provider, :model, :intent],
        reporter_options: [buckets: [100, 500, 1000, 2000, 4000, 8000]]
      ),
      
      distribution("llm.token_usage.response_tokens",
        description: "Response token count",
        tags: [:provider, :model, :intent],
        reporter_options: [buckets: [100, 500, 1000, 2000, 4000]]
      ),
      
      sum("llm.token_usage.total_tokens",
        description: "Total tokens used",
        tags: [:provider, :model]
      ),
      
      sum("llm.token_usage.estimated_cost",
        description: "Estimated cost in USD",
        tags: [:provider, :model],
        unit: :dollar
      ),
      
      # Cache metrics
      counter("llm.cache.hit.count",
        description: "LLM cache hits",
        tags: [:intent]
      ),
      
      counter("llm.cache.miss.count",
        description: "LLM cache misses",
        tags: [:intent, :reason]
      ),
      
      # Rate limiting
      counter("llm.rate_limit.count",
        description: "LLM rate limit hits",
        tags: [:provider]
      ),
      
      last_value("llm.rate_limit.retry_after",
        description: "Rate limit retry after seconds",
        tags: [:provider]
      ),
      
      # Provider switching
      counter("llm.provider_switch.count",
        description: "LLM provider switches",
        tags: [:from_provider, :to_provider, :reason]
      )
    ]
  end
  
  defp phoenix_metrics do
    [
      # HTTP Request metrics
      summary("phoenix.router_dispatch.stop.duration",
        unit: {:native, :millisecond},
        tags: [:route],
        description: "HTTP request duration"
      ),
      
      counter("phoenix.router_dispatch.stop.count",
        description: "HTTP requests",
        tags: [:method, :route, :status]
      ),
      
      # LiveView metrics
      summary("phoenix.live_view.mount.stop.duration",
        unit: {:native, :millisecond},
        tags: [:view],
        description: "LiveView mount duration"
      ),
      
      summary("phoenix.live_view.handle_event.stop.duration",
        unit: {:native, :millisecond},
        tags: [:event],
        description: "LiveView event handling duration"
      ),
      
      counter("phoenix.live_view.handle_event.stop.count",
        description: "LiveView events handled",
        tags: [:event]
      )
    ]
  end
  
  defp vm_metrics do
    [
      # Memory
      last_value("vm.memory.total", unit: {:byte, :megabyte}, description: "Total VM memory"),
      last_value("vm.memory.processes", unit: {:byte, :megabyte}, description: "Process memory"),
      last_value("vm.memory.binary", unit: {:byte, :megabyte}, description: "Binary memory"),
      last_value("vm.memory.ets", unit: {:byte, :megabyte}, description: "ETS memory"),
      
      # System
      last_value("vm.total_run_queue_lengths.total", description: "Total run queue length"),
      last_value("vm.total_run_queue_lengths.cpu", description: "CPU run queue length"),
      last_value("vm.total_run_queue_lengths.io", description: "IO run queue length"),
      
      # Processes
      last_value("vm.system_counts.process_count", description: "Process count"),
      last_value("vm.system_counts.atom_count", description: "Atom count"),
      last_value("vm.system_counts.port_count", description: "Port count"),
      
      # System health
      counter("system.health_check.count",
        description: "Health checks performed",
        tags: [:status]
      ),
      
      last_value("system.health_check.checks_passed",
        description: "Health checks passed"
      ),
      
      summary("system.health_check.duration",
        unit: {:native, :millisecond},
        description: "Health check duration"
      ),
      
      # Circuit breaker
      counter("system.circuit_breaker.opened.count",
        description: "Circuit breakers opened",
        tags: [:name]
      ),
      
      counter("system.circuit_breaker.closed.count",
        description: "Circuit breakers closed",
        tags: [:name]
      ),
      
      # Rate limiting
      counter("system.rate_limit.exceeded.count",
        description: "Rate limits exceeded",
        tags: [:key]
      )
    ]
  end
  
  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function should call :telemetry.execute/3 with metrics.
      {AutonomousOpponentV2Web.Telemetry, :emit_vm_metrics, []}
    ]
  end
end