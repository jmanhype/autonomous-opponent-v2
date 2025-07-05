defmodule AutonomousOpponentV2Core.MCP.Tracing do
  @moduledoc """
  OpenTelemetry distributed tracing for MCP Gateway.
  
  Provides:
  - Trace ID propagation through VSM
  - Span creation for major operations
  - Integration with existing telemetry
  - Performance monitoring
  """
  
  require OpentelemetryAPI.Tracer, as: Tracer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  
  @tracer_name :mcp_gateway
  
  # Trace attributes
  @transport_attr "mcp.transport"
  @client_id_attr "mcp.client_id"
  @message_type_attr "mcp.message_type"
  @message_size_attr "mcp.message_size"
  @vsm_subsystem_attr "vsm.subsystem"
  @error_attr "mcp.error"
  
  @doc """
  Starts a new trace span for a gateway operation.
  
  Options:
  - kind: :server, :client, :producer, :consumer, :internal (default: :internal)
  - attributes: Map of attributes to add to the span
  """
  def with_span(name, opts \\ [], fun) do
    kind = Keyword.get(opts, :kind, :internal)
    attributes = Keyword.get(opts, :attributes, %{})
    
    Tracer.with_span name, %{kind: kind, attributes: attributes} do
      fun.()
    end
  end
  
  @doc """
  Traces message routing through the gateway.
  """
  def trace_routing(client_id, message, transport, fun) do
    attributes = %{
      @client_id_attr => client_id,
      @transport_attr => to_string(transport),
      @message_type_attr => get_message_type(message),
      @message_size_attr => estimate_message_size(message)
    }
    
    with_span "mcp.route_message", [kind: :server, attributes: attributes] do
      # Add events for routing decisions
      Tracer.add_event("routing.started", %{transport: transport})
      
      # The actual routing happens here
      result = fun.()
      
      case result do
        {:ok, _} ->
          Tracer.add_event("routing.completed", %{status: "success"})
          Tracer.set_status(:ok)
          
        {:error, reason} ->
          Tracer.add_event("routing.failed", %{reason: inspect(reason)})
          Tracer.set_attribute(@error_attr, inspect(reason))
          Tracer.set_status(:error, inspect(reason))
      end
      
      result
    end
  end
  
  @doc """
  Traces WebSocket message handling.
  """
  def trace_websocket_message(client_id, message, fun) do
    trace_transport_message(:websocket, client_id, message, fun)
  end
  
  @doc """
  Traces SSE event sending.
  """
  def trace_sse_event(client_id, event_type, data, fun) do
    attributes = %{
      @client_id_attr => client_id,
      @transport_attr => "http_sse",
      "sse.event_type" => event_type,
      @message_size_attr => estimate_message_size(data)
    }
    
    with_span "mcp.sse.send_event", [attributes: attributes] do
      fun.()
    end
  end
  
  @doc """
  Traces connection pool operations.
  """
  def trace_pool_operation(operation, connection_id, fun) do
    attributes = %{
      "pool.operation" => to_string(operation),
      "pool.connection_id" => connection_id
    }
    
    with_span "mcp.pool.#{operation}", [attributes: attributes] do
      start_time = System.monotonic_time(:millisecond)
      result = fun.()
      duration = System.monotonic_time(:millisecond) - start_time
      
      Tracer.add_event("pool.operation_completed", %{
        duration_ms: duration,
        success: match?({:ok, _}, result)
      })
      
      result
    end
  end
  
  @doc """
  Traces VSM integration points.
  """
  def trace_vsm_interaction(subsystem, operation, data, fun) do
    attributes = %{
      @vsm_subsystem_attr => to_string(subsystem),
      "vsm.operation" => to_string(operation),
      "vsm.data_size" => estimate_message_size(data)
    }
    
    with_span "vsm.#{subsystem}.#{operation}", [attributes: attributes] do
      # Create a link to the parent trace if available
      parent_ctx = Tracer.current_span_ctx()
      
      enriched_data = if parent_ctx do
        # Propagate trace context through EventBus
        Map.put(data, :trace_context, encode_trace_context(parent_ctx))
      else
        data
      end
      
      result = fun.(enriched_data)
      
      # Record VSM response
      case result do
        {:ok, response} ->
          Tracer.add_event("vsm.response_received", %{
            subsystem: subsystem,
            response_type: get_response_type(response)
          })
          
        {:error, reason} ->
          Tracer.add_event("vsm.error", %{
            subsystem: subsystem,
            error: inspect(reason)
          })
      end
      
      result
    end
  end
  
  @doc """
  Traces circuit breaker operations.
  """
  def trace_circuit_breaker(breaker_name, operation, fun) do
    attributes = %{
      "circuit_breaker.name" => to_string(breaker_name),
      "circuit_breaker.operation" => to_string(operation)
    }
    
    with_span "mcp.circuit_breaker", [attributes: attributes] do
      result = fun.()
      
      # Add circuit breaker state
      state = get_circuit_breaker_state(breaker_name)
      Tracer.set_attribute("circuit_breaker.state", to_string(state))
      
      # Record events based on result
      case {operation, result} do
        {:call, {:error, :circuit_open}} ->
          Tracer.add_event("circuit_breaker.rejected", %{state: state})
          
        {:call, {:ok, _}} ->
          Tracer.add_event("circuit_breaker.allowed", %{state: state})
          
        _ ->
          :ok
      end
      
      result
    end
  end
  
  @doc """
  Extracts trace context from a message or request.
  """
  def extract_trace_context(headers) when is_map(headers) do
    # Extract W3C Trace Context headers
    traceparent = Map.get(headers, "traceparent")
    tracestate = Map.get(headers, "tracestate")
    
    if traceparent do
      :otel_propagator_text_map.extract([{"traceparent", traceparent}, {"tracestate", tracestate || ""}])
    else
      :undefined
    end
  end
  
  @doc """
  Injects trace context into headers for propagation.
  """
  def inject_trace_context(headers \\ %{}) do
    ctx = Tracer.current_span_ctx()
    
    if ctx do
      # Inject W3C Trace Context headers
      carrier = :otel_propagator_text_map.inject([])
      
      Enum.reduce(carrier, headers, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)
    else
      headers
    end
  end
  
  @doc """
  Adds custom attributes to the current span.
  """
  def add_attributes(attributes) when is_map(attributes) do
    Enum.each(attributes, fn {key, value} ->
      Tracer.set_attribute(to_string(key), to_string(value))
    end)
  end
  
  @doc """
  Records an event in the current span.
  """
  def add_event(name, attributes \\ %{}) do
    Tracer.add_event(name, attributes)
  end
  
  @doc """
  Sets up telemetry handlers for automatic tracing.
  """
  def setup_telemetry_handlers do
    events = [
      [:mcp, :gateway, :message, :start],
      [:mcp, :gateway, :message, :stop],
      [:mcp, :gateway, :message, :exception],
      [:mcp, :transport, :websocket, :start],
      [:mcp, :transport, :websocket, :stop],
      [:mcp, :transport, :sse, :start],
      [:mcp, :transport, :sse, :stop],
      [:mcp, :pool, :checkout, :start],
      [:mcp, :pool, :checkout, :stop],
      [:mcp, :pool, :checkin, :start],
      [:mcp, :pool, :checkin, :stop]
    ]
    
    :telemetry.attach_many(
      "mcp-gateway-tracing",
      events,
      &handle_telemetry_event/4,
      nil
    )
  end
  
  # Private functions
  
  defp handle_telemetry_event(event, measurements, metadata, _config) do
    case event do
      [:mcp, :gateway, :message, :start] ->
        # Start a new span for message processing
        span_name = "mcp.process_message"
        attributes = extract_telemetry_attributes(metadata)
        # This would need to store the span context for the stop event
        :ok
        
      [:mcp, :gateway, :message, :stop] ->
        # Complete the span
        if metadata[:duration] do
          Tracer.add_event("message.processed", %{duration_us: metadata.duration})
        end
        :ok
        
      [:mcp, :gateway, :message, :exception] ->
        # Record the exception
        Tracer.record_exception(metadata.reason, metadata.stacktrace)
        Tracer.set_status(:error, Exception.message(metadata.reason))
        :ok
        
      _ ->
        # Handle other events
        :ok
    end
  end
  
  defp extract_telemetry_attributes(metadata) do
    metadata
    |> Map.take([:client_id, :transport, :message_type, :message_size])
    |> Enum.map(fn {k, v} -> {"mcp.#{k}", to_string(v)} end)
    |> Map.new()
  end
  
  defp get_message_type(message) when is_map(message) do
    Map.get(message, :type, Map.get(message, "type", "unknown"))
  end
  defp get_message_type(_), do: "unknown"
  
  defp estimate_message_size(data) when is_binary(data), do: byte_size(data)
  defp estimate_message_size(data) do
    data
    |> Jason.encode!()
    |> byte_size()
  rescue
    _ -> 0
  end
  
  defp encode_trace_context(span_ctx) do
    # Encode span context for propagation through EventBus
    %{
      trace_id: span_ctx.trace_id,
      span_id: span_ctx.span_id,
      trace_flags: span_ctx.trace_flags
    }
  end
  
  defp get_response_type({:ok, response}) when is_map(response) do
    Map.get(response, :type, "unknown")
  end
  defp get_response_type(_), do: "unknown"
  
  defp get_circuit_breaker_state(breaker_name) do
    # This would query the actual circuit breaker state
    # For now, return a placeholder
    :closed
  end
  
  # Transport-specific tracing
  defp trace_transport_message(transport, client_id, message, fun) do
    attributes = %{
      @client_id_attr => client_id,
      @transport_attr => to_string(transport),
      @message_type_attr => get_message_type(message),
      @message_size_attr => estimate_message_size(message)
    }
    
    with_span "mcp.#{transport}.handle_message", [kind: :consumer, attributes: attributes] do
      fun.()
    end
  end
end