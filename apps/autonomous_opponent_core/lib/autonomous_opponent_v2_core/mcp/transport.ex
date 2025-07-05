defmodule AutonomousOpponentV2Core.MCP.Transport do
  @moduledoc """
  Transport layer abstraction for MCP (Model Context Protocol).
  
  Supports multiple transport mechanisms:
  - Standard I/O (stdio) - For CLI tools and direct connections
  - Server-Sent Events (SSE) - For web-based clients
  - WebSocket - For real-time bidirectional communication
  
  Each transport handles message framing and delivery while maintaining
  the same MCP message interface.
  """
  
  require Logger
  
  @type transport_type :: :stdio | :sse | :websocket
  @type transport_opts :: keyword()
  @type transport :: %{
    type: transport_type(),
    pid: pid(),
    opts: transport_opts()
  }
  
  @doc """
  Starts a transport of the specified type.
  """
  @spec start(transport_type(), transport_opts()) :: {:ok, transport()} | {:error, term()}
  def start(transport_type, opts \\ []) do
    case transport_type do
      :stdio ->
        start_stdio_transport(opts)
        
      :sse ->
        start_sse_transport(opts)
        
      :websocket ->
        start_websocket_transport(opts)
        
      _ ->
        {:error, {:unsupported_transport, transport_type}}
    end
  end
  
  @doc """
  Sends a message through the transport.
  """
  @spec send_message(transport(), map()) :: :ok | {:error, term()}
  def send_message(%{type: :stdio, pid: pid}, message) do
    AutonomousOpponentV2Core.MCP.Transport.Stdio.send_message(pid, message)
  end
  
  def send_message(%{type: :sse, pid: pid}, message) do
    AutonomousOpponentV2Core.MCP.Transport.SSE.send_message(pid, message)
  end
  
  def send_message(%{type: :websocket, pid: pid}, message) do
    AutonomousOpponentV2Core.MCP.Transport.WebSocket.send_message(pid, message)
  end
  
  @doc """
  Closes the transport connection.
  """
  @spec close(transport()) :: :ok
  def close(%{pid: pid}) do
    GenServer.stop(pid, :normal)
    :ok
  end
  
  # Private Functions
  
  defp start_stdio_transport(opts) do
    case AutonomousOpponentV2Core.MCP.Transport.Stdio.start_link(opts) do
      {:ok, pid} ->
        {:ok, %{type: :stdio, pid: pid, opts: opts}}
        
      error ->
        error
    end
  end
  
  defp start_sse_transport(opts) do
    case AutonomousOpponentV2Core.MCP.Transport.SSE.start_link(opts) do
      {:ok, pid} ->
        {:ok, %{type: :sse, pid: pid, opts: opts}}
        
      error ->
        error
    end
  end
  
  defp start_websocket_transport(opts) do
    case AutonomousOpponentV2Core.MCP.Transport.WebSocket.start_link(opts) do
      {:ok, pid} ->
        {:ok, %{type: :websocket, pid: pid, opts: opts}}
        
      error ->
        error
    end
  end
end


defmodule AutonomousOpponentV2Core.MCP.Transport.SSE do
  @moduledoc """
  Server-Sent Events transport for MCP.
  
  Provides HTTP endpoint for MCP over SSE. Clients connect via HTTP
  and receive messages as Server-Sent Events. Requests are sent via
  separate HTTP POST requests.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.MCP.{Message, Server}
  
  defstruct [:port, :clients]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def send_message(pid, message) do
    GenServer.cast(pid, {:send_message, message})
  end
  
  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 8080)
    
    # Start HTTP server for SSE endpoint
    {:ok, _} = Plug.Cowboy.http(__MODULE__.Router, [], port: port)
    
    Logger.info("MCP SSE transport started on port #{port}")
    {:ok, %__MODULE__{port: port, clients: []}}
  end
  
  @impl true
  def handle_cast({:send_message, message}, state) do
    case Message.serialize(message) do
      {:ok, json} ->
        # Send to all connected SSE clients
        Enum.each(state.clients, fn client_pid ->
          send(client_pid, {:sse_message, json})
        end)
        
      {:error, reason} ->
        Logger.error("Failed to serialize SSE message: #{inspect(reason)}")
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_call({:add_client, client_pid}, _from, state) do
    new_clients = [client_pid | state.clients]
    {:reply, :ok, %{state | clients: new_clients}}
  end
  
  @impl true
  def handle_call({:remove_client, client_pid}, _from, state) do
    new_clients = List.delete(state.clients, client_pid)
    {:reply, :ok, %{state | clients: new_clients}}
  end
  
  defmodule Router do
    use Plug.Router
    
    plug Plug.Logger
    plug :match
    plug Plug.Parsers, parsers: [:json], json_decoder: Jason
    plug :dispatch
    
    get "/mcp/sse" do
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("access-control-allow-origin", "*")
      |> send_chunked(200)
      |> handle_sse_connection()
    end
    
    post "/mcp/message" do
      case conn.body_params do
        %{} = message ->
          # Handle MCP request
          case Message.serialize(message) do
            {:ok, json} ->
              Server.handle_message(json)
              send_resp(conn, 200, "OK")
              
            {:error, _} ->
              send_resp(conn, 400, "Invalid message format")
          end
          
        _ ->
          send_resp(conn, 400, "Invalid JSON")
      end
    end
    
    match _ do
      send_resp(conn, 404, "Not found")
    end
    
    defp handle_sse_connection(conn) do
      # Send initial connection message
      {:ok, conn} = chunk(conn, "data: {\"type\":\"connected\"}\n\n")
      
      # Add this connection to the client list
      GenServer.call(AutonomousOpponentV2Core.MCP.Transport.SSE, {:add_client, self()})
      
      sse_loop(conn)
    end
    
    defp sse_loop(conn) do
      receive do
        {:sse_message, json} ->
          case chunk(conn, "data: #{json}\n\n") do
            {:ok, conn} ->
              sse_loop(conn)
              
            {:error, _} ->
              # Client disconnected
              GenServer.call(AutonomousOpponentV2Core.MCP.Transport.SSE, {:remove_client, self()})
              conn
          end
          
      after
        30_000 ->
          # Send keepalive
          case chunk(conn, "data: {\"type\":\"keepalive\"}\n\n") do
            {:ok, conn} ->
              sse_loop(conn)
              
            {:error, _} ->
              GenServer.call(AutonomousOpponentV2Core.MCP.Transport.SSE, {:remove_client, self()})
              conn
          end
      end
    end
  end
end

defmodule AutonomousOpponentV2Core.MCP.Transport.WebSocket do
  @moduledoc """
  WebSocket transport for MCP.
  
  Integrates with the existing Web Gateway WebSocket infrastructure
  to provide MCP protocol over WebSocket connections.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.MCP.{Message, Server}
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def send_message(pid, message) do
    GenServer.cast(pid, {:send_message, message})
  end
  
  @impl true
  def init(opts) do
    # Subscribe to WebSocket events from Web Gateway
    Phoenix.PubSub.subscribe(AutonomousOpponentV2.PubSub, "websocket:mcp")
    
    Logger.info("MCP WebSocket transport started")
    {:ok, %{clients: %{}, opts: opts}}
  end
  
  @impl true
  def handle_cast({:send_message, message}, state) do
    case Message.serialize(message) do
      {:ok, json} ->
        # Broadcast to all MCP WebSocket clients
        Enum.each(state.clients, fn {socket_id, _info} ->
          AutonomousOpponentWeb.Endpoint.broadcast("websocket:#{socket_id}", "mcp_message", %{data: json})
        end)
        
      {:error, reason} ->
        Logger.error("Failed to serialize WebSocket message: #{inspect(reason)}")
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:websocket_connect, socket_id, client_info}, state) do
    new_clients = Map.put(state.clients, socket_id, client_info)
    Logger.info("MCP WebSocket client connected: #{socket_id}")
    {:noreply, %{state | clients: new_clients}}
  end
  
  @impl true
  def handle_info({:websocket_disconnect, socket_id}, state) do
    new_clients = Map.delete(state.clients, socket_id)
    Logger.info("MCP WebSocket client disconnected: #{socket_id}")
    {:noreply, %{state | clients: new_clients}}
  end
  
  @impl true
  def handle_info({:websocket_message, _socket_id, message}, state) do
    # Handle incoming MCP message from WebSocket client
    Server.handle_message(message)
    {:noreply, state}
  end
end