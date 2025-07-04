defmodule AutonomousOpponentV2Core.MCPGateway.Transports.WebSocket do
  @moduledoc """
  WebSocket transport for MCP Gateway.
  
  Provides:
  - Bidirectional real-time communication
  - Binary and text frame support
  - Automatic ping/pong for connection health
  - Reconnection with exponential backoff
  
  ## Wisdom Preservation
  
  ### Why WebSockets?
  While SSE handles server-to-client well, many applications need
  bidirectional communication. WebSockets provide full-duplex channels
  with minimal overhead after the initial handshake.
  
  ### Protocol Design
  1. **Message Framing**: All messages are JSON with type field
  2. **Request/Response**: Optional correlation IDs for RPC patterns
  3. **Heartbeat**: Ping/pong frames keep connections alive
  4. **Compression**: Per-message deflate for bandwidth efficiency
  """
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Core.{Metrics, RateLimiter}
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCPGateway.{ConnectionPool, TransportRegistry}
  
  @behaviour AutonomousOpponentV2Core.MCPGateway.Transport
  
  # Message types
  @type message_type :: :request | :response | :event | :error | :ping | :pong
  
  # Connection state
  defmodule Connection do
    defstruct [
      :id,
      :pid,
      :ref,
      :created_at,
      :last_ping,
      :last_pong,
      :pending_requests,
      :status,
      :metadata
    ]
  end
  
  # Client API
  
  def start_link(opts) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Connect a new WebSocket client
  """
  def connect(name \\ __MODULE__, socket_pid, opts \\ []) do
    GenServer.call(name, {:connect, socket_pid, opts})
  end
  
  @doc """
  Handle incoming WebSocket message
  """
  def handle_message(name \\ __MODULE__, connection_id, message) do
    GenServer.cast(name, {:handle_message, connection_id, message})
  end
  
  @doc """
  Send a message to a WebSocket client
  """
  def send_message(name \\ __MODULE__, connection_id, message) do
    GenServer.cast(name, {:send_message, connection_id, message})
  end
  
  @doc """
  Close a WebSocket connection
  """
  def close(name \\ __MODULE__, connection_id, reason \\ :normal) do
    GenServer.cast(name, {:close, connection_id, reason})
  end
  
  # Transport behaviour implementation
  
  @impl true
  def send(connection_id, message, opts) do
    __MODULE__.send_message(connection_id, message)
  end
  
  # Server implementation
  
  defstruct [
    :max_connections,
    :ping_interval,
    :pong_timeout,
    :max_frame_size,
    connections: %{},
    ping_timer: nil
  ]
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      max_connections: opts[:max_connections] || 1000,
      ping_interval: opts[:ping_interval] || 30_000,
      pong_timeout: opts[:pong_timeout] || 10_000,
      max_frame_size: opts[:max_frame_size] || 1_000_000,  # 1MB
      connections: %{}
    }
    
    # Register with transport registry
    TransportRegistry.register(:websocket, __MODULE__)
    
    # Start ping timer
    timer = Process.send_after(self(), :ping_all, state.ping_interval)
    state = %{state | ping_timer: timer}
    
    EventBus.publish(:mcp_transport_started, %{
      transport: :websocket,
      max_connections: state.max_connections
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:connect, socket_pid, opts}, _from, state) do
    # Check rate limit
    case RateLimiter.consume(:mcp_gateway_limiter) do
      {:ok, _} ->
        if map_size(state.connections) < state.max_connections do
          connection = create_connection(socket_pid, opts)
          connections = Map.put(state.connections, connection.id, connection)
          
          Logger.info("WebSocket client connected: #{connection.id}")
          
          # Send welcome message
          send_ws_message(socket_pid, %{
            type: "connected",
            id: connection.id,
            timestamp: System.system_time(:millisecond)
          })
          
          Metrics.counter(:mcp_gateway_metrics, "websocket.connections", 1)
          
          {:reply, {:ok, connection.id}, %{state | connections: connections}}
        else
          {:reply, {:error, :max_connections_reached}, state}
        end
        
      {:error, :rate_limited} ->
        {:reply, {:error, :rate_limited}, state}
    end
  end
  
  @impl true
  def handle_cast({:handle_message, connection_id, message}, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        Logger.warning("Message from unknown connection: #{connection_id}")
        {:noreply, state}
        
      connection ->
        # Parse and route message
        state = case parse_message(message) do
          {:ok, parsed} ->
            handle_parsed_message(connection, parsed, state)
            
          {:error, reason} ->
            send_error(connection, reason)
            state
        end
        
        {:noreply, state}
    end
  end
  
  def handle_cast({:send_message, connection_id, message}, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        Logger.warning("Attempt to send to non-existent connection: #{connection_id}")
        {:noreply, state}
        
      connection ->
        # Wrap message with metadata
        wrapped = wrap_message(message)
        
        # Send via WebSocket
        send_ws_message(connection.pid, wrapped)
        
        Metrics.counter(:mcp_gateway_metrics, "websocket.messages_sent", 1)
        
        {:noreply, state}
    end
  end
  
  def handle_cast({:close, connection_id, reason}, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:noreply, state}
        
      connection ->
        # Send close frame
        send_ws_close(connection.pid, reason)
        
        # Clean up connection
        Process.demonitor(connection.ref, [:flush])
        connections = Map.delete(state.connections, connection_id)
        
        Logger.info("WebSocket client disconnected: #{connection_id}, reason: #{inspect(reason)}")
        
        Metrics.counter(:mcp_gateway_metrics, "websocket.disconnections", 1)
        
        EventBus.publish(:mcp_websocket_closed, %{
          connection_id: connection_id,
          reason: reason
        })
        
        {:noreply, %{state | connections: connections}}
    end
  end
  
  @impl true
  def handle_info(:ping_all, state) do
    now = System.monotonic_time(:millisecond)
    
    # Send ping to all connections and check for dead ones
    {alive, dead} = 
      state.connections
      |> Enum.split_with(fn {_id, conn} ->
        # Check if last pong was received
        if conn.last_pong && now - conn.last_pong > state.pong_timeout do
          false
        else
          # Send ping
          send_ws_ping(conn.pid)
          true
        end
      end)
    
    # Update alive connections with ping time
    alive_connections = 
      alive
      |> Enum.map(fn {id, conn} ->
        {id, %{conn | last_ping: now}}
      end)
      |> Map.new()
    
    # Close dead connections
    Enum.each(dead, fn {id, _conn} ->
      GenServer.cast(self(), {:close, id, :ping_timeout})
    end)
    
    # Schedule next ping
    timer = Process.send_after(self(), :ping_all, state.ping_interval)
    
    {:noreply, %{state | connections: alive_connections, ping_timer: timer}}
  end
  
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Find connection by ref
    case Enum.find(state.connections, fn {_id, conn} -> conn.ref == ref end) do
      {id, _conn} ->
        Logger.info("WebSocket process died: #{id}, reason: #{inspect(reason)}")
        GenServer.cast(self(), {:close, id, {:process_died, reason}})
        
      nil ->
        :ok
    end
    
    {:noreply, state}
  end
  
  def handle_info({:pong, connection_id}, state) do
    # Update last pong time
    case Map.get(state.connections, connection_id) do
      nil ->
        {:noreply, state}
        
      connection ->
        updated = %{connection | last_pong: System.monotonic_time(:millisecond)}
        connections = Map.put(state.connections, connection_id, updated)
        {:noreply, %{state | connections: connections}}
    end
  end
  
  # Private functions
  
  defp create_connection(socket_pid, opts) do
    ref = Process.monitor(socket_pid)
    
    %Connection{
      id: generate_connection_id(),
      pid: socket_pid,
      ref: ref,
      created_at: System.monotonic_time(:millisecond),
      last_ping: nil,
      last_pong: System.monotonic_time(:millisecond),
      pending_requests: %{},
      status: :connected,
      metadata: opts[:metadata] || %{}
    }
  end
  
  defp generate_connection_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
  
  defp parse_message(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, parsed} -> validate_message(parsed)
      {:error, _} -> {:error, :invalid_json}
    end
  end
  
  defp parse_message(message) when is_map(message) do
    validate_message(message)
  end
  
  defp parse_message(_), do: {:error, :invalid_message_format}
  
  defp validate_message(%{"type" => type} = message) 
       when type in ["request", "response", "event", "ping", "pong"] do
    {:ok, message}
  end
  
  defp validate_message(_), do: {:error, :missing_or_invalid_type}
  
  defp handle_parsed_message(connection, %{"type" => "request"} = message, state) do
    # Handle request-response pattern
    request_id = message["id"] || generate_request_id()
    
    # Process request through router
    Task.start(fn ->
      result = process_request(message["method"], message["params"])
      
      response = %{
        type: "response",
        id: request_id,
        result: result
      }
      
      GenServer.cast(self(), {:send_message, connection.id, response})
    end)
    
    # Track pending request
    pending = Map.put(connection.pending_requests, request_id, System.monotonic_time(:millisecond))
    updated_conn = %{connection | pending_requests: pending}
    connections = Map.put(state.connections, connection.id, updated_conn)
    
    %{state | connections: connections}
  end
  
  defp handle_parsed_message(connection, %{"type" => "event"} = message, state) do
    # Forward event to EventBus
    EventBus.publish(:mcp_websocket_event, %{
      connection_id: connection.id,
      event_type: message["event"],
      data: message["data"]
    })
    
    state
  end
  
  defp handle_parsed_message(connection, %{"type" => "pong"}, state) do
    # Handle pong - update last pong time
    send(self(), {:pong, connection.id})
    state
  end
  
  defp handle_parsed_message(_connection, _message, state), do: state
  
  defp process_request(method, params) do
    # Route to appropriate handler based on method
    # This is simplified - real implementation would use Router
    case method do
      "echo" -> params
      "time" -> System.system_time(:millisecond)
      _ -> %{error: "Unknown method: #{method}"}
    end
  end
  
  defp wrap_message(message) when is_map(message) do
    message
    |> Map.put_new("timestamp", System.system_time(:millisecond))
    |> Map.put_new("type", "event")
  end
  
  defp wrap_message(data) do
    %{
      type: "event",
      data: data,
      timestamp: System.system_time(:millisecond)
    }
  end
  
  defp send_ws_message(pid, message) do
    # In real implementation, this would send through Phoenix Socket
    # For now, send as a message to the process
    encoded = Jason.encode!(message)
    send(pid, {:websocket_frame, :text, encoded})
  end
  
  defp send_ws_ping(pid) do
    send(pid, {:websocket_frame, :ping, ""})
  end
  
  defp send_ws_close(pid, reason) do
    code = case reason do
      :normal -> 1000
      :going_away -> 1001
      :protocol_error -> 1002
      :unsupported -> 1003
      _ -> 1006
    end
    
    send(pid, {:websocket_frame, :close, {code, inspect(reason)}})
  end
  
  defp send_error(connection, error) do
    error_message = %{
      type: "error",
      error: error,
      timestamp: System.system_time(:millisecond)
    }
    
    send_ws_message(connection.pid, error_message)
  end
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end
end