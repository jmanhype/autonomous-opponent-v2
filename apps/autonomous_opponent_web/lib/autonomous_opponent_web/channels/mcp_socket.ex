defmodule AutonomousOpponentV2Web.MCPSocket do
  @moduledoc """
  Socket configuration for MCP Gateway WebSocket connections.
  """
  
  use Phoenix.Socket
  
  # Channel routes
  channel "mcp:*", AutonomousOpponentV2Web.MCPChannel
  
  @impl true
  def connect(params, socket, _connect_info) do
    # Optional authentication can be added here
    # For now, accept all connections
    
    client_id = params["client_id"] || UUID.uuid4()
    
    socket = socket
    |> assign(:client_id, client_id)
    |> assign(:connected_at, DateTime.utc_now())
    
    {:ok, socket}
  end
  
  @impl true
  def id(socket), do: "mcp_socket:#{socket.assigns.client_id}"
end