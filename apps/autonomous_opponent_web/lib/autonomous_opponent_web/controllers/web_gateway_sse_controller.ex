defmodule AutonomousOpponentV2Web.WebGatewaySSEController do
  @moduledoc """
  Phoenix controller for Server-Sent Events (SSE) transport in Web Gateway.
  
  Handles HTTP connections and streams events to clients using SSE protocol.
  """
  
  use AutonomousOpponentV2Web, :controller
  
  alias AutonomousOpponentV2Core.WebGateway.Transport.HTTPSSE
  alias AutonomousOpponentV2Core.WebGateway.Gateway
  
  require Logger
  
  @heartbeat_interval 30_000  # 30 seconds
  
  @doc """
  Establishes SSE connection and streams events to the client.
  """
  def stream(conn, params) do
    # Check if gateway is accepting new connections
    if not Gateway.accepting_connections?() do
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "Service temporarily unavailable"})
      |> halt()
    else
    
    # Extract client ID from params or authenticated user
    client_id = case conn.assigns do
      %{current_user: %{user_id: user_id}} -> user_id
      _ -> params["client_id"] || UUID.uuid4()
    end
    
    # Set up SSE headers
    conn = conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> put_resp_header("x-accel-buffering", "no")  # Disable Nginx buffering
    
    # Send initial connection event
    conn = send_chunked(conn, 200)
    
    # Build welcome data with auth info
    welcome_data = %{
      client_id: client_id,
      timestamp: DateTime.utc_now(),
      transport: "http_sse",
      authenticated: Map.get(conn.assigns, :authenticated, false)
    }
    
    # Add user info if authenticated
    welcome_data = case conn.assigns do
      %{current_user: user_info} ->
        Map.merge(welcome_data, %{
          user_id: user_info.user_id,
          role: user_info.role
        })
      _ ->
        welcome_data
    end
    
    # Send welcome message
    welcome_event = format_sse_event("connected", welcome_data)
    
    case chunk(conn, welcome_event) do
      {:ok, conn} ->
        # Register connection with HTTPSSE transport
        connection_params = Map.merge(params, %{
          "authenticated" => Map.get(conn.assigns, :authenticated, false),
          "user_info" => Map.get(conn.assigns, :current_user)
        })
        
        {:ok, connection_id} = HTTPSSE.register_connection(self(), client_id, connection_params)
        
        # Start streaming
        stream_loop(conn, client_id, connection_id)
        
      {:error, _reason} ->
        conn
    end
    end  # End of accepting_connections check
  end
  
  # Private functions
  
  defp stream_loop(conn, client_id, connection_id) do
    receive do
      {:sse_event, data} ->
        # Send event to client
        case chunk(conn, data) do
          {:ok, conn} ->
            stream_loop(conn, client_id, connection_id)
            
          {:error, _reason} ->
            # Connection closed by client
            cleanup_connection(connection_id)
            conn
        end
        
      :close ->
        # Graceful shutdown
        cleanup_connection(connection_id)
        conn
        
    after
      @heartbeat_interval ->
        # Send heartbeat
        heartbeat = format_sse_event("heartbeat", %{timestamp: DateTime.utc_now()})
        
        case chunk(conn, heartbeat) do
          {:ok, conn} ->
            stream_loop(conn, client_id, connection_id)
            
          {:error, _reason} ->
            cleanup_connection(connection_id)
            conn
        end
    end
  end
  
  defp format_sse_event(event_type, data) do
    json_data = Jason.encode!(data)
    "event: #{event_type}\ndata: #{json_data}\n\n"
  end
  
  defp cleanup_connection(connection_id) do
    HTTPSSE.unregister_connection(connection_id)
    Logger.info("SSE connection cleaned up: #{connection_id}")
  end
end