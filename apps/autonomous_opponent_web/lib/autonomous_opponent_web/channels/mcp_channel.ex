defmodule AutonomousOpponentV2Web.MCPChannel do
  @moduledoc """
  Phoenix Channel for WebSocket transport in MCP Gateway.
  
  Provides bidirectional communication with clients using Phoenix Channels
  and WebSocket protocol.
  """
  
  use Phoenix.Channel
  
  alias AutonomousOpponentV2Core.MCP.Transport.WebSocket
  alias AutonomousOpponentV2Core.EventBus
  
  require Logger
  
  @doc """
  Handles client joining the MCP channel.
  """
  def join("mcp:gateway", params, socket) do
    client_id = params["client_id"] || UUID.uuid4()
    
    # Register WebSocket connection
    opts = [
      metadata: params,
      compression: Map.get(params, "compression", true),
      binary: Map.get(params, "binary", false),
      rate_limit: Map.get(params, "rate_limit", 100)
    ]
    
    case WebSocket.register_connection(self(), client_id, opts) do
      {:ok, connection_id} ->
        socket = socket
        |> assign(:client_id, client_id)
        |> assign(:connection_id, connection_id)
        |> assign(:joined_at, DateTime.utc_now())
        
        # Subscribe to client-specific events
        EventBus.subscribe({:mcp_client_events, client_id})
        
        # Send welcome message
        push(socket, "connected", %{
          client_id: client_id,
          connection_id: connection_id,
          transport: "websocket"
        })
        
        {:ok, socket}
        
      {:error, reason} ->
        Logger.error("Failed to register WebSocket connection: #{inspect(reason)}")
        {:error, %{reason: "connection_failed"}}
    end
  end
  
  @doc """
  Handles incoming messages from clients.
  """
  def handle_in("message", payload, socket) do
    connection_id = socket.assigns.connection_id
    
    # Forward to WebSocket transport for processing
    WebSocket.handle_message(connection_id, payload)
    
    # Acknowledge receipt
    {:reply, {:ok, %{received: true}}, socket}
  end
  
  @doc """
  Handles ping messages for keep-alive.
  """
  def handle_in("ping", _payload, socket) do
    # Respond with pong
    {:reply, {:ok, %{type: "pong", timestamp: DateTime.utc_now()}}, socket}
  end
  
  @doc """
  Handles pong responses from clients.
  """
  def handle_in("pong", _payload, socket) do
    connection_id = socket.assigns.connection_id
    WebSocket.handle_pong(connection_id)
    {:noreply, socket}
  end
  
  @doc """
  Handles client requesting specific event subscriptions.
  """
  def handle_in("subscribe", %{"events" => events}, socket) when is_list(events) do
    # Subscribe to requested event types
    Enum.each(events, fn event_type ->
      EventBus.subscribe({:mcp_event_type, event_type})
    end)
    
    socket = assign(socket, :subscriptions, events)
    
    {:reply, {:ok, %{subscribed: events}}, socket}
  end
  
  @doc """
  Handles client unsubscribe requests.
  """
  def handle_in("unsubscribe", %{"events" => events}, socket) when is_list(events) do
    # Unsubscribe from event types
    Enum.each(events, fn event_type ->
      EventBus.unsubscribe({:mcp_event_type, event_type})
    end)
    
    current_subs = Map.get(socket.assigns, :subscriptions, [])
    remaining_subs = current_subs -- events
    
    socket = assign(socket, :subscriptions, remaining_subs)
    
    {:reply, {:ok, %{unsubscribed: events}}, socket}
  end
  
  @doc """
  Handles info messages from EventBus and other processes.
  """
  def handle_info({:event_bus, topic, data}, socket) do
    # Forward events to client based on topic
    event_type = case topic do
      {:mcp_client_events, _} -> "client_event"
      {:mcp_event_type, type} -> to_string(type)
      _ -> "event"
    end
    
    push(socket, event_type, data)
    {:noreply, socket}
  end
  
  def handle_info({:ws_send, message}, socket) do
    # Direct message from WebSocket transport
    push(socket, "message", message)
    {:noreply, socket}
  end
  
  def handle_info(:ws_ping, socket) do
    # Send ping to client
    push(socket, "ping", %{timestamp: DateTime.utc_now()})
    {:noreply, socket}
  end
  
  @doc """
  Handles client disconnection.
  """
  def terminate(reason, socket) do
    connection_id = socket.assigns[:connection_id]
    client_id = socket.assigns[:client_id]
    
    if connection_id do
      WebSocket.unregister_connection(connection_id)
      Logger.info("WebSocket disconnected: #{connection_id} (#{inspect(reason)})")
    end
    
    # Unsubscribe from all events
    if client_id do
      EventBus.unsubscribe({:mcp_client_events, client_id})
    end
    
    :ok
  end
end