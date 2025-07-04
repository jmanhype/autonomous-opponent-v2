defmodule AutonomousOpponentV2Web.MCPChannel do
  @moduledoc """
  Phoenix Channel for MCP Gateway WebSocket communication.
  
  Handles WebSocket messages and routes them through MCP Gateway.
  """
  use AutonomousOpponentV2Web, :channel
  
  alias AutonomousOpponentV2Core.MCPGateway.Transports.WebSocket
  alias AutonomousOpponentV2Core.MCPGateway.Router
  alias AutonomousOpponentV2Core.EventBus
  
  require Logger
  
  @impl true
  def join("mcp:" <> topic, params, socket) do
    # Route join request through MCP Gateway
    request = %{
      path: "/events/#{topic}",
      transport_type: :websocket,
      params: params,
      user_id: socket.assigns[:user_id]
    }
    
    case Router.route(request) do
      {:ok, response} ->
        # Subscribe to relevant events
        if topic == "events" do
          EventBus.subscribe(:all)
        else
          EventBus.subscribe(String.to_atom(topic))
        end
        
        socket = assign(socket, :topic, topic)
        
        {:ok, response, socket}
        
      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
  
  @impl true
  def handle_in("request", payload, socket) do
    connection_id = socket.assigns.mcp_connection_id
    
    # Forward to WebSocket transport
    WebSocket.handle_message(connection_id, %{
      "type" => "request",
      "method" => payload["method"],
      "params" => payload["params"],
      "id" => payload["id"]
    })
    
    {:noreply, socket}
  end
  
  def handle_in("event", payload, socket) do
    connection_id = socket.assigns.mcp_connection_id
    
    # Forward event
    WebSocket.handle_message(connection_id, %{
      "type" => "event",
      "event" => payload["event"],
      "data" => payload["data"]
    })
    
    {:noreply, socket}
  end
  
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{type: "pong", timestamp: System.system_time(:millisecond)}}, socket}
  end
  
  @impl true
  def handle_info({:event, event_name, data}, socket) do
    # Forward EventBus events to WebSocket
    push(socket, "event", %{
      event: event_name,
      data: data,
      timestamp: System.system_time(:millisecond)
    })
    
    {:noreply, socket}
  end
  
  def handle_info({:websocket_frame, _type, data}, socket) do
    # Handle incoming WebSocket frames from transport
    case Jason.decode(data) do
      {:ok, message} ->
        handle_transport_message(message, socket)
        
      {:error, _} ->
        {:noreply, socket}
    end
  end
  
  # Private functions
  
  defp handle_transport_message(%{"type" => "response"} = message, socket) do
    # Send response back to client
    push(socket, "response", message)
    {:noreply, socket}
  end
  
  defp handle_transport_message(%{"type" => "event"} = message, socket) do
    # Forward event to client
    push(socket, "event", message["data"])
    {:noreply, socket}
  end
  
  defp handle_transport_message(%{"type" => "error"} = message, socket) do
    # Send error to client
    push(socket, "error", message)
    {:noreply, socket}
  end
  
  defp handle_transport_message(_, socket), do: {:noreply, socket}
end