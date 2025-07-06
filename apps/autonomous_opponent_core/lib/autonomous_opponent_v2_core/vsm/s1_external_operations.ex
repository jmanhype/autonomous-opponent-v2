defmodule AutonomousOpponentV2Core.VSM.S1ExternalOperations do
  @moduledoc """
  VSM S1 External Operations - Integrates external MCP servers into the cybernetic framework.
  
  This module implements variety absorption from external MCP servers, routing their
  capabilities through the VSM hierarchy according to cybernetic principles.
  
  ## Cybernetic Integration
  - S1: Absorbs variety from external servers (this module)
  - S2: Coordinates between different external capabilities
  - S3: Controls resource allocation and server health
  - S4: Aggregates intelligence from multiple sources
  - S5: Governs policy for server activation and deactivation
  
  ## Variety Processing
  External MCP servers provide environmental variety through:
  - Resources (files, databases, APIs)
  - Tools (actions, computations, transformations)
  - Notifications (real-time events, alerts)
  
  This variety is absorbed, filtered, and routed upward through the VSM hierarchy.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.{EventBus, MCP.ProcessManager}
  # Removed unused alias MCP.ConfigManager
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  alias AutonomousOpponentV2Core.Telemetry.SystemTelemetry
  # Removed unused alias S2Coordination
  
  defstruct [
    :config_manager,
    :process_manager,
    :active_capabilities,
    :variety_buffer,
    :absorption_rate,
    :coordination_channel
  ]
  
  @type capability :: %{
    server_name: String.t(),
    type: :resource | :tool | :notification,
    name: String.t(),
    description: String.t(),
    schema: map(),
    last_used: DateTime.t() | nil,
    usage_count: non_neg_integer(),
    effectiveness: float()
  }
  
  @type t :: %__MODULE__{
    config_manager: pid(),
    process_manager: pid(),
    active_capabilities: %{String.t() => [capability()]},
    variety_buffer: [map()],
    absorption_rate: float(),
    coordination_channel: pid()
  }
  
  # Configuration
  @max_variety_buffer 1000
  @absorption_rate_initial 0.5
  @capability_effectiveness_threshold 0.3
  
  # Public API
  
  @doc """
  Starts the S1 External Operations subsystem.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Absorbs external capabilities from a specific server.
  """
  def absorb_server_capabilities(server_name) do
    SystemTelemetry.measure([:vsm, :s1, :operation], %{operation: :absorb_capabilities}, fn ->
      GenServer.cast(__MODULE__, {:absorb_capabilities, server_name})
    end)
  end
  
  @doc """
  Executes an external capability.
  """
  def execute_capability(server_name, capability_name, params \\ %{}) do
    GenServer.call(__MODULE__, {:execute_capability, server_name, capability_name, params})
  end
  
  @doc """
  Gets current variety absorption status.
  """
  def get_absorption_status do
    GenServer.call(__MODULE__, :get_absorption_status)
  end
  
  @doc """
  Lists all available external capabilities.
  """
  def list_external_capabilities do
    GenServer.call(__MODULE__, :list_external_capabilities)
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(_opts) do
    Logger.info("Starting VSM S1 External Operations")
    
    # Get references to MCP managers
    config_manager = Process.whereis(MCP.ConfigManager)
    process_manager = Process.whereis(MCP.ProcessManager)
    
    # Start variety channel to S2
    {:ok, coordination_channel} = VarietyChannel.start_link(channel_type: :s1_to_s2)
    
    state = %__MODULE__{
      config_manager: config_manager,
      process_manager: process_manager,
      active_capabilities: %{},
      variety_buffer: [],
      absorption_rate: @absorption_rate_initial,
      coordination_channel: coordination_channel
    }
    
    # Subscribe to external MCP events
    EventBus.subscribe(:mcp_client_connected)
    EventBus.subscribe(:external_resource_data)
    EventBus.subscribe(:external_tool_result)
    EventBus.subscribe(:external_mcp_notification)
    
    # Publish S1 External started event
    EventBus.publish(:vsm_s1_external_started, %{
      absorption_rate: @absorption_rate_initial,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:absorb_capabilities, server_name}, state) do
    Logger.info("Absorbing capabilities from external server: #{server_name}")
    
    # Get server capabilities
    case get_server_capabilities(server_name, state) do
      {:ok, capabilities} ->
        # Process and categorize capabilities
        processed_capabilities = process_capabilities(server_name, capabilities)
        
        # Update state with new capabilities
        new_active_capabilities = Map.put(
          state.active_capabilities, 
          server_name, 
          processed_capabilities
        )
        
        new_state = %{state | active_capabilities: new_active_capabilities}
        
        # Send variety to S2 Coordination
        variety_packet = %{
          source: :s1_external,
          server_name: server_name,
          capabilities: processed_capabilities,
          variety_count: length(processed_capabilities),
          timestamp: DateTime.utc_now()
        }
        
        VarietyChannel.send_variety(state.coordination_channel, variety_packet)
        
        # Publish absorption event
        EventBus.publish(:variety_absorbed, %{
          source: :external_mcp,
          server_name: server_name,
          capability_count: length(processed_capabilities),
          absorption_rate: state.absorption_rate,
          timestamp: DateTime.utc_now()
        })
        
        {:noreply, new_state}
        
      {:error, reason} ->
        Logger.warning("Failed to absorb capabilities from #{server_name}: #{inspect(reason)}")
        
        # Send pain signal
        EventBus.publish(:algedonic_signal, %{
          type: :pain,
          severity: 0.5,
          valence: -0.5,
          reason: "Failed to absorb external capabilities: #{server_name}",
          source: :s1_external_operations,
          timestamp: DateTime.utc_now()
        })
        
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_call({:execute_capability, server_name, capability_name, params}, _from, state) do
    case find_capability(state, server_name, capability_name) do
      {:ok, capability} ->
        case execute_external_capability(capability, server_name, params) do
          {:ok, result} ->
            # Emit successful operation telemetry
            SystemTelemetry.emit(
              [:vsm, :s1, :operation, :stop],
              %{
                duration: 0,  # Would need start time for real duration
                output_variety: 1
              },
              %{operation: :execute_capability, server_name: server_name, capability: capability_name}
            )
            
            # Update capability usage statistics
            updated_state = update_capability_usage(state, server_name, capability_name, :success)
            
            # Buffer the result as variety
            variety_item = %{
              type: :execution_result,
              server_name: server_name,
              capability: capability_name,
              result: result,
              timestamp: DateTime.utc_now()
            }
            
            new_state = add_to_variety_buffer(updated_state, variety_item)
            
            {:reply, {:ok, result}, new_state}
            
          {:error, reason} ->
            # Emit failed operation telemetry
            SystemTelemetry.emit(
              [:vsm, :s1, :operation, :exception],
              %{duration: 0},
              %{operation: :execute_capability, error: reason, server_name: server_name, capability: capability_name}
            )
            
            # Update capability usage statistics
            updated_state = update_capability_usage(state, server_name, capability_name, :failure)
            
            {:reply, {:error, reason}, updated_state}
        end
        
      {:error, :not_found} ->
        {:reply, {:error, :capability_not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:get_absorption_status, _from, state) do
    status = %{
      active_servers: map_size(state.active_capabilities),
      total_capabilities: count_total_capabilities(state.active_capabilities),
      variety_buffer_size: length(state.variety_buffer),
      absorption_rate: state.absorption_rate,
      top_performers: get_top_performing_capabilities(state.active_capabilities)
    }
    
    {:reply, {:ok, status}, state}
  end
  
  @impl true
  def handle_call(:list_external_capabilities, _from, state) do
    all_capabilities = 
      state.active_capabilities
      |> Enum.flat_map(fn {server_name, capabilities} ->
        Enum.map(capabilities, fn cap ->
          Map.put(cap, :server_name, server_name)
        end)
      end)
      |> Enum.sort_by(& &1.effectiveness, :desc)
    
    {:reply, {:ok, all_capabilities}, state}
  end
  
  @impl true
  def handle_info({:event, :mcp_client_connected, data}, state) do
    server_name = data.server_name
    Logger.info("External MCP server connected: #{server_name}, initiating capability absorption")
    
    # Automatically absorb capabilities from newly connected servers
    GenServer.cast(self(), {:absorb_capabilities, server_name})
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :external_resource_data, data}, state) do
    # Process external resource data as variety
    variety_item = %{
      type: :resource_data,
      server_name: data.server_name,
      uri: data.uri,
      content: data.content,
      timestamp: data.timestamp
    }
    
    new_state = add_to_variety_buffer(state, variety_item)
    
    # Send variety to coordination channel
    VarietyChannel.send_variety(state.coordination_channel, variety_item)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :external_tool_result, data}, state) do
    # Process external tool results as variety
    variety_item = %{
      type: :tool_result,
      server_name: data.server_name,
      tool_name: data.tool_name,
      arguments: data.arguments,
      result: data.result,
      timestamp: data.timestamp
    }
    
    new_state = add_to_variety_buffer(state, variety_item)
    
    # Send variety to coordination channel
    VarietyChannel.send_variety(state.coordination_channel, variety_item)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :external_mcp_notification, data}, state) do
    # Process external notifications as variety
    variety_item = %{
      type: :notification,
      server_name: data.server_name,
      method: data.method,
      params: data.params,
      timestamp: data.timestamp
    }
    
    new_state = add_to_variety_buffer(state, variety_item)
    
    # Send variety to coordination channel
    VarietyChannel.send_variety(state.coordination_channel, variety_item)
    
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp get_server_capabilities(server_name, _state) do
    case ProcessManager.get_server_status(server_name) do
      {:ok, %{status: :healthy, pid: pid}} ->
        # Get capabilities from the MCP client
        with {:ok, tools} <- MCP.Client.list_tools(pid),
             {:ok, resources} <- MCP.Client.list_resources(pid) do
          
          # Remove unused capabilities assignment
          
          # Convert tools to capabilities
          tool_capabilities = Enum.map(tools || [], fn tool ->
            %{
              server_name: server_name,
              type: :tool,
              name: tool["name"],
              description: tool["description"] || "",
              schema: tool["inputSchema"] || %{},
              last_used: nil,
              usage_count: 0,
              effectiveness: 1.0  # Start with perfect effectiveness
            }
          end)
          
          # Convert resources to capabilities
          resource_capabilities = Enum.map(resources || [], fn resource ->
            %{
              server_name: server_name,
              type: :resource,
              name: resource["uri"],
              description: resource["description"] || "",
              schema: %{},
              last_used: nil,
              usage_count: 0,
              effectiveness: 1.0
            }
          end)
          
          all_capabilities = tool_capabilities ++ resource_capabilities
          {:ok, all_capabilities}
          
        else
          error -> 
            Logger.warning("Failed to get capabilities from #{server_name}: #{inspect(error)}")
            {:error, error}
        end
        
      {:ok, %{status: status}} ->
        {:error, {:server_not_healthy, status}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp process_capabilities(server_name, raw_capabilities) do
    Logger.debug("Processing #{length(raw_capabilities)} capabilities from #{server_name}")
    
    # Emit telemetry for capability processing
    SystemTelemetry.emit(
      [:vsm, :s1, :capabilities_processing],
      %{raw_count: length(raw_capabilities)},
      %{server_name: server_name}
    )
    
    processed = raw_capabilities
    |> Enum.map(fn capability ->
      # Apply cybernetic processing
      capability
      |> apply_variety_filter()
      |> calculate_initial_effectiveness()
      |> add_cybernetic_metadata(server_name)
    end)
    |> Enum.filter(& &1.effectiveness >= @capability_effectiveness_threshold)
    
    # Emit variety absorbed telemetry
    SystemTelemetry.emit(
      [:vsm, :s1, :variety_absorbed],
      %{
        input_variety: length(raw_capabilities),
        absorbed_variety: length(processed),
        efficiency: if(length(raw_capabilities) > 0, do: length(processed) / length(raw_capabilities), else: 0.0)
      },
      %{server_name: server_name}
    )
    
    processed
  end
  
  defp apply_variety_filter(capability) do
    # Filter based on variety absorption principles
    # For now, accept all capabilities
    capability
  end
  
  defp calculate_initial_effectiveness(capability) do
    # Calculate effectiveness based on capability characteristics
    base_effectiveness = case capability.type do
      :tool -> 0.8      # Tools are generally highly effective
      :resource -> 0.6  # Resources provide good variety
      :notification -> 0.4  # Notifications are useful but less direct
    end
    
    # Adjust based on description quality
    description_bonus = if String.length(capability.description) > 10, do: 0.1, else: 0.0
    
    # Adjust based on schema complexity (for tools)
    schema_bonus = if map_size(capability.schema) > 0, do: 0.1, else: 0.0
    
    final_effectiveness = min(1.0, base_effectiveness + description_bonus + schema_bonus)
    
    %{capability | effectiveness: final_effectiveness}
  end
  
  defp add_cybernetic_metadata(capability, server_name) do
    capability
    |> Map.put(:absorption_time, DateTime.utc_now())
    |> Map.put(:variety_source, server_name)
    |> Map.put(:cybernetic_weight, capability.effectiveness)
  end
  
  defp find_capability(state, server_name, capability_name) do
    case Map.get(state.active_capabilities, server_name) do
      nil -> {:error, :not_found}
      capabilities ->
        case Enum.find(capabilities, &(&1.name == capability_name)) do
          nil -> {:error, :not_found}
          capability -> {:ok, capability}
        end
    end
  end
  
  defp execute_external_capability(capability, server_name, params) do
    # Start telemetry span
    start_metadata = SystemTelemetry.start_span(
      [:vsm, :s1, :operation],
      %{
        operation: :execute_external_capability,
        input_variety: 1,
        capability_type: capability.type
      }
    )
    
    case ProcessManager.get_server_status(server_name) do
      {:ok, %{status: :healthy, pid: pid}} ->
        case capability.type do
          :tool ->
            MCP.Client.call_tool(pid, capability.name, params)
            
          :resource ->
            MCP.Client.read_resource(pid, capability.name)
            
          :notification ->
            # Notifications can't be executed directly
            {:error, :notification_not_executable}
        end
        
      {:ok, %{status: status}} ->
        {:error, {:server_not_healthy, status}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp update_capability_usage(state, server_name, capability_name, result) do
    case Map.get(state.active_capabilities, server_name) do
      nil -> state
      capabilities ->
        updated_capabilities = Enum.map(capabilities, fn cap ->
          if cap.name == capability_name do
            new_usage_count = cap.usage_count + 1
            new_effectiveness = calculate_new_effectiveness(cap.effectiveness, result, new_usage_count)
            
            %{cap | 
              usage_count: new_usage_count,
              last_used: DateTime.utc_now(),
              effectiveness: new_effectiveness
            }
          else
            cap
          end
        end)
        
        new_active_capabilities = Map.put(state.active_capabilities, server_name, updated_capabilities)
        %{state | active_capabilities: new_active_capabilities}
    end
  end
  
  defp calculate_new_effectiveness(current_effectiveness, :success, usage_count) do
    # Increase effectiveness on success, but with diminishing returns
    improvement = 0.1 / (1 + usage_count * 0.1)
    min(1.0, current_effectiveness + improvement)
  end
  
  defp calculate_new_effectiveness(current_effectiveness, :failure, usage_count) do
    # Decrease effectiveness on failure
    degradation = 0.05 * (1 + usage_count * 0.05)
    max(0.0, current_effectiveness - degradation)
  end
  
  defp add_to_variety_buffer(state, variety_item) do
    new_buffer = [variety_item | state.variety_buffer]
    
    # Trim buffer if it exceeds maximum size
    trimmed_buffer = if length(new_buffer) > @max_variety_buffer do
      # Emit buffer overflow telemetry
      SystemTelemetry.emit(
        [:vsm, :s1, :variety_buffer_overflow],
        %{buffer_size: length(new_buffer), max_size: @max_variety_buffer},
        %{items_dropped: length(new_buffer) - @max_variety_buffer}
      )
      Enum.take(new_buffer, @max_variety_buffer)
    else
      new_buffer
    end
    
    %{state | variety_buffer: trimmed_buffer}
  end
  
  defp count_total_capabilities(active_capabilities) do
    active_capabilities
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end
  
  defp get_top_performing_capabilities(active_capabilities) do
    active_capabilities
    |> Enum.flat_map(fn {server_name, capabilities} ->
      Enum.map(capabilities, fn cap ->
        Map.put(cap, :server_name, server_name)
      end)
    end)
    |> Enum.sort_by(& &1.effectiveness, :desc)
    |> Enum.take(10)
  end
end