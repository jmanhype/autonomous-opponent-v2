defmodule AutonomousOpponentV2Core.MCP.Transport.Stdio do
  @moduledoc """
  STDIO transport for MCP (Model Context Protocol).
  
  Handles JSON-RPC messages via standard input/output for CLI tool integration.
  This is the reference implementation for MCP transports.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.MCP.{Server, Message}
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def send_message(pid, message) do
    GenServer.cast(pid, {:send_message, message})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    Logger.info("Starting MCP STDIO transport")
    
    # Get or start the MCP server
    server_pid = Process.whereis(Server) || raise "MCP Server not running"
    
    state = %{
      server_pid: server_pid,
      buffer: ""
    }
    
    # Start reading from STDIN in a separate process
    spawn_link(fn -> read_loop(self()) end)
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:send_message, message}, state) do
    # Encode and write to STDOUT
    case Jason.encode(message) do
      {:ok, json} ->
        IO.puts(json)
        
      {:error, reason} ->
        Logger.error("Failed to encode MCP message: #{inspect(reason)}")
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:stdin, data}, state) do
    # Accumulate data in buffer
    buffer = state.buffer <> data
    
    # Try to parse complete JSON messages
    {messages, remaining_buffer} = extract_messages(buffer)
    
    # Process each complete message
    Enum.each(messages, fn msg ->
      process_message(msg, state.server_pid)
    end)
    
    {:noreply, %{state | buffer: remaining_buffer}}
  end
  
  @impl true
  def handle_info({:mcp_response, response}, state) do
    # Send response back via STDOUT
    send_message(self(), response)
    {:noreply, state}
  end
  
  # Private Functions
  
  defp read_loop(parent_pid) do
    case IO.gets("") do
      :eof ->
        Logger.info("STDIO transport: EOF received, shutting down")
        Process.exit(parent_pid, :normal)
        
      {:error, reason} ->
        Logger.error("STDIO transport read error: #{inspect(reason)}")
        Process.exit(parent_pid, {:error, reason})
        
      data when is_binary(data) ->
        send(parent_pid, {:stdin, data})
        read_loop(parent_pid)
    end
  end
  
  defp extract_messages(buffer) do
    # Split by newlines and try to parse each line as JSON
    lines = String.split(buffer, "\n", trim: true)
    
    {messages, unparsed} = Enum.reduce(lines, {[], []}, fn line, {msgs, unparsed} ->
      case Jason.decode(line) do
        {:ok, msg} -> {msgs ++ [msg], unparsed}
        {:error, _} -> {msgs, unparsed ++ [line]}
      end
    end)
    
    remaining_buffer = Enum.join(unparsed, "\n")
    {messages, remaining_buffer}
  end
  
  defp process_message(message, server_pid) do
    # Forward to MCP server and register this transport for responses
    case GenServer.call(server_pid, {:handle_message_with_transport, message, self()}) do
      {:ok, response} when not is_nil(response) ->
        send_message(self(), response)
      _ ->
        :ok
    end
  end
  
  # Make it work with DynamicSupervisor
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
end