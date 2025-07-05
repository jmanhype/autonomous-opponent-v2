defmodule AutonomousOpponentV2Core.MCP.ConfigManager do
  @moduledoc """
  MCP Configuration Manager for parsing and managing external MCP server configurations.
  
  Handles JSON configuration files (like Claude Desktop's mcp.json) and converts them
  into server specifications that can be managed by our VSM cybernetic framework.
  
  ## Configuration Format
  Supports the standard MCP configuration format:
  ```json
  {
    "mcpServers": {
      "server-name": {
        "command": "command-to-run",
        "args": ["arg1", "arg2"],
        "env": {
          "ENV_VAR": "value"
        },
        "cwd": "/path/to/directory"
      }
    }
  }
  ```
  
  ## VSM Integration
  Server configurations are processed through S5 Policy to determine
  which servers should be activated based on cybernetic viability.
  """
  
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  
  defstruct [
    :config_path,
    :servers,
    :active_servers,
    :metadata
  ]
  
  @type server_config :: %{
    name: String.t(),
    command: String.t(),
    args: [String.t()],
    env: %{String.t() => String.t()},
    cwd: String.t() | nil
  }
  
  @type t :: %__MODULE__{
    config_path: String.t(),
    servers: %{String.t() => server_config()},
    active_servers: [String.t()],
    metadata: %{String.t() => any()}
  }
  
  @doc """
  Loads an MCP configuration from a JSON file.
  
  ## Examples
      iex> ConfigManager.load_config("/path/to/mcp.json")
      {:ok, %ConfigManager{servers: %{"filesystem" => %{...}}}}
  """
  @spec load_config(String.t()) :: {:ok, t()} | {:error, term()}
  def load_config(config_path) do
    Logger.info("Loading MCP configuration from: #{config_path}")
    
    with {:ok, content} <- File.read(config_path),
         {:ok, json} <- Jason.decode(content),
         {:ok, servers} <- parse_servers(json) do
      
      config = %__MODULE__{
        config_path: config_path,
        servers: servers,
        active_servers: [],
        metadata: %{
          loaded_at: DateTime.utc_now(),
          server_count: map_size(servers),
          config_hash: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        }
      }
      
      # Publish configuration loaded event to VSM
      EventBus.publish(:mcp_config_loaded, %{
        config_path: config_path,
        server_count: map_size(servers),
        servers: Map.keys(servers),
        timestamp: DateTime.utc_now()
      })
      
      {:ok, config}
    else
      {:error, :enoent} ->
        Logger.error("MCP configuration file not found: #{config_path}")
        {:error, :config_file_not_found}
        
      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("Invalid JSON in MCP configuration: #{Exception.message(error)}")
        {:error, :invalid_json}
        
      {:error, reason} ->
        Logger.error("Failed to load MCP configuration: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Validates a server configuration for cybernetic viability.
  
  Checks if the server configuration meets VSM requirements
  and can be safely integrated into the autonomous system.
  """
  @spec validate_server(server_config()) :: {:ok, server_config()} | {:error, term()}
  def validate_server(server_config) do
    with :ok <- validate_command(server_config.command),
         :ok <- validate_args(server_config.args),
         :ok <- validate_env(server_config.env) do
      {:ok, server_config}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Selects servers for activation based on VSM policy criteria.
  
  Uses S5 Policy governance to determine which external servers
  should be activated based on:
  - Resource availability
  - Security constraints  
  - Variety absorption capacity
  - Cybernetic viability
  """
  @spec select_servers_for_activation(t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def select_servers_for_activation(config, opts \\ []) do
    max_servers = Keyword.get(opts, :max_servers, 10)
    priority_servers = Keyword.get(opts, :priority_servers, [])
    exclude_servers = Keyword.get(opts, :exclude_servers, [])
    
    Logger.info("Selecting servers for activation (max: #{max_servers})")
    
    # Apply S5 Policy selection criteria
    candidates = config.servers
    |> Map.keys()
    |> Enum.reject(&(&1 in exclude_servers))
    |> prioritize_servers(priority_servers)
    |> filter_by_viability(config.servers)
    |> Enum.take(max_servers)
    
    # Publish server selection event
    EventBus.publish(:mcp_servers_selected, %{
      selected_servers: candidates,
      total_available: map_size(config.servers),
      selection_criteria: %{
        max_servers: max_servers,
        priority_servers: priority_servers,
        exclude_servers: exclude_servers
      },
      timestamp: DateTime.utc_now()
    })
    
    {:ok, candidates}
  end
  
  @doc """
  Gets a specific server configuration by name.
  """
  @spec get_server_config(t(), String.t()) :: {:ok, server_config()} | {:error, :not_found}
  def get_server_config(config, server_name) do
    case Map.get(config.servers, server_name) do
      nil -> {:error, :not_found}
      server_config -> {:ok, server_config}
    end
  end
  
  @doc """
  Lists all available server names.
  """
  @spec list_servers(t()) :: [String.t()]
  def list_servers(config) do
    Map.keys(config.servers)
  end
  
  @doc """
  Gets servers by category (based on naming patterns).
  
  ## Examples
      iex> get_servers_by_category(config, :database)
      ["postgres", "sqlite", "mysql"]
      
      iex> get_servers_by_category(config, :search)
      ["exa", "brave-search", "google"]
  """
  @spec get_servers_by_category(t(), atom()) :: [String.t()]
  def get_servers_by_category(config, category) do
    patterns = category_patterns(category)
    
    config.servers
    |> Map.keys()
    |> Enum.filter(fn name ->
      Enum.any?(patterns, &String.contains?(name, &1))
    end)
  end
  
  @doc """
  Reloads configuration from file and detects changes.
  """
  @spec reload_config(t()) :: {:ok, t()} | {:error, term()}
  def reload_config(config) do
    case load_config(config.config_path) do
      {:ok, new_config} ->
        changes = detect_changes(config, new_config)
        
        if length(changes) > 0 do
          Logger.info("MCP configuration changes detected: #{inspect(changes)}")
          
          EventBus.publish(:mcp_config_changed, %{
            config_path: config.config_path,
            changes: changes,
            timestamp: DateTime.utc_now()
          })
        end
        
        {:ok, new_config}
        
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Private Functions
  
  defp parse_servers(%{"mcpServers" => servers}) when is_map(servers) do
    parsed_servers = 
      servers
      |> Enum.map(fn {name, config} ->
        {name, parse_server_config(name, config)}
      end)
      |> Enum.into(%{})
    
    {:ok, parsed_servers}
  end
  
  defp parse_servers(_) do
    {:error, :invalid_config_format}
  end
  
  defp parse_server_config(name, config) when is_map(config) do
    %{
      name: name,
      command: Map.get(config, "command", ""),
      args: Map.get(config, "args", []),
      env: Map.get(config, "env", %{}),
      cwd: Map.get(config, "cwd")
    }
  end
  
  defp validate_command(""), do: {:error, :empty_command}
  defp validate_command(command) when is_binary(command) do
    case System.find_executable(command) do
      nil -> {:error, {:command_not_found, command}}
      _path -> :ok
    end
  end
  defp validate_command(_), do: {:error, :invalid_command_type}
  
  defp validate_args(args) when is_list(args) do
    if Enum.all?(args, &is_binary/1) do
      :ok
    else
      {:error, :invalid_args_format}
    end
  end
  defp validate_args(_), do: {:error, :invalid_args_type}
  
  defp validate_env(env) when is_map(env) do
    valid = Enum.all?(env, fn {k, v} -> is_binary(k) and is_binary(v) end)
    if valid, do: :ok, else: {:error, :invalid_env_format}
  end
  defp validate_env(_), do: {:error, :invalid_env_type}
  
  defp prioritize_servers(servers, priority_servers) do
    # Put priority servers first
    priority_set = MapSet.new(priority_servers)
    {priority, normal} = Enum.split_with(servers, &MapSet.member?(priority_set, &1))
    priority ++ normal
  end
  
  defp filter_by_viability(servers, server_configs) do
    # Apply cybernetic viability filters
    servers
    |> Enum.filter(fn name ->
      server_config = Map.get(server_configs, name)
      case validate_server(server_config) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    end)
    # Additional viability checks could go here
    |> apply_variety_constraints()
    |> apply_security_constraints()
  end
  
  defp apply_variety_constraints(servers) do
    # Limit variety to prevent overwhelming the system
    # This implements Ashby's Law of Requisite Variety
    max_variety = 15  # Arbitrary limit for now
    Enum.take(servers, max_variety)
  end
  
  defp apply_security_constraints(servers) do
    # Filter out potentially dangerous server types
    # This could be configurable via S5 Policy
    dangerous_patterns = ["exec", "shell", "eval"]
    
    servers
    |> Enum.reject(fn name ->
      Enum.any?(dangerous_patterns, &String.contains?(name, &1))
    end)
  end
  
  defp category_patterns(:database), do: ["postgres", "mysql", "sqlite", "mongo", "redis"]
  defp category_patterns(:search), do: ["search", "exa", "brave", "google", "bing"]
  defp category_patterns(:filesystem), do: ["filesystem", "file", "fs", "disk"]
  defp category_patterns(:communication), do: ["slack", "discord", "email", "gmail", "teams"]
  defp category_patterns(:productivity), do: ["notion", "todoist", "calendar", "task"]
  defp category_patterns(:development), do: ["github", "git", "docker", "kubernetes"]
  defp category_patterns(:cloud), do: ["aws", "gcp", "azure", "cloud"]
  defp category_patterns(:browser), do: ["browser", "puppeteer", "selenium", "chrome"]
  defp category_patterns(_), do: []
  
  defp detect_changes(old_config, new_config) do
    changes = []
    
    # Check for new servers
    new_servers = Map.keys(new_config.servers) -- Map.keys(old_config.servers)
    changes = if length(new_servers) > 0, do: [{:servers_added, new_servers} | changes], else: changes
    
    # Check for removed servers
    removed_servers = Map.keys(old_config.servers) -- Map.keys(new_config.servers)
    changes = if length(removed_servers) > 0, do: [{:servers_removed, removed_servers} | changes], else: changes
    
    # Check for modified servers
    common_servers = Map.keys(old_config.servers) -- removed_servers
    modified_servers = 
      common_servers
      |> Enum.filter(fn name ->
        old_config.servers[name] != new_config.servers[name]
      end)
    
    changes = if length(modified_servers) > 0, do: [{:servers_modified, modified_servers} | changes], else: changes
    
    changes
  end
end