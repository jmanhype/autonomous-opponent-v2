defmodule AutonomousOpponentV2Core.MCP.Client do
  @moduledoc """
  MCP Client for connecting to external MCP servers via STDIO.
  
  This module enables our autonomous opponent to act as an MCP client,
  connecting to external servers and integrating their capabilities
  into our VSM cybernetic framework.
  
  ## Cybernetic Integration
  External MCP servers become environmental sensors and actuators,
  expanding our system's variety absorption and environmental coupling.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.{EventBus, MCP.Message}
  # Removed unused alias S1Operations
  
  defstruct [
    :server_config,
    :port,
    :capabilities,
    :resources,
    :tools,
    :prompts,
    :connection_id,
    :buffer,
    :message_id_counter
  ]
  
  # Client API
  
  @doc """
  Starts an MCP client connection to an external server.
  
  ## Options
  - `command`: The command to run the external server
  - `args`: Arguments for the command
  - `env`: Environment variables
  - `cwd`: Working directory
  """
  def start_link(server_config, opts \\ []) do
    GenServer.start_link(__MODULE__, {server_config, opts})
  end
  
  @doc """
  Discovers capabilities of the connected server.
  """
  def discover_capabilities(pid) do
    GenServer.call(pid, :discover_capabilities)
  end
  
  @doc """
  Lists available resources from the external server.
  """
  def list_resources(pid) do
    GenServer.call(pid, :list_resources)
  end
  
  @doc """
  Lists available tools from the external server.
  """
  def list_tools(pid) do
    GenServer.call(pid, :list_tools)
  end
  
  @doc """
  Reads a specific resource from the external server.
  """
  def read_resource(pid, uri) do
    GenServer.call(pid, {:read_resource, uri})
  end
  
  @doc """
  Calls a tool on the external server.
  """
  def call_tool(pid, tool_name, arguments \\ %{}) do
    GenServer.call(pid, {:call_tool, tool_name, arguments})
  end
  
  # GenServer Callbacks
  
  @impl true
  def init({server_config, _opts}) do
    Logger.info("Starting MCP client for server: #{server_config.name}")
    
    # Generate unique connection ID
    connection_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    
    # Start the external MCP server process
    case start_external_server(server_config) do
      {:ok, port} ->
        state = %__MODULE__{
          server_config: server_config,
          port: port,
          connection_id: connection_id,
          buffer: "",
          message_id_counter: 0
        }
        
        # Initialize the connection
        send(self(), :initialize_connection)
        
        # Publish connection event to VSM
        EventBus.publish(:mcp_client_connected, %{
          server_name: server_config.name,
          connection_id: connection_id,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to start external MCP server #{server_config.name}: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_call(:discover_capabilities, _from, state) do
    case send_request(state, "initialize", %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{},
      "clientInfo" => %{
        "name" => "autonomous-opponent-vsm",
        "version" => "2.0.0"
      }
    }) do
      {:ok, response, new_state} ->
        capabilities = response["result"]["capabilities"]
        updated_state = %{new_state | capabilities: capabilities}
        {:reply, {:ok, capabilities}, updated_state}
        
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_call(:list_resources, _from, state) do
    case send_request(state, "resources/list", %{}) do
      {:ok, response, new_state} ->
        resources = response["result"]["resources"]
        updated_state = %{new_state | resources: resources}
        {:reply, {:ok, resources}, updated_state}
        
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_call(:list_tools, _from, state) do
    case send_request(state, "tools/list", %{}) do
      {:ok, response, new_state} ->
        tools = response["result"]["tools"]
        updated_state = %{new_state | tools: tools}
        {:reply, {:ok, tools}, updated_state}
        
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_call({:read_resource, uri}, _from, state) do
    case send_request(state, "resources/read", %{"uri" => uri}) do
      {:ok, response, new_state} ->
        content = response["result"]["contents"]
        
        # Publish resource data to VSM S1 for variety absorption
        EventBus.publish(:external_resource_data, %{
          server_name: state.server_config.name,
          uri: uri,
          content: content,
          timestamp: DateTime.utc_now()
        })
        
        {:reply, {:ok, content}, new_state}
        
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_call({:call_tool, tool_name, arguments}, _from, state) do
    case send_request(state, "tools/call", %{
      "name" => tool_name,
      "arguments" => arguments
    }) do
      {:ok, response, new_state} ->
        result = response["result"]
        
        # Publish tool execution result to VSM S1
        EventBus.publish(:external_tool_result, %{
          server_name: state.server_config.name,
          tool_name: tool_name,
          arguments: arguments,
          result: result,
          timestamp: DateTime.utc_now()
        })
        
        {:reply, {:ok, result}, new_state}
        
      {:error, reason, new_state} ->
        # Publish error as algedonic pain signal
        EventBus.publish(:algedonic_signal, %{
          type: :pain,
          severity: 0.7,
          valence: -0.7,
          reason: "External MCP tool call failed: #{tool_name}",
          source: :mcp_client,
          server_name: state.server_config.name,
          timestamp: DateTime.utc_now()
        })
        
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_info(:initialize_connection, state) do
    # Send initialize message to establish the connection
    case discover_capabilities(self()) do
      {:ok, _capabilities} ->
        Logger.info("MCP client connected to #{state.server_config.name}")
        {:noreply, state}
        
      {:error, reason} ->
        Logger.error("Failed to initialize MCP connection: #{inspect(reason)}")
        {:stop, :initialization_failed, state}
    end
  end
  
  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    # Accumulate data in buffer
    buffer = state.buffer <> data
    
    # Try to parse complete JSON messages
    {messages, remaining_buffer} = extract_messages(buffer)
    
    # Process each complete message
    Enum.each(messages, fn message ->
      process_response(message, state)
    end)
    
    {:noreply, %{state | buffer: remaining_buffer}}
  end
  
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("External MCP server #{state.server_config.name} exited with status #{status}")
    
    # Publish disconnection event
    EventBus.publish(:mcp_client_disconnected, %{
      server_name: state.server_config.name,
      connection_id: state.connection_id,
      exit_status: status,
      timestamp: DateTime.utc_now()
    })
    
    {:stop, :server_exit, state}
  end
  
  # Private Functions
  
  defp start_external_server(server_config) do
    command = server_config.command
    args = server_config.args || []
    env = server_config.env || %{}
    cwd = server_config.cwd || System.cwd!()
    
    # Convert env map to list of tuples
    env_list = Enum.map(env, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
    
    try do
      port = Port.open({:spawn_executable, System.find_executable(command)}, [
        :binary,
        :exit_status,
        {:args, args},
        {:env, env_list},
        {:cd, cwd},
        {:packet, :line}
      ])
      
      {:ok, port}
    rescue
      error ->
        {:error, error}
    end
  end
  
  defp send_request(state, method, params) do
    # Increment message ID counter
    message_id = state.message_id_counter + 1
    
    # Create JSON-RPC request
    request = %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => message_id
    }
    
    # Encode and send
    case Jason.encode(request) do
      {:ok, json} ->
        Port.command(state.port, json <> "\n")
        
        # Wait for response (simplified - in real implementation would use async)
        receive do
          {:response, ^message_id, response} ->
            updated_state = %{state | message_id_counter: message_id}
            {:ok, response, updated_state}
        after
          5000 ->
            {:error, :timeout, state}
        end
        
      {:error, reason} ->
        {:error, {:json_encode_error, reason}, state}
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
  
  defp process_response(message, state) do
    case message do
      %{"id" => id, "result" => _result} ->
        # Send response back to waiting caller
        send(self(), {:response, id, message})
        
      %{"id" => id, "error" => error} ->
        # Send error back to waiting caller
        send(self(), {:response, id, {:error, error}})
        
      %{"method" => method, "params" => params} ->
        # Handle notification from server
        Logger.debug("Received notification from #{state.server_config.name}: #{method}")
        
        # Publish notification to VSM
        EventBus.publish(:external_mcp_notification, %{
          server_name: state.server_config.name,
          method: method,
          params: params,
          timestamp: DateTime.utc_now()
        })
        
      _ ->
        Logger.warning("Received unknown message format from #{state.server_config.name}: #{inspect(message)}")
    end
  end
  
  @doc """
  Creates a child spec for supervision.
  """
  def child_spec({server_config, opts}) do
    %{
      id: {__MODULE__, server_config.name},
      start: {__MODULE__, :start_link, [server_config, opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end