defmodule AutonomousOpponentV2Core.MCP.Supervisor do
  @moduledoc """
  Supervisor for Model Context Protocol (MCP) infrastructure.
  
  Manages the MCP server and its transport mechanisms, providing
  a standardized interface for LLMs to connect to our VSM system.
  
  The MCP implementation exposes:
  - VSM subsystem data as Resources
  - System control functions as Tools  
  - Analysis workflows as Prompts
  - Real-time VSM events as Notifications
  """
  
  use Supervisor
  require Logger
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    Logger.info("Starting MCP Supervisor for VSM integration...")
    
    children = [
      # Core MCP server
      {AutonomousOpponentV2Core.MCP.Server, []},
      
      # Registry for MCP client connections
      {Registry, keys: :unique, name: AutonomousOpponentV2Core.MCP.ClientRegistry},
      
      # Dynamic supervisor for transport processes
      {DynamicSupervisor, name: AutonomousOpponentV2Core.MCP.TransportSupervisor, strategy: :one_for_one},
      
      # Resource manager for caching and updates
      {AutonomousOpponentV2Core.MCP.ResourceManager, []},
      
      # Tool executor for safe tool execution
      {AutonomousOpponentV2Core.MCP.ToolExecutor, []},
      
      # External MCP client management (optional - started when needed)
      %{
        id: :external_mcp_manager,
        start: {__MODULE__, :start_external_mcp_if_configured, []},
        restart: :transient
      }
      
      # TODO: Implement PromptManager for prompt templates
      # {AutonomousOpponentV2Core.MCP.PromptManager, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Starts an MCP transport dynamically.
  """
  def start_transport(transport_type, opts \\ []) do
    # Determine which transport module to use
    transport_module = case transport_type do
      :stdio -> AutonomousOpponentV2Core.MCP.Transport.Stdio
      :sse -> AutonomousOpponentV2Core.MCP.Transport.SSE
      :websocket -> AutonomousOpponentV2Core.MCP.Transport.WebSocket
      _ -> raise "Unknown transport type: #{transport_type}"
    end
    
    transport_spec = {transport_module, opts}
    
    DynamicSupervisor.start_child(
      AutonomousOpponentV2Core.MCP.TransportSupervisor, 
      transport_spec
    )
  end
  
  @doc """
  Gets status of all MCP components.
  """
  def get_status do
    %{
      server_running: GenServer.whereis(AutonomousOpponentV2Core.MCP.Server) != nil,
      active_transports: count_active_transports(),
      connected_clients: count_connected_clients(),
      resource_cache_size: get_resource_cache_size(),
      uptime: get_uptime()
    }
  end
  
  defp count_active_transports do
    DynamicSupervisor.count_children(AutonomousOpponentV2Core.MCP.TransportSupervisor).active
  end
  
  defp count_connected_clients do
    Registry.count(AutonomousOpponentV2Core.MCP.ClientRegistry)
  end
  
  defp get_resource_cache_size do
    case GenServer.call(AutonomousOpponentV2Core.MCP.ResourceManager, :cache_size, 1000) do
      {:ok, size} -> size
      _ -> 0
    end
  end
  
  defp get_uptime do
    case Process.info(self(), :dictionary) do
      {:dictionary, dict} ->
        case Keyword.get(dict, :start_time) do
          nil -> 0
          start_time -> System.system_time(:second) - start_time
        end
      _ -> 0
    end
  end
  
  @doc """
  Conditionally starts external MCP management if configuration is found.
  """
  def start_external_mcp_if_configured do
    # Check for MCP configuration file
    config_paths = [
      "/Users/speed/autonomous-opponent-phoenix/autonomous-opponent-proper/mcp.json",
      "./mcp.json",
      System.get_env("MCP_CONFIG_PATH")
    ]
    
    config_path = Enum.find(config_paths, fn path ->
      path && File.exists?(path)
    end)
    
    if config_path do
      Logger.info("External MCP configuration found at: #{config_path}")
      
      case AutonomousOpponentV2Core.MCP.ConfigManager.load_config(config_path) do
        {:ok, config} ->
          # Start the external MCP components
          children = [
            {AutonomousOpponentV2Core.MCP.ConfigManager, config},
            {AutonomousOpponentV2Core.MCP.ProcessManager, config}
          ]
          
          Logger.info("Starting external MCP management with #{map_size(config.servers)} servers")
          
          case Task.Supervisor.start_link(name: :external_mcp_supervisor) do
            {:ok, sup_pid} ->
              Enum.each(children, fn child_spec ->
                Task.Supervisor.start_child(:external_mcp_supervisor, fn ->
                  case child_spec do
                    {module, args} ->
                      {:ok, _pid} = module.start_link(args)
                      :timer.sleep(:infinity)  # Keep alive
                  end
                end)
              end)
              
              {:ok, sup_pid}
              
            error ->
              Logger.warning("Failed to start external MCP supervisor: #{inspect(error)}")
              error
          end
          
        {:error, reason} ->
          Logger.warning("Failed to load MCP configuration: #{inspect(reason)}")
          :ignore
      end
    else
      Logger.info("No external MCP configuration found - skipping external MCP management")
      :ignore
    end
  end
end