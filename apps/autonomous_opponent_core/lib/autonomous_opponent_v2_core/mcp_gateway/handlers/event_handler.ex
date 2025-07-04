defmodule AutonomousOpponentV2Core.MCPGateway.Handlers.EventHandler do
  @moduledoc """
  Event streaming handler for MCP Gateway.
  
  Handles event subscriptions and streaming through both
  SSE and WebSocket transports.
  """
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCPGateway.Transports.{HTTPSSE, WebSocket}
  
  @doc """
  Handle event subscription request
  """
  def handle_request(request, connection, _backend) do
    # Extract event patterns to subscribe to
    patterns = extract_event_patterns(request)
    transport_type = request[:transport_type]
    
    # Subscribe to requested events
    Enum.each(patterns, fn pattern ->
      EventBus.subscribe(pattern)
    end)
    
    # Set up event forwarding based on transport
    case transport_type do
      :http_sse ->
        setup_sse_forwarding(connection, patterns)
        
      :websocket ->
        setup_websocket_forwarding(connection, patterns)
        
      _ ->
        {:error, :unsupported_transport}
    end
  end
  
  # Private functions
  
  defp extract_event_patterns(request) do
    # Extract from path or query params
    case request[:path] do
      "/events/all" -> [:all]
      "/events/" <> specific -> [String.to_atom(specific)]
      _ -> request[:params][:events] || [:all]
    end
  end
  
  defp setup_sse_forwarding(connection, patterns) do
    # Start a process to forward events via SSE
    Task.start(fn ->
      forward_events_loop(:http_sse, connection, patterns)
    end)
    
    {:ok, %{status: "streaming", transport: "sse", patterns: patterns}}
  end
  
  defp setup_websocket_forwarding(connection, patterns) do
    # WebSocket handles bidirectional, so just confirm subscription
    {:ok, %{status: "subscribed", transport: "websocket", patterns: patterns}}
  end
  
  defp forward_events_loop(transport, connection, patterns) do
    receive do
      {:event, event_name, data} ->
        if should_forward_event?(event_name, patterns) do
          formatted = format_event(event_name, data)
          
          case transport do
            :http_sse -> HTTPSSE.send_event(connection.id, formatted)
            :websocket -> WebSocket.send_message(connection.id, formatted)
          end
        end
        
        forward_events_loop(transport, connection, patterns)
        
      :stop ->
        :ok
    end
  end
  
  defp should_forward_event?(_event_name, [:all]), do: true
  
  defp should_forward_event?(event_name, patterns) do
    Enum.any?(patterns, fn pattern ->
      case pattern do
        ^event_name -> true
        _ -> false
      end
    end)
  end
  
  defp format_event(event_name, data) do
    %{
      event: "vsm_event",
      data: %{
        event_type: event_name,
        payload: data,
        timestamp: System.system_time(:millisecond)
      }
    }
  end
end