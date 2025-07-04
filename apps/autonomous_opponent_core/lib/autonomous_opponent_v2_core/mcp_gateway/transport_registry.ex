defmodule AutonomousOpponentV2Core.MCPGateway.TransportRegistry do
  @moduledoc """
  Registry for MCP Gateway transport handlers.
  
  Manages registration and lookup of transport implementations:
  - HTTP+SSE
  - WebSocket
  - Future transports (gRPC, etc.)
  
  ## Wisdom Preservation
  
  ### Why a Registry?
  Different clients need different transport mechanisms. Some prefer
  long-lived WebSocket connections, others need stateless HTTP+SSE.
  The registry allows dynamic transport selection without coupling.
  
  ### Design Pattern
  This implements the Strategy pattern - transports are interchangeable
  strategies for message delivery. The registry is the context that
  selects the appropriate strategy.
  """
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  
  # Transport types
  @type transport_type :: :http_sse | :websocket | :grpc
  @type transport_handler :: module()
  
  # Client API
  
  def start_link(opts) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Register a transport handler
  """
  def register(name \\ __MODULE__, transport_type, handler_module) do
    GenServer.call(name, {:register, transport_type, handler_module})
  end
  
  @doc """
  Get handler for a transport type
  """
  def get_handler(name \\ __MODULE__, transport_type) do
    GenServer.call(name, {:get_handler, transport_type})
  end
  
  @doc """
  List all registered transports
  """
  def list_transports(name \\ __MODULE__) do
    GenServer.call(name, :list_transports)
  end
  
  @doc """
  Get registry status
  """
  def status(name \\ __MODULE__) do
    GenServer.call(name, :status)
  end
  
  # Server implementation
  
  defstruct transports: %{}, stats: %{}
  
  @impl true
  def init(_opts) do
    # Register default transports
    state = %__MODULE__{
      transports: %{},
      stats: %{
        registrations: 0,
        lookups: 0,
        hits: 0,
        misses: 0
      }
    }
    
    # Publish initialization event
    EventBus.publish(:mcp_transport_registry_started, %{
      registry: __MODULE__
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register, transport_type, handler_module}, _from, state) do
    # Validate handler implements required callbacks
    if valid_handler?(handler_module) do
      new_transports = Map.put(state.transports, transport_type, handler_module)
      new_stats = Map.update(state.stats, :registrations, 1, &(&1 + 1))
      
      Logger.info("Registered #{transport_type} transport: #{handler_module}")
      
      EventBus.publish(:mcp_transport_registered, %{
        type: transport_type,
        handler: handler_module
      })
      
      {:reply, :ok, %{state | transports: new_transports, stats: new_stats}}
    else
      {:reply, {:error, :invalid_handler}, state}
    end
  end
  
  def handle_call({:get_handler, transport_type}, _from, state) do
    new_stats = Map.update(state.stats, :lookups, 1, &(&1 + 1))
    
    case Map.get(state.transports, transport_type) do
      nil ->
        new_stats = Map.update(new_stats, :misses, 1, &(&1 + 1))
        {:reply, {:error, :not_found}, %{state | stats: new_stats}}
        
      handler ->
        new_stats = Map.update(new_stats, :hits, 1, &(&1 + 1))
        {:reply, {:ok, handler}, %{state | stats: new_stats}}
    end
  end
  
  def handle_call(:list_transports, _from, state) do
    transports = Map.keys(state.transports)
    {:reply, transports, state}
  end
  
  def handle_call(:status, _from, state) do
    status = %{
      registered_transports: Map.keys(state.transports),
      stats: state.stats,
      hit_rate: calculate_hit_rate(state.stats)
    }
    {:reply, status, state}
  end
  
  # Private functions
  
  defp valid_handler?(module) do
    # Check if module exports required functions
    # In real implementation, would check for behaviour compliance
    Code.ensure_loaded?(module) and
      function_exported?(module, :connect, 2) and
      function_exported?(module, :send, 3) and
      function_exported?(module, :close, 1)
  end
  
  defp calculate_hit_rate(%{lookups: 0}), do: 0.0
  defp calculate_hit_rate(%{lookups: lookups, hits: hits}) do
    (hits / lookups) * 100
  end
end