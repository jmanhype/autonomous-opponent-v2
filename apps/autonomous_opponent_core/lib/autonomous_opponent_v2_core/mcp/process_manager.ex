defmodule AutonomousOpponentV2Core.MCP.ProcessManager do
  @moduledoc """
  MCP Process Manager for managing the lifecycle of external MCP servers.
  
  This module handles:
  - Starting and stopping external MCP server processes
  - Health monitoring and automatic recovery
  - Resource management and cleanup
  - Integration with VSM cybernetic control loops
  
  ## VSM Integration
  - S1 Operations: Manages individual server processes
  - S2 Coordination: Coordinates between multiple servers
  - S3 Control: Monitors and controls server health
  - Algedonic: Generates pain/pleasure signals based on server performance
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.{EventBus, MCP.Client, MCP.ConfigManager}
  
  defstruct [
    :config,
    :active_clients,
    :health_monitors,
    :restart_counts,
    :last_health_check,
    :supervisor_pid
  ]
  
  @type client_info :: %{
    pid: pid(),
    server_name: String.t(),
    start_time: DateTime.t(),
    last_health_check: DateTime.t() | nil,
    status: :healthy | :unhealthy | :starting | :stopping,
    restart_count: non_neg_integer()
  }
  
  @type t :: %__MODULE__{
    config: ConfigManager.t(),
    active_clients: %{String.t() => client_info()},
    health_monitors: %{String.t() => pid()},
    restart_counts: %{String.t() => non_neg_integer()},
    last_health_check: DateTime.t() | nil,
    supervisor_pid: pid() | nil
  }
  
  # Configuration
  @health_check_interval 30_000  # 30 seconds
  @max_restart_count 3
  
  # Public API
  
  @doc """
  Starts the MCP Process Manager.
  """
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, [name: __MODULE__] ++ opts)
  end
  
  @doc """
  Starts external MCP servers based on configuration.
  """
  def start_servers(server_names \\ :all) do
    GenServer.call(__MODULE__, {:start_servers, server_names})
  end
  
  @doc """
  Stops specific external MCP servers.
  """
  def stop_servers(server_names) do
    GenServer.call(__MODULE__, {:stop_servers, server_names})
  end
  
  @doc """
  Stops all external MCP servers.
  """
  def stop_all_servers do
    GenServer.call(__MODULE__, :stop_all_servers)
  end
  
  @doc """
  Gets the status of all managed servers.
  """
  def get_server_status do
    GenServer.call(__MODULE__, :get_server_status)
  end
  
  @doc """
  Gets the status of a specific server.
  """
  def get_server_status(server_name) do
    GenServer.call(__MODULE__, {:get_server_status, server_name})
  end
  
  @doc """
  Restarts a specific server.
  """
  def restart_server(server_name) do
    GenServer.call(__MODULE__, {:restart_server, server_name})
  end
  
  @doc """
  Reloads configuration and applies changes.
  """
  def reload_config do
    GenServer.call(__MODULE__, :reload_config)
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(config) do
    Logger.info("Starting MCP Process Manager with #{map_size(config.servers)} configured servers")
    
    # Start DynamicSupervisor for MCP clients
    {:ok, supervisor_pid} = DynamicSupervisor.start_link(strategy: :one_for_one)
    
    state = %__MODULE__{
      config: config,
      active_clients: %{},
      health_monitors: %{},
      restart_counts: %{},
      supervisor_pid: supervisor_pid
    }
    
    # Subscribe to MCP client events
    EventBus.subscribe(:mcp_client_connected)
    EventBus.subscribe(:mcp_client_disconnected)
    
    # Start health check timer
    schedule_health_check()
    
    # Publish manager started event
    EventBus.publish(:mcp_process_manager_started, %{
      configured_servers: Map.keys(config.servers),
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_servers, :all}, _from, state) do
    server_names = Map.keys(state.config.servers)
    start_servers_internal(server_names, state)
  end
  
  @impl true
  def handle_call({:start_servers, server_names}, _from, state) when is_list(server_names) do
    start_servers_internal(server_names, state)
  end
  
  @impl true
  def handle_call({:start_servers, server_name}, _from, state) when is_binary(server_name) do
    start_servers_internal([server_name], state)
  end
  
  @impl true
  def handle_call({:stop_servers, server_names}, _from, state) when is_list(server_names) do
    stop_servers_internal(server_names, state)
  end
  
  @impl true
  def handle_call({:stop_servers, server_name}, _from, state) when is_binary(server_name) do
    stop_servers_internal([server_name], state)
  end
  
  @impl true
  def handle_call(:stop_all_servers, _from, state) do
    server_names = Map.keys(state.active_clients)
    stop_servers_internal(server_names, state)
  end
  
  @impl true
  def handle_call(:get_server_status, _from, state) do
    status = build_status_report(state)
    {:reply, {:ok, status}, state}
  end
  
  @impl true
  def handle_call({:get_server_status, server_name}, _from, state) do
    case Map.get(state.active_clients, server_name) do
      nil -> {:reply, {:error, :not_found}, state}
      client_info -> {:reply, {:ok, client_info}, state}
    end
  end
  
  @impl true
  def handle_call({:restart_server, server_name}, _from, state) do
    case restart_server_internal(server_name, state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:reload_config, _from, state) do
    case ConfigManager.reload_config(state.config) do
      {:ok, new_config} ->
        # Apply configuration changes
        new_state = apply_config_changes(state, new_config)
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        Logger.error("Failed to reload MCP configuration: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)
    schedule_health_check()
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :mcp_client_connected, data}, state) do
    server_name = data.server_name
    
    case Map.get(state.active_clients, server_name) do
      nil ->
        Logger.warning("Received connection event for unknown server: #{server_name}")
        {:noreply, state}
        
      client_info ->
        updated_client_info = %{client_info | 
          status: :healthy,
          last_health_check: DateTime.utc_now()
        }
        
        new_state = %{state | 
          active_clients: Map.put(state.active_clients, server_name, updated_client_info)
        }
        
        # Publish pleasure signal for successful connection
        EventBus.publish(:algedonic_signal, %{
          type: :pleasure,
          severity: 0.6,
          valence: 0.6,
          reason: "External MCP server connected successfully: #{server_name}",
          source: :mcp_process_manager,
          server_name: server_name,
          timestamp: DateTime.utc_now()
        })
        
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info({:event, :mcp_client_disconnected, data}, state) do
    server_name = data.server_name
    exit_status = data.exit_status
    
    Logger.warning("MCP client disconnected: #{server_name} (exit: #{exit_status})")
    
    case Map.get(state.active_clients, server_name) do
      nil ->
        {:noreply, state}
        
      client_info ->
        # Check if we should restart the server
        restart_count = Map.get(state.restart_counts, server_name, 0)
        
        if restart_count < @max_restart_count and should_restart?(exit_status) do
          Logger.info("Restarting MCP server #{server_name} (attempt #{restart_count + 1})")
          
          # Schedule restart after a delay
          Process.send_after(self(), {:restart_server, server_name}, 5000)
          
          updated_client_info = %{client_info | status: :unhealthy}
          new_restart_counts = Map.put(state.restart_counts, server_name, restart_count + 1)
          
          new_state = %{state |
            active_clients: Map.put(state.active_clients, server_name, updated_client_info),
            restart_counts: new_restart_counts
          }
          
          {:noreply, new_state}
        else
          Logger.error("MCP server #{server_name} failed permanently after #{restart_count} restarts")
          
          # Remove from active clients
          new_state = %{state |
            active_clients: Map.delete(state.active_clients, server_name)
          }
          
          # Publish pain signal for permanent failure
          EventBus.publish(:algedonic_signal, %{
            type: :pain,
            severity: 0.8,
            valence: -0.8,
            reason: "External MCP server failed permanently: #{server_name}",
            source: :mcp_process_manager,
            server_name: server_name,
            timestamp: DateTime.utc_now()
          })
          
          {:noreply, new_state}
        end
    end
  end
  
  @impl true
  def handle_info({:restart_server, server_name}, state) do
    case restart_server_internal(server_name, state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find which server this pid belongs to
    case find_server_by_pid(state, pid) do
      {:ok, server_name} ->
        Logger.warning("MCP client process #{inspect(pid)} for #{server_name} died: #{inspect(reason)}")
        
        # This will be handled by the mcp_client_disconnected event
        {:noreply, state}
        
      :not_found ->
        Logger.debug("Unknown process #{inspect(pid)} died: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  # Private Functions
  
  defp start_servers_internal(server_names, state) do
    Logger.info("Starting MCP servers: #{inspect(server_names)}")
    
    results = 
      server_names
      |> Enum.map(fn server_name ->
        case start_server_internal(server_name, state) do
          {:ok, client_info} -> {server_name, {:ok, client_info}}
          {:error, reason} -> {server_name, {:error, reason}}
        end
      end)
      |> Enum.into(%{})
    
    # Update state with successful starts
    successful_starts = 
      results
      |> Enum.filter(fn {_name, result} -> match?({:ok, _}, result) end)
      |> Enum.map(fn {name, {:ok, client_info}} -> {name, client_info} end)
      |> Enum.into(%{})
    
    new_state = %{state |
      active_clients: Map.merge(state.active_clients, successful_starts)
    }
    
    {:reply, {:ok, results}, new_state}
  end
  
  defp start_server_internal(server_name, state) do
    case ConfigManager.get_server_config(state.config, server_name) do
      {:ok, server_config} ->
        case DynamicSupervisor.start_child(
          state.supervisor_pid, 
          {Client, server_config, []}
        ) do
          {:ok, pid} ->
            Process.monitor(pid)
            
            client_info = %{
              pid: pid,
              server_name: server_name,
              start_time: DateTime.utc_now(),
              last_health_check: nil,
              status: :starting,
              restart_count: Map.get(state.restart_counts, server_name, 0)
            }
            
            Logger.info("Started MCP client for #{server_name} (PID: #{inspect(pid)})")
            {:ok, client_info}
            
          {:error, reason} ->
            Logger.error("Failed to start MCP client for #{server_name}: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, :not_found} ->
        Logger.error("Server configuration not found: #{server_name}")
        {:error, :server_not_configured}
    end
  end
  
  defp stop_servers_internal(server_names, state) do
    Logger.info("Stopping MCP servers: #{inspect(server_names)}")
    
    results = 
      server_names
      |> Enum.map(fn server_name ->
        case stop_server_internal(server_name, state) do
          :ok -> {server_name, :ok}
          {:error, reason} -> {server_name, {:error, reason}}
        end
      end)
      |> Enum.into(%{})
    
    # Remove stopped servers from active clients
    new_active_clients = 
      server_names
      |> Enum.reduce(state.active_clients, fn name, acc ->
        Map.delete(acc, name)
      end)
    
    new_state = %{state | active_clients: new_active_clients}
    
    {:reply, {:ok, results}, new_state}
  end
  
  defp stop_server_internal(server_name, state) do
    case Map.get(state.active_clients, server_name) do
      nil ->
        {:error, :not_running}
        
      %{pid: pid} ->
        DynamicSupervisor.terminate_child(state.supervisor_pid, pid)
        Logger.info("Stopped MCP client for #{server_name}")
        :ok
    end
  end
  
  defp restart_server_internal(server_name, state) do
    Logger.info("Restarting MCP server: #{server_name}")
    
    # Stop if running
    case Map.get(state.active_clients, server_name) do
      nil -> :ok
      _client_info -> stop_server_internal(server_name, state)
    end
    
    # Start again
    case start_server_internal(server_name, state) do
      {:ok, client_info} ->
        new_state = %{state |
          active_clients: Map.put(state.active_clients, server_name, client_info)
        }
        {:ok, new_state}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp perform_health_check(state) do
    Logger.debug("Performing health check on #{map_size(state.active_clients)} MCP clients")
    
    updated_clients = 
      state.active_clients
      |> Enum.map(fn {server_name, client_info} ->
        health_status = check_client_health(client_info)
        updated_info = %{client_info | 
          last_health_check: DateTime.utc_now(),
          status: health_status
        }
        {server_name, updated_info}
      end)
      |> Enum.into(%{})
    
    %{state | 
      active_clients: updated_clients,
      last_health_check: DateTime.utc_now()
    }
  end
  
  defp check_client_health(%{pid: pid}) do
    if Process.alive?(pid) do
      :healthy
    else
      :unhealthy
    end
  end
  
  defp should_restart?(exit_status) do
    # Restart on abnormal exits, but not on normal shutdown
    exit_status != 0
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
  
  defp find_server_by_pid(state, pid) do
    case Enum.find(state.active_clients, fn {_name, %{pid: client_pid}} -> 
      client_pid == pid 
    end) do
      {server_name, _client_info} -> {:ok, server_name}
      nil -> :not_found
    end
  end
  
  defp build_status_report(state) do
    %{
      total_servers: map_size(state.config.servers),
      active_servers: map_size(state.active_clients),
      last_health_check: state.last_health_check,
      servers: 
        state.active_clients
        |> Enum.map(fn {name, info} ->
          %{
            name: name,
            status: info.status,
            start_time: info.start_time,
            last_health_check: info.last_health_check,
            restart_count: info.restart_count,
            uptime: calculate_uptime(info.start_time)
          }
        end)
    }
  end
  
  defp calculate_uptime(start_time) do
    DateTime.diff(DateTime.utc_now(), start_time, :second)
  end
  
  defp apply_config_changes(state, new_config) do
    # For now, just update the config
    # In a full implementation, we'd detect and apply changes
    %{state | config: new_config}
  end
end