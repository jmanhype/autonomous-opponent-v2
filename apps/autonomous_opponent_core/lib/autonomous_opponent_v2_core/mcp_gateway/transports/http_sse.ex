defmodule AutonomousOpponentV2Core.MCPGateway.Transports.HTTPSSE do
  @moduledoc """
  HTTP+SSE (Server-Sent Events) transport for MCP Gateway.
  
  Provides:
  - Long-lived HTTP connections with SSE
  - Automatic reconnection handling
  - Event streaming with backpressure
  - Graceful degradation
  
  ## Wisdom Preservation
  
  ### Why SSE?
  WebSockets are bidirectional but complex. For many use cases, we only
  need server-to-client streaming. SSE provides this with simpler HTTP
  semantics, better proxy support, and automatic reconnection.
  
  ### Design Choices
  1. **Chunked Transfer**: Events stream as they arrive, no buffering
  2. **Heartbeat Events**: Keep connections alive through proxies
  3. **Event IDs**: Enable resumption after disconnection
  4. **Backpressure**: Slow clients don't block fast producers
  """
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Core.{Metrics, RateLimiter}
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCPGateway.{ConnectionPool, TransportRegistry}
  
  @behaviour AutonomousOpponentV2Core.MCPGateway.Transport
  
  # Connection state
  defmodule Connection do
    defstruct [
      :id,
      :client_ref,
      :created_at,
      :last_event_id,
      :event_buffer,
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
  Connect a new SSE client
  """
  def connect(name \\ __MODULE__, client_ref, opts \\ []) do
    GenServer.call(name, {:connect, client_ref, opts})
  end
  
  @doc """
  Send an event to a connected client
  """
  def send_event(name \\ __MODULE__, connection_id, event) do
    GenServer.cast(name, {:send_event, connection_id, event})
  end
  
  @doc """
  Close a connection
  """
  def close(name \\ __MODULE__, connection_id) do
    GenServer.cast(name, {:close, connection_id})
  end
  
  # Transport behaviour implementation
  
  @impl true
  def send(connection_id, message, opts) do
    __MODULE__.send_event(connection_id, message)
  end
  
  # Server implementation
  
  defstruct [
    :max_connections,
    :heartbeat_interval,
    :buffer_size,
    connections: %{},
    heartbeat_timer: nil
  ]
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      max_connections: opts[:max_connections] || 1000,
      heartbeat_interval: opts[:heartbeat_interval] || 30_000,
      buffer_size: opts[:buffer_size] || 100,
      connections: %{}
    }
    
    # Register with transport registry
    TransportRegistry.register(:http_sse, __MODULE__)
    
    # Start heartbeat timer
    timer = Process.send_after(self(), :heartbeat, state.heartbeat_interval)
    state = %{state | heartbeat_timer: timer}
    
    EventBus.publish(:mcp_transport_started, %{
      transport: :http_sse,
      max_connections: state.max_connections
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:connect, client_ref, opts}, _from, state) do
    # Check rate limit
    case RateLimiter.consume(:mcp_gateway_limiter) do
      {:ok, _} ->
        if map_size(state.connections) < state.max_connections do
          connection = create_connection(client_ref, opts)
          connections = Map.put(state.connections, connection.id, connection)
          
          Logger.info("SSE client connected: #{connection.id}")
          
          # Send initial connection event
          send_sse_event(client_ref, %{
            event: "connected",
            data: %{connection_id: connection.id},
            id: "0"
          })
          
          Metrics.counter(:mcp_gateway_metrics, "sse.connections", 1)
          
          {:reply, {:ok, connection.id}, %{state | connections: connections}}
        else
          {:reply, {:error, :max_connections_reached}, state}
        end
        
      {:error, :rate_limited} ->
        {:reply, {:error, :rate_limited}, state}
    end
  end
  
  @impl true
  def handle_cast({:send_event, connection_id, event}, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        Logger.warning("Attempt to send to non-existent connection: #{connection_id}")
        {:noreply, state}
        
      connection ->
        # Apply backpressure if buffer is full
        if length(connection.event_buffer) < state.buffer_size do
          # Add to buffer
          event = prepare_event(event, connection)
          updated_connection = %{connection | 
            event_buffer: connection.event_buffer ++ [event],
            last_event_id: event[:id] || connection.last_event_id
          }
          
          # Try to flush buffer
          updated_connection = flush_event_buffer(updated_connection)
          
          connections = Map.put(state.connections, connection_id, updated_connection)
          
          Metrics.counter(:mcp_gateway_metrics, "sse.events_sent", 1)
          
          {:noreply, %{state | connections: connections}}
        else
          # Buffer full - apply backpressure
          Logger.warning("SSE buffer full for connection: #{connection_id}")
          
          EventBus.publish(:mcp_sse_backpressure, %{
            connection_id: connection_id,
            buffer_size: state.buffer_size
          })
          
          {:noreply, state}
        end
    end
  end
  
  def handle_cast({:close, connection_id}, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:noreply, state}
        
      connection ->
        # Send close event
        send_sse_event(connection.client_ref, %{
          event: "close",
          data: %{reason: "requested"}
        })
        
        connections = Map.delete(state.connections, connection_id)
        
        Logger.info("SSE client disconnected: #{connection_id}")
        
        Metrics.counter(:mcp_gateway_metrics, "sse.disconnections", 1)
        
        {:noreply, %{state | connections: connections}}
    end
  end
  
  @impl true
  def handle_info(:heartbeat, state) do
    # Send heartbeat to all connections
    Enum.each(state.connections, fn {_id, connection} ->
      send_sse_event(connection.client_ref, %{
        event: "heartbeat",
        data: %{timestamp: System.system_time(:millisecond)}
      })
    end)
    
    # Check for stale connections
    now = System.monotonic_time(:millisecond)
    stale_timeout = 5 * 60 * 1000  # 5 minutes
    
    {active, stale} = 
      Map.split_with(state.connections, fn {_id, conn} ->
        now - conn.created_at < stale_timeout
      end)
    
    # Close stale connections
    Enum.each(stale, fn {id, _conn} ->
      GenServer.cast(self(), {:close, id})
    end)
    
    # Schedule next heartbeat
    timer = Process.send_after(self(), :heartbeat, state.heartbeat_interval)
    
    {:noreply, %{state | connections: active, heartbeat_timer: timer}}
  end
  
  def handle_info({:flush_buffer, connection_id}, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:noreply, state}
        
      connection ->
        updated_connection = flush_event_buffer(connection)
        connections = Map.put(state.connections, connection_id, updated_connection)
        {:noreply, %{state | connections: connections}}
    end
  end
  
  # Private functions
  
  defp create_connection(client_ref, opts) do
    %Connection{
      id: generate_connection_id(),
      client_ref: client_ref,
      created_at: System.monotonic_time(:millisecond),
      last_event_id: opts[:last_event_id],
      event_buffer: [],
      status: :connected,
      metadata: opts[:metadata] || %{}
    }
  end
  
  defp generate_connection_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
  
  defp prepare_event(event, connection) do
    # Ensure event has proper structure
    event
    |> Map.put_new(:id, next_event_id(connection))
    |> Map.put_new(:event, "message")
    |> Map.update(:data, "", &encode_data/1)
    |> Map.put_new(:retry, 5000)
  end
  
  defp next_event_id(connection) do
    case connection.last_event_id do
      nil -> "1"
      id -> 
        {num, _} = Integer.parse(id)
        Integer.to_string(num + 1)
    end
  end
  
  defp encode_data(data) when is_binary(data), do: data
  defp encode_data(data), do: Jason.encode!(data)
  
  defp flush_event_buffer(connection) do
    case connection.event_buffer do
      [] ->
        connection
        
      events ->
        # Send all buffered events
        Enum.each(events, fn event ->
          send_sse_event(connection.client_ref, event)
        end)
        
        %{connection | event_buffer: []}
    end
  end
  
  defp send_sse_event(client_ref, event) do
    # Format SSE event
    sse_data = format_sse_event(event)
    
    # Send to client (in real implementation, would use actual HTTP connection)
    # This is a placeholder - actual implementation would integrate with Phoenix
    send(client_ref, {:sse_data, sse_data})
  end
  
  defp format_sse_event(event) do
    parts = []
    
    # Add event type if specified
    if event[:event] && event[:event] != "message" do
      parts = ["event: #{event[:event]}" | parts]
    end
    
    # Add event ID
    if event[:id] do
      parts = ["id: #{event[:id]}" | parts]
    end
    
    # Add retry timeout
    if event[:retry] do
      parts = ["retry: #{event[:retry]}" | parts]
    end
    
    # Add data (can be multiline)
    data_lines = 
      event[:data]
      |> String.split("\n")
      |> Enum.map(fn line -> "data: #{line}" end)
    
    parts = parts ++ data_lines
    
    # SSE events are separated by double newline
    Enum.join(parts, "\n") <> "\n\n"
  end
end