defmodule AutonomousOpponentV2Core.MCP.Transport.HTTPSSE do
  @moduledoc """
  HTTP+SSE (Server-Sent Events) transport implementation for MCP Gateway.
  
  Provides real-time unidirectional communication from server to clients
  with automatic reconnection and heartbeat support.
  """
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCP.Gateway
  alias AutonomousOpponentV2Core.MCP.Pool.ConnectionPool
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  
  require Logger
  
  @heartbeat_interval 30_000  # 30 seconds
  @max_retry_attempts 5
  @base_backoff 1_000         # 1 second
  @max_backoff 60_000         # 60 seconds
  
  defmodule Connection do
    @moduledoc """
    Represents an SSE connection with client metadata.
    """
    defstruct [:id, :pid, :client_id, :connected_at, :last_heartbeat, :metadata]
  end
  
  use GenServer
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a new SSE connection.
  """
  def register_connection(conn_pid, client_id, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register, conn_pid, client_id, metadata})
  end
  
  @doc """
  Unregisters an SSE connection.
  """
  def unregister_connection(conn_id) do
    GenServer.cast(__MODULE__, {:unregister, conn_id})
  end
  
  @doc """
  Sends an event to a specific client.
  """
  def send_event(client_id, event_type, data) do
    GenServer.cast(__MODULE__, {:send_event, client_id, event_type, data})
  end
  
  @doc """
  Broadcasts an event to all connected clients.
  """
  def broadcast_event(event_type, data) do
    GenServer.cast(__MODULE__, {:broadcast, event_type, data})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    
    # Start heartbeat timer
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
    
    # Subscribe to VSM events
    EventBus.subscribe(:vsm_broadcast)
    EventBus.subscribe(:mcp_sse_events)
    
    state = %{
      connections: %{},
      client_connections: %{},  # client_id -> [connection_ids]
      stats: %{
        total_connections: 0,
        messages_sent: 0,
        errors: 0
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register, conn_pid, client_id, metadata}, _from, state) do
    conn_id = UUID.uuid4()
    
    connection = %Connection{
      id: conn_id,
      pid: conn_pid,
      client_id: client_id,
      connected_at: DateTime.utc_now(),
      last_heartbeat: DateTime.utc_now(),
      metadata: metadata
    }
    
    # Monitor the connection process
    Process.monitor(conn_pid)
    
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
    
    Logger.info("SSE connection registered: #{conn_id} for client: #{client_id}")
    
    {:reply, {:ok, conn_id}, new_state}
  end
  
  @impl true
  def handle_cast({:unregister, conn_id}, state) do
    case Map.get(state.connections, conn_id) do
      nil -> 
        {:noreply, state}
        
      connection ->
        # Remove from connections
        connections = Map.delete(state.connections, conn_id)
        
        # Remove from client connections
        client_conns = Map.update(
          state.client_connections,
          connection.client_id,
          [],
          &Enum.reject(&1, fn id -> id == conn_id end)
        )
        
        new_state = %{state |
          connections: connections,
          client_connections: client_conns
        }
        
        Logger.info("SSE connection unregistered: #{conn_id}")
        
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_cast({:send_event, client_id, event_type, data}, state) do
    case Map.get(state.client_connections, client_id) do
      nil ->
        {:noreply, state}
        
      conn_ids ->
        Enum.each(conn_ids, fn conn_id ->
          send_to_connection(conn_id, event_type, data, state)
        end)
        
        stats = Map.update(state.stats, :messages_sent, 1, &(&1 + 1))
        {:noreply, %{state | stats: stats}}
    end
  end
  
  @impl true
  def handle_cast({:broadcast, event_type, data}, state) do
    Enum.each(state.connections, fn {_conn_id, connection} ->
      send_sse_event(connection.pid, event_type, data)
    end)
    
    stats = Map.update(
      state.stats,
      :messages_sent,
      Map.size(state.connections),
      &(&1 + Map.size(state.connections))
    )
    
    {:noreply, %{state | stats: stats}}
  end
  
  @impl true
  def handle_info(:heartbeat, state) do
    # Send heartbeat to all connections
    timestamp = DateTime.utc_now()
    
    Enum.each(state.connections, fn {conn_id, connection} ->
      if send_sse_event(connection.pid, "heartbeat", %{timestamp: timestamp}) do
        # Update last heartbeat
        put_in(state.connections[conn_id].last_heartbeat, timestamp)
      else
        # Connection might be dead, will be cleaned up by monitor
        Logger.warn("Failed to send heartbeat to connection: #{conn_id}")
      end
    end)
    
    # Schedule next heartbeat
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
    
    # Report metrics
    report_connection_metrics(state)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Find and remove the connection
    {conn_id, connection} = Enum.find(state.connections, fn {_id, conn} ->
      conn.pid == pid
    end) || {nil, nil}
    
    if conn_id do
      Logger.info("SSE connection process down: #{conn_id}")
      handle_cast({:unregister, conn_id}, state)
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event_bus, :vsm_broadcast, data}, state) do
    # Forward VSM broadcasts to all SSE clients
    broadcast_event("vsm_update", data)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event_bus, :mcp_sse_events, %{event: event, data: data}}, state) do
    # Forward MCP events to SSE clients
    broadcast_event(event, data)
    {:noreply, state}
  end
  
  # Private functions
  
  defp send_to_connection(conn_id, event_type, data, state) do
    case Map.get(state.connections, conn_id) do
      nil -> 
        :ok
        
      connection ->
        send_sse_event(connection.pid, event_type, data)
    end
  end
  
  defp send_sse_event(pid, event_type, data) do
    try do
      formatted_data = format_sse_event(event_type, data)
      send(pid, {:sse_event, formatted_data})
      true
    catch
      _, _ -> false
    end
  end
  
  defp format_sse_event(event_type, data) do
    json_data = Jason.encode!(data)
    "event: #{event_type}\ndata: #{json_data}\n\n"
  end
  
  defp report_connection_metrics(state) do
    metrics = %{
      transport: :http_sse,
      active_connections: map_size(state.connections),
      unique_clients: map_size(state.client_connections),
      messages_sent: state.stats.messages_sent,
      errors: state.stats.errors
    }
    
    Gateway.report_metrics(metrics)
  end
  
  @doc """
  Stops accepting new SSE connections.
  Used during graceful shutdown.
  """
  def stop_accepting_connections do
    GenServer.cast(__MODULE__, :stop_accepting_connections)
  end
  
  @impl true
  def handle_cast(:stop_accepting_connections, state) do
    Logger.info("HTTP SSE transport stopping new connections")
    # In a real implementation, this would update a flag checked by the controller
    {:noreply, Map.put(state, :accepting_connections, false)}
  end
end