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
      
      # Prompt template manager
      {AutonomousOpponentV2Core.MCP.PromptManager, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Starts an MCP transport dynamically.
  """
  def start_transport(transport_type, opts \\ []) do
    transport_spec = {AutonomousOpponentV2Core.MCP.Transport, [transport_type, opts]}
    
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
end