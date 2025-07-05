defmodule AutonomousOpponentV2Core.WebGateway.Transport.WebSocket do
  @moduledoc """
  WebSocket transport implementation for Web Gateway.
  
  Provides bidirectional real-time communication with automatic reconnection,
  ping/pong heartbeat, and binary/text frame support.
  """
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.WebGateway.Gateway
  alias AutonomousOpponentV2Core.WebGateway.Pool.ConnectionPool
  alias AutonomousOpponentV2Core.Core.{CircuitBreaker, RateLimiter}
  
  require Logger
  
  @ping_interval 30_000       # 30 seconds
  @pong_timeout 10_000        # 10 seconds
  @compression_threshold 1024  # Compress messages larger than 1KB
  
  defmodule Connection do
    @moduledoc """
    Represents a WebSocket connection with client metadata and state.
    """
    defstruct [
      :id,
      :socket_pid,
      :client_id,
      :connected_at,
      :last_ping,
      :last_pong,
      :metadata,
      :compression_enabled,
      :binary_mode,
      :rate_limiter_ref
    ]
  end
  
  use GenServer
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a new WebSocket connection.
  """
  def register_connection(socket_pid, client_id, opts \\ []) do
    GenServer.call(__MODULE__, {:register, socket_pid, client_id, opts})
  end
  
  @doc """
  Unregisters a WebSocket connection.
  """
  def unregister_connection(conn_id) do
    GenServer.cast(__MODULE__, {:unregister, conn_id})
  end
  
  @doc """
  Handles incoming message from a WebSocket client.
  """
  def handle_message(conn_id, message) do
    GenServer.cast(__MODULE__, {:handle_message, conn_id, message})
  end
  
  @doc """
  Sends a message to a specific client.
  """
  def send_message(client_id, message, opts \\ []) do
    GenServer.cast(__MODULE__, {:send_message, client_id, message, opts})
  end
  
  @doc """
  Broadcasts a message to all connected clients.
  """
  def broadcast_message(message, opts \\ []) do
    GenServer.cast(__MODULE__, {:broadcast, message, opts})
  end
  
  @doc """
  Handles pong response from client.
  """
  def handle_pong(conn_id) do
    GenServer.cast(__MODULE__, {:pong_received, conn_id})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    
    # Start ping timer
    Process.send_after(self(), :send_pings, @ping_interval)
    
    # Subscribe to VSM events
    EventBus.subscribe(:vsm_broadcast)
    EventBus.subscribe(:web_gateway_websocket_events)
    
    state = %{
      connections: %{},
      client_connections: %{},  # client_id -> [connection_ids]
      pending_pongs: %{},        # conn_id -> timer_ref
      stats: %{
        total_connections: 0,
        messages_sent: 0,
        messages_received: 0,
        errors: 0,
        bytes_sent: 0,
        bytes_received: 0
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register, socket_pid, client_id, opts}, _from, state) do
    conn_id = UUID.uuid4()
    
    # Initialize rate limiter for this connection
    {:ok, rate_limiter_ref} = RateLimiter.start_link(
      max_tokens: Keyword.get(opts, :rate_limit, 100),
      refill_rate: Keyword.get(opts, :rate_limit, 100)
    )
    
    connection = %Connection{
      id: conn_id,
      socket_pid: socket_pid,
      client_id: client_id,
      connected_at: DateTime.utc_now(),
      last_ping: DateTime.utc_now(),
      last_pong: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{}),
      compression_enabled: Keyword.get(opts, :compression, true),
      binary_mode: Keyword.get(opts, :binary, false),
      rate_limiter_ref: rate_limiter_ref
    }
    
    # Monitor the socket process
    Process.monitor(socket_pid)
    
    # Update state
    connections = Map.put(state.connections, conn_id, connection)
    
    client_conns = Map.update(
      state.client_connections,
      client_id,
      [conn_id],
      &[conn_id | &1]
    )
    
    stats = Map.update(state.stats, :total_connections, 1, &(&1 + 1))
    
    new_state = %{state |
      connections: connections,
      client_connections: client_conns,
      stats: stats
    }
    
    # Report to VSM
    report_connection_metrics(new_state)
    
    # Get connection from pool
    ConnectionPool.checkout(conn_id)
    
    Logger.info("WebSocket connection registered: #{conn_id} for client: #{client_id}")
    
    {:reply, {:ok, conn_id}, new_state}
  end
  
  @impl true
  def handle_cast({:unregister, conn_id}, state) do
    case Map.get(state.connections, conn_id) do
      nil -> 
        {:noreply, state}
        
      connection ->
        # Clean up rate limiter
        if connection.rate_limiter_ref do
          GenServer.stop(connection.rate_limiter_ref)
        end
        
        # Return connection to pool
        ConnectionPool.checkin(conn_id)
        
        # Cancel pending pong timer
        case Map.get(state.pending_pongs, conn_id) do
          nil -> :ok
          timer_ref -> Process.cancel_timer(timer_ref)
        end
        
        # Remove from connections
        connections = Map.delete(state.connections, conn_id)
        pending_pongs = Map.delete(state.pending_pongs, conn_id)
        
        # Remove from client connections
        client_conns = Map.update(
          state.client_connections,
          connection.client_id,
          [],
          &Enum.reject(&1, fn id -> id == conn_id end)
        )
        
        new_state = %{state |
          connections: connections,
          client_connections: client_conns,
          pending_pongs: pending_pongs
        }
        
        Logger.info("WebSocket connection unregistered: #{conn_id}")
        
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_cast({:handle_message, conn_id, message}, state) do
    case Map.get(state.connections, conn_id) do
      nil ->
        {:noreply, state}
        
      connection ->
        # Check rate limit
        case RateLimiter.check_rate(connection.rate_limiter_ref, 1) do
          :ok ->
            process_incoming_message(connection, message, state)
            
          {:error, :rate_limited} ->
            send_error(connection.socket_pid, "rate_limit_exceeded")
            
            # Report to VSM
            Gateway.trigger_algedonic(:medium, {:rate_limit_exceeded, conn_id})
            
            stats = Map.update(state.stats, :errors, 1, &(&1 + 1))
            {:noreply, %{state | stats: stats}}
        end
    end
  end
  
  @impl true
  def handle_cast({:send_message, client_id, message, opts}, state) do
    case Map.get(state.client_connections, client_id) do
      nil ->
        {:noreply, state}
        
      conn_ids ->
        stats = Enum.reduce(conn_ids, state.stats, fn conn_id, acc_stats ->
          case send_to_connection(conn_id, message, opts, state) do
            {:ok, bytes_sent} ->
              acc_stats
              |> Map.update(:messages_sent, 1, &(&1 + 1))
              |> Map.update(:bytes_sent, bytes_sent, &(&1 + bytes_sent))
              
            :error ->
              Map.update(acc_stats, :errors, 1, &(&1 + 1))
          end
        end)
        
        {:noreply, %{state | stats: stats}}
    end
  end
  
  @impl true
  def handle_cast({:broadcast, message, opts}, state) do
    {total_sent, total_bytes} = Enum.reduce(state.connections, {0, 0}, fn {_conn_id, connection}, {sent, bytes} ->
      case send_ws_message(connection, message, opts) do
        {:ok, bytes_sent} -> {sent + 1, bytes + bytes_sent}
        :error -> {sent, bytes}
      end
    end)
    
    stats = state.stats
    |> Map.update(:messages_sent, total_sent, &(&1 + total_sent))
    |> Map.update(:bytes_sent, total_bytes, &(&1 + total_bytes))
    
    {:noreply, %{state | stats: stats}}
  end
  
  @impl true
  def handle_cast(:stop_accepting_connections, state) do
    Logger.info("WebSocket transport stopping new connections")
    # In a real implementation, this would update a flag checked by the channel
    {:noreply, Map.put(state, :accepting_connections, false)}
  end

  @impl true
  def handle_cast({:pong_received, conn_id}, state) do
    # Cancel timeout timer
    case Map.get(state.pending_pongs, conn_id) do
      nil -> 
        {:noreply, state}
        
      timer_ref ->
        Process.cancel_timer(timer_ref)
        
        # Update last pong time
        connections = put_in(state.connections[conn_id].last_pong, DateTime.utc_now())
        pending_pongs = Map.delete(state.pending_pongs, conn_id)
        
        {:noreply, %{state | connections: connections, pending_pongs: pending_pongs}}
    end
  end
  
  @impl true
  def handle_info(:send_pings, state) do
    timestamp = DateTime.utc_now()
    
    # Send ping to all connections and set up pong timeouts
    pending_pongs = Enum.reduce(state.connections, state.pending_pongs, fn {conn_id, connection}, acc ->
      if send_ping(connection.socket_pid) do
        # Set up pong timeout
        timer_ref = Process.send_after(self(), {:pong_timeout, conn_id}, @pong_timeout)
        
        # Update last ping time
        put_in(state.connections[conn_id].last_ping, timestamp)
        
        Map.put(acc, conn_id, timer_ref)
      else
        acc
      end
    end)
    
    # Schedule next ping round
    Process.send_after(self(), :send_pings, @ping_interval)
    
    {:noreply, %{state | pending_pongs: pending_pongs}}
  end
  
  @impl true
  def handle_info({:pong_timeout, conn_id}, state) do
    Logger.warning("WebSocket pong timeout for connection: #{conn_id}")
    
    # Connection is considered dead, unregister it
    handle_cast({:unregister, conn_id}, state)
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Find and remove the connection
    {conn_id, _connection} = Enum.find(state.connections, fn {_id, conn} ->
      conn.socket_pid == pid
    end) || {nil, nil}
    
    if conn_id do
      Logger.info("WebSocket process down: #{conn_id}")
      handle_cast({:unregister, conn_id}, state)
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event_bus, :vsm_broadcast, data}, state) do
    # Forward VSM broadcasts to all WebSocket clients
    broadcast_message(%{type: "vsm_update", data: data})
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event_bus, :web_gateway_websocket_events, message}, state) do
    # Forward Web Gateway events to WebSocket clients
    broadcast_message(message)
    {:noreply, state}
  end
  
  # Private functions
  
  defp process_incoming_message(connection, message, state) do
    # Parse message based on mode
    parsed = if connection.binary_mode do
      parse_binary_message(message)
    else
      parse_text_message(message)
    end
    
    case parsed do
      {:ok, %{type: type, data: data}} ->
        # Update stats
        message_size = byte_size(message)
        stats = state.stats
        |> Map.update(:messages_received, 1, &(&1 + 1))
        |> Map.update(:bytes_received, message_size, &(&1 + message_size))
        
        # Publish to EventBus for processing
        EventBus.publish(:web_gateway_message_received, %{
          conn_id: connection.id,
          client_id: connection.client_id,
          type: type,
          data: data,
          transport: :websocket
        })
        
        {:noreply, %{state | stats: stats}}
        
      {:error, reason} ->
        Logger.error("Failed to parse WebSocket message: #{inspect(reason)}")
        send_error(connection.socket_pid, "invalid_message")
        
        stats = Map.update(state.stats, :errors, 1, &(&1 + 1))
        {:noreply, %{state | stats: stats}}
    end
  end
  
  defp send_to_connection(conn_id, message, opts, state) do
    case Map.get(state.connections, conn_id) do
      nil -> 
        :error
        
      connection ->
        send_ws_message(connection, message, opts)
    end
  end
  
  defp send_ws_message(connection, message, opts) do
    try do
      # Encode message
      encoded = encode_message(message, connection, opts)
      
      # Send via circuit breaker
      case CircuitBreaker.call(:websocket_send, fn ->
        send(connection.socket_pid, {:ws_send, encoded})
        {:ok, byte_size(encoded)}
      end) do
        {:ok, result} -> result
        {:error, _} -> :error
      end
    catch
      _, _ -> :error
    end
  end
  
  defp encode_message(message, connection, _opts) do
    # Convert to JSON if needed
    json_message = if is_binary(message), do: message, else: Jason.encode!(message)
    
    # Apply compression if enabled and message is large enough
    if connection.compression_enabled && byte_size(json_message) > @compression_threshold do
      :zlib.compress(json_message)
    else
      json_message
    end
  end
  
  defp parse_text_message(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, %{"type" => type, "data" => data}} ->
        {:ok, %{type: type, data: data}}
        
      {:ok, _} ->
        {:error, :invalid_format}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp parse_binary_message(message) when is_binary(message) do
    # Attempt to decompress first
    decompressed = try do
      :zlib.uncompress(message)
    catch
      _, _ -> message
    end
    
    parse_text_message(decompressed)
  end
  
  defp send_ping(socket_pid) do
    try do
      send(socket_pid, :ws_ping)
      true
    catch
      _, _ -> false
    end
  end
  
  defp send_error(socket_pid, error) do
    try do
      error_msg = Jason.encode!(%{type: "error", error: error})
      send(socket_pid, {:ws_send, error_msg})
    catch
      _, _ -> :ok
    end
  end
  
  defp report_connection_metrics(state) do
    metrics = %{
      transport: :websocket,
      active_connections: map_size(state.connections),
      unique_clients: map_size(state.client_connections),
      messages_sent: state.stats.messages_sent,
      messages_received: state.stats.messages_received,
      bytes_sent: state.stats.bytes_sent,
      bytes_received: state.stats.bytes_received,
      errors: state.stats.errors
    }
    
    Gateway.report_metrics(metrics)
  end
  
  @doc """
  Stops accepting new WebSocket connections.
  Used during graceful shutdown.
  """
  def stop_accepting_connections do
    GenServer.cast(__MODULE__, :stop_accepting_connections)
  end
  
end