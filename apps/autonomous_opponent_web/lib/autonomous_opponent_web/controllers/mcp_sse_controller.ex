defmodule AutonomousOpponentV2Web.MCPSSEController do
  @moduledoc """
  Phoenix controller for MCP Gateway SSE transport.
  
  Provides Server-Sent Events endpoint for real-time streaming.
  """
  use AutonomousOpponentV2Web, :controller
  
  alias AutonomousOpponentV2Core.MCPGateway.Transports.HTTPSSE
  alias AutonomousOpponentV2Core.MCPGateway.Router
  
  require Logger
  
  @doc """
  Establish SSE connection
  """
  def connect(conn, params) do
    # Set SSE headers
    conn = conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> put_resp_header("x-accel-buffering", "no")  # Disable Nginx buffering
    |> send_chunked(200)
    
    # Create SSE connection
    client_ref = self()
    last_event_id = get_req_header(conn, "last-event-id") |> List.first()
    
    case HTTPSSE.connect(client_ref, last_event_id: last_event_id, metadata: params) do
      {:ok, connection_id} ->
        # Set up connection state
        conn = assign(conn, :mcp_connection_id, connection_id)
        
        # Start SSE event loop
        sse_loop(conn, connection_id)
        
      {:error, reason} ->
        Logger.error("Failed to establish SSE connection: #{inspect(reason)}")
        
        # Send error event and close
        chunk(conn, format_sse_error(reason))
        conn
    end
  end
  
  @doc """
  Stream events endpoint
  """
  def events(conn, %{"topic" => topic} = params) do
    # Route through MCP Gateway
    request = %{
      path: "/events/#{topic}",
      transport_type: :http_sse,
      params: params,
      remote_ip: to_string(:inet.ntoa(conn.remote_ip))
    }
    
    case Router.route(request) do
      {:ok, _response} ->
        # Connection established, start streaming
        connect(conn, params)
        
      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: reason})
    end
  end
  
  # Private functions
  
  defp sse_loop(conn, connection_id) do
    receive do
      {:sse_data, data} ->
        # Send SSE data chunk
        case chunk(conn, data) do
          {:ok, conn} ->
            sse_loop(conn, connection_id)
            
          {:error, _reason} ->
            # Connection closed by client
            HTTPSSE.close(connection_id)
            conn
        end
        
      :close ->
        # Server-initiated close
        HTTPSSE.close(connection_id)
        conn
        
      other ->
        Logger.warning("Unexpected message in SSE loop: #{inspect(other)}")
        sse_loop(conn, connection_id)
        
    after
      # Timeout after 5 minutes of inactivity
      300_000 ->
        HTTPSSE.close(connection_id)
        conn
    end
  end
  
  defp format_sse_error(reason) do
    "event: error\n" <>
    "data: #{Jason.encode!(%{error: reason})}\n\n"
  end
end