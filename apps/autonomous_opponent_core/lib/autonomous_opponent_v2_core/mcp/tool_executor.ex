defmodule AutonomousOpponentV2Core.MCP.ToolExecutor do
  @moduledoc """
  Safe execution environment for MCP Tools.
  
  Provides sandboxed execution of tools with:
  - Input validation and sanitization
  - Execution timeouts
  - Resource limits
  - Audit logging
  - Error recovery
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  
  defstruct [
    :execution_stats,
    :running_tools,
    :tool_registry
  ]
  
  @execution_timeout 30_000  # 30 seconds
  @max_concurrent_tools 10
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Executes a tool with the given arguments.
  """
  def execute_tool(tool_name, arguments) do
    GenServer.call(__MODULE__, {:execute_tool, tool_name, arguments}, @execution_timeout + 5000)
  end
  
  @doc """
  Gets execution statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Lists currently running tools.
  """
  def get_running_tools do
    GenServer.call(__MODULE__, :get_running_tools)
  end
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      execution_stats: %{
        total_executions: 0,
        successful_executions: 0,
        failed_executions: 0,
        average_execution_time: 0
      },
      running_tools: %{},
      tool_registry: register_tools()
    }
    
    Logger.info("MCP ToolExecutor started")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:execute_tool, tool_name, arguments}, from, state) do
    if map_size(state.running_tools) >= @max_concurrent_tools do
      {:reply, {:error, "Too many concurrent tool executions"}, state}
    else
      # Start tool execution in a separate process
      task = Task.async(fn ->
        execute_tool_safely(tool_name, arguments)
      end)
      
      # Track the running tool
      execution_id = make_ref()
      execution_info = %{
        tool_name: tool_name,
        task: task,
        client: from,
        start_time: System.monotonic_time(:millisecond),
        arguments: arguments
      }
      
      new_running_tools = Map.put(state.running_tools, execution_id, execution_info)
      
      # Set timeout for the execution
      Process.send_after(self(), {:tool_timeout, execution_id}, @execution_timeout)
      
      {:noreply, %{state | running_tools: new_running_tools}}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.execution_stats, state}
  end
  
  @impl true
  def handle_call(:get_running_tools, _from, state) do
    running = state.running_tools
    |> Enum.map(fn {id, info} ->
      %{
        id: id,
        tool_name: info.tool_name,
        start_time: info.start_time,
        duration: System.monotonic_time(:millisecond) - info.start_time
      }
    end)
    
    {:reply, running, state}
  end
  
  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Tool execution completed
    case find_execution_by_task_ref(ref, state) do
      {execution_id, execution_info} ->
        # Send result to client
        GenServer.reply(execution_info.client, result)
        
        # Update stats
        execution_time = System.monotonic_time(:millisecond) - execution_info.start_time
        state = update_execution_stats(state, result, execution_time)
        
        # Remove from running tools
        new_running_tools = Map.delete(state.running_tools, execution_id)
        
        # Log execution
        log_tool_execution(execution_info.tool_name, execution_info.arguments, result, execution_time)
        
        {:noreply, %{state | running_tools: new_running_tools}}
        
      nil ->
        # Unknown task reference
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Tool execution process died
    case find_execution_by_task_ref(ref, state) do
      {execution_id, execution_info} ->
        error_result = {:error, "Tool execution failed: #{inspect(reason)}"}
        GenServer.reply(execution_info.client, error_result)
        
        execution_time = System.monotonic_time(:millisecond) - execution_info.start_time
        state = update_execution_stats(state, error_result, execution_time)
        
        new_running_tools = Map.delete(state.running_tools, execution_id)
        
        Logger.error("Tool execution crashed: #{execution_info.tool_name}, reason: #{inspect(reason)}")
        
        {:noreply, %{state | running_tools: new_running_tools}}
        
      nil ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:tool_timeout, execution_id}, state) do
    case Map.get(state.running_tools, execution_id) do
      nil ->
        # Tool already completed
        {:noreply, state}
        
      execution_info ->
        # Kill the task and reply with timeout error
        Task.shutdown(execution_info.task, :brutal_kill)
        
        error_result = {:error, "Tool execution timeout"}
        GenServer.reply(execution_info.client, error_result)
        
        execution_time = System.monotonic_time(:millisecond) - execution_info.start_time
        state = update_execution_stats(state, error_result, execution_time)
        
        new_running_tools = Map.delete(state.running_tools, execution_id)
        
        Logger.warning("Tool execution timeout: #{execution_info.tool_name}")
        
        {:noreply, %{state | running_tools: new_running_tools}}
    end
  end
  
  # Private Functions
  
  defp register_tools do
    %{
      "trigger_algedonic" => %{
        executor: &execute_trigger_algedonic/1,
        validation: &validate_trigger_algedonic/1,
        description: "Trigger algedonic signal in VSM"
      },
      "query_subsystem" => %{
        executor: &execute_query_subsystem/1,
        validation: &validate_query_subsystem/1,
        description: "Query VSM subsystem"
      },
      "publish_event" => %{
        executor: &execute_publish_event/1,
        validation: &validate_publish_event/1,
        description: "Publish event to EventBus"
      },
      "get_consciousness_state" => %{
        executor: &execute_get_consciousness_state/1,
        validation: &validate_get_consciousness_state/1,
        description: "Get current consciousness state"
      }
    }
  end
  
  defp execute_tool_safely(tool_name, arguments) do
    case Map.get(register_tools(), tool_name) do
      nil ->
        {:error, "Tool not found: #{tool_name}"}
        
      tool_def ->
        case tool_def.validation.(arguments) do
          :ok ->
            try do
              tool_def.executor.(arguments)
            rescue
              e ->
                Logger.error("Tool execution error: #{inspect(e)}")
                {:error, "Tool execution failed: #{Exception.message(e)}"}
            catch
              :exit, reason ->
                Logger.error("Tool execution exit: #{inspect(reason)}")
                {:error, "Tool execution exited: #{inspect(reason)}"}
            end
            
          {:error, reason} ->
            {:error, "Invalid arguments: #{reason}"}
        end
    end
  end
  
  # Tool Validators
  
  defp validate_trigger_algedonic(%{"type" => type, "severity" => severity, "reason" => reason}) 
    when type in ["pain", "pleasure"] and is_number(severity) and severity >= 0 and severity <= 1 
    and is_binary(reason) do
    :ok
  end
  defp validate_trigger_algedonic(_), do: {:error, "Invalid trigger_algedonic arguments"}
  
  defp validate_query_subsystem(%{"subsystem" => subsystem, "query" => query}) 
    when subsystem in ["s1", "s2", "s3", "s4", "s5"] and is_binary(query) do
    :ok
  end
  defp validate_query_subsystem(_), do: {:error, "Invalid query_subsystem arguments"}
  
  defp validate_publish_event(%{"event_name" => event_name, "data" => data}) 
    when is_binary(event_name) and is_map(data) do
    :ok
  end
  defp validate_publish_event(_), do: {:error, "Invalid publish_event arguments"}
  
  defp validate_get_consciousness_state(_), do: :ok
  
  # Tool Executors
  
  defp execute_trigger_algedonic(%{"type" => type, "severity" => severity, "reason" => reason}) do
    valence = if type == "pain", do: -severity, else: severity
    
    EventBus.publish(:algedonic_signal, %{
      type: String.to_atom(type),
      severity: severity,
      valence: valence,
      reason: reason,
      source: :mcp_tool,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, %{
      content: [%{
        type: "text",
        text: "Algedonic signal triggered: #{type} with severity #{severity}"
      }]
    }}
  end
  
  defp execute_query_subsystem(%{"subsystem" => subsystem, "query" => query}) do
    result = case EventBus.call(:"vsm_#{subsystem}", :handle_query, [query], 5000) do
      {:ok, response} -> response
      {:error, :timeout} -> "Subsystem timeout"
      _ -> "Subsystem not responding"
    end
    
    {:ok, %{
      content: [%{
        type: "text",
        text: "#{String.upcase(subsystem)} Response: #{inspect(result)}"
      }]
    }}
  end
  
  defp execute_publish_event(%{"event_name" => event_name, "data" => data}) do
    # Sanitize event name (only allow alphanumeric and underscore)
    sanitized_name = Regex.replace(~r/[^a-zA-Z0-9_]/, event_name, "_")
    
    EventBus.publish(String.to_atom("mcp_" <> sanitized_name), data)
    
    {:ok, %{
      content: [%{
        type: "text",
        text: "Event 'mcp_#{sanitized_name}' published to EventBus"
      }]
    }}
  end
  
  defp execute_get_consciousness_state(_args) do
    state = case EventBus.call(:consciousness, :get_state, 5000) do
      {:ok, state} -> state
      _ -> %{state: "unknown", timestamp: DateTime.utc_now()}
    end
    
    {:ok, %{
      content: [%{
        type: "text",
        text: "Consciousness State: #{Jason.encode!(state, pretty: true)}"
      }]
    }}
  end
  
  defp find_execution_by_task_ref(ref, state) do
    Enum.find_value(state.running_tools, fn {id, info} ->
      if info.task.ref == ref do
        {id, info}
      end
    end)
  end
  
  defp update_execution_stats(state, result, execution_time) do
    stats = state.execution_stats
    
    total = stats.total_executions + 1
    successful = if match?({:ok, _}, result), do: stats.successful_executions + 1, else: stats.successful_executions
    failed = if match?({:error, _}, result), do: stats.failed_executions + 1, else: stats.failed_executions
    
    # Calculate new average execution time
    current_avg = stats.average_execution_time
    new_avg = (current_avg * (total - 1) + execution_time) / total
    
    new_stats = %{
      total_executions: total,
      successful_executions: successful,
      failed_executions: failed,
      average_execution_time: round(new_avg)
    }
    
    %{state | execution_stats: new_stats}
  end
  
  defp log_tool_execution(tool_name, arguments, result, execution_time) do
    success = match?({:ok, _}, result)
    
    EventBus.publish(:mcp_tool_execution, %{
      tool_name: tool_name,
      arguments: arguments,
      success: success,
      execution_time: execution_time,
      timestamp: DateTime.utc_now()
    })
    
    level = if success, do: :info, else: :warning
    Logger.log(level, "MCP tool executed: #{tool_name} (#{execution_time}ms) - #{if success, do: "SUCCESS", else: "FAILED"}")
  end
end