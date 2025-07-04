defmodule AutonomousOpponentV2Web.MCPSocket do
  @moduledoc """
  Phoenix Socket for MCP Gateway WebSocket transport.
  
  Provides real-time bidirectional communication for MCP Gateway.
  """
  use Phoenix.Socket
  
  alias AutonomousOpponentV2Core.MCPGateway.Transports.WebSocket
  alias AutonomousOpponentV2Core.MCPGateway.Router
  
  require Logger
  
  # Channels
  channel "mcp:*", AutonomousOpponentV2Web.MCPChannel
  
  @impl true
  def connect(params, socket, _connect_info) do
    # Create WebSocket connection in MCP Gateway
    case WebSocket.connect(self(), metadata: params) do
      {:ok, connection_id} ->
        socket = socket
        |> assign(:mcp_connection_id, connection_id)
        |> assign(:user_id, params["user_id"])
        
        {:ok, socket}
        
      {:error, reason} ->
        Logger.error("Failed to establish WebSocket connection: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @impl true
  def id(socket) do
    "mcp_socket:#{socket.assigns.mcp_connection_id}"
  end
  
  # Handle termination
  def terminate(reason, socket) do
    if connection_id = socket.assigns[:mcp_connection_id] do
      WebSocket.close(connection_id, reason)
    end
    :ok
  end
end