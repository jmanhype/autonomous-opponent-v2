defmodule AutonomousOpponentV2Core.Security.VaultClient do
  @moduledoc """
  HashiCorp Vault client for secure secret storage and retrieval.
  
  This module provides integration with HashiCorp Vault for:
  - Secure secret storage
  - Dynamic secret generation
  - Secret versioning and history
  - Access control and auditing
  
  ## Configuration
  
  The Vault client requires:
  - VAULT_ADDR: Vault server address
  - VAULT_TOKEN: Authentication token
  - VAULT_NAMESPACE: Optional namespace for multi-tenancy
  """
  
  use GenServer
  require Logger
  
  alias Vaultex.Client
  
  defstruct [
    :config,
    :connection,
    :health_check_interval,
    :last_health_check,
    :is_healthy
  ]
  
  # Client API
  
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end
  
  @doc """
  Read a secret from Vault.
  """
  def read_secret(client \\ __MODULE__, key) do
    GenServer.call(client, {:read_secret, key})
  end
  
  @doc """
  Write a secret to Vault.
  """
  def write_secret(client \\ __MODULE__, key, value, opts \\ []) do
    GenServer.call(client, {:write_secret, key, value, opts})
  end
  
  @doc """
  Delete a secret from Vault.
  """
  def delete_secret(client \\ __MODULE__, key) do
    GenServer.call(client, {:delete_secret, key})
  end
  
  @doc """
  List all secrets in the configured path.
  """
  def list_secrets(client \\ __MODULE__) do
    GenServer.call(client, :list_secrets)
  end
  
  @doc """
  Check Vault health status.
  """
  def health_check(client \\ __MODULE__) do
    GenServer.call(client, :health_check)
  end
  
  @doc """
  Get secret metadata (versions, created/updated times).
  """
  def get_metadata(client \\ __MODULE__, key) do
    GenServer.call(client, {:get_metadata, key})
  end
  
  # Server Callbacks
  
  @impl true
  def init(config) do
    # Configure Vaultex client
    vault_config = %{
      host: config.address || "http://localhost:8200",
      auth_method: :token,
      token: config.token,
      engine: config.engine || "secret",
      http_options: [timeout: 5000, recv_timeout: 5000]
    }
    
    # Test connection
    Application.put_env(:vaultex, :vault_addr, vault_config.host)
    Application.put_env(:vaultex, :vault_token, vault_config.token)
    
    state = %__MODULE__{
      config: Map.merge(config, vault_config),
      connection: nil,
      health_check_interval: :timer.seconds(30),
      last_health_check: nil,
      is_healthy: false
    }
    
    # Initial health check
    case perform_health_check() do
      {:ok, _} ->
        Logger.info("Vault connection established successfully")
        schedule_health_check(state)
        {:ok, %{state | is_healthy: true, last_health_check: DateTime.utc_now()}}
        
      {:error, reason} ->
        Logger.error("Failed to connect to Vault: #{inspect(reason)}")
        schedule_health_check(state)
        {:ok, %{state | is_healthy: false}}
    end
  end
  
  @impl true
  def handle_call({:read_secret, key}, _from, state) do
    if state.is_healthy do
      path = build_path(state.config, key)
      
      case Vaultex.read(path, :token, {state.config.token}) do
        {:ok, %{"data" => data}} ->
          # Handle KV v2 format
          value = get_in(data, ["data", "value"]) || get_in(data, ["value"])
          {:reply, {:ok, value}, state}
          
        {:ok, data} when is_map(data) ->
          # Handle KV v1 format
          value = Map.get(data, "value") || Map.get(data, key)
          {:reply, {:ok, value}, state}
          
        {:error, ["Key not found"]} ->
          {:reply, :not_found, state}
          
        error ->
          Logger.error("Vault read error: #{inspect(error)}")
          {:reply, {:error, :vault_error}, state}
      end
    else
      {:reply, {:error, :vault_unhealthy}, state}
    end
  end
  
  @impl true
  def handle_call({:write_secret, key, value, opts}, _from, state) do
    if state.is_healthy do
      path = build_path(state.config, key)
      
      # Prepare data based on KV version
      data = if kv_v2?(state.config) do
        %{
          "data" => %{
            "value" => value,
            "metadata" => build_metadata(opts)
          }
        }
      else
        %{"value" => value}
      end
      
      case Vaultex.write(path, data, :token, {state.config.token}) do
        {:ok, _} ->
          Logger.debug("Secret written to Vault: #{key}")
          {:reply, :ok, state}
          
        error ->
          Logger.error("Vault write error: #{inspect(error)}")
          {:reply, {:error, :vault_write_failed}, state}
      end
    else
      {:reply, {:error, :vault_unhealthy}, state}
    end
  end
  
  @impl true
  def handle_call({:delete_secret, key}, _from, state) do
    if state.is_healthy do
      path = build_path(state.config, key)
      
      case Vaultex.delete(path, :token, {state.config.token}) do
        {:ok, _} ->
          Logger.debug("Secret deleted from Vault: #{key}")
          {:reply, :ok, state}
          
        error ->
          Logger.error("Vault delete error: #{inspect(error)}")
          {:reply, {:error, :vault_delete_failed}, state}
      end
    else
      {:reply, {:error, :vault_unhealthy}, state}
    end
  end
  
  @impl true
  def handle_call(:list_secrets, _from, state) do
    if state.is_healthy do
      path = build_list_path(state.config)
      
      case Vaultex.list(path, :token, {state.config.token}) do
        {:ok, %{"data" => %{"keys" => keys}}} ->
          {:reply, {:ok, keys}, state}
          
        {:ok, %{"keys" => keys}} ->
          {:reply, {:ok, keys}, state}
          
        error ->
          Logger.error("Vault list error: #{inspect(error)}")
          {:reply, {:error, :vault_list_failed}, state}
      end
    else
      {:reply, {:error, :vault_unhealthy}, state}
    end
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    case perform_health_check() do
      {:ok, info} ->
        new_state = %{state | 
          is_healthy: true, 
          last_health_check: DateTime.utc_now()
        }
        {:reply, {:ok, info}, new_state}
        
      {:error, reason} ->
        new_state = %{state | 
          is_healthy: false, 
          last_health_check: DateTime.utc_now()
        }
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_call({:get_metadata, key}, _from, state) do
    if state.is_healthy and kv_v2?(state.config) do
      metadata_path = build_metadata_path(state.config, key)
      
      case Vaultex.read(metadata_path, :token, {state.config.token}) do
        {:ok, %{"data" => metadata}} ->
          {:reply, {:ok, metadata}, state}
          
        error ->
          Logger.error("Vault metadata error: #{inspect(error)}")
          {:reply, {:error, :metadata_read_failed}, state}
      end
    else
      {:reply, {:error, :not_supported}, state}
    end
  end
  
  @impl true
  def handle_info(:health_check, state) do
    case perform_health_check() do
      {:ok, _} ->
        unless state.is_healthy do
          Logger.info("Vault connection restored")
        end
        
        schedule_health_check(state)
        {:noreply, %{state | is_healthy: true, last_health_check: DateTime.utc_now()}}
        
      {:error, reason} ->
        if state.is_healthy do
          Logger.error("Vault connection lost: #{inspect(reason)}")
        end
        
        schedule_health_check(state)
        {:noreply, %{state | is_healthy: false, last_health_check: DateTime.utc_now()}}
    end
  end
  
  # Private Functions
  
  defp perform_health_check do
    # Use Vaultex health endpoint or sys/health
    case Vaultex.read("sys/health", :token, {}) do
      {:ok, data} ->
        {:ok, data}
        
      {:error, reason} ->
        # Try alternative health check
        case HTTPoison.get(Application.get_env(:vaultex, :vault_addr) <> "/v1/sys/health") do
          {:ok, %{status_code: code}} when code in 200..299 ->
            {:ok, %{status: :healthy}}
            
          _ ->
            {:error, reason}
        end
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  end
  
  defp schedule_health_check(state) do
    Process.send_after(self(), :health_check, state.health_check_interval)
  end
  
  defp build_path(config, key) do
    namespace = config[:namespace] || "autonomous-opponent"
    engine = config[:engine] || "secret"
    
    if kv_v2?(config) do
      "#{engine}/data/#{namespace}/#{key}"
    else
      "#{engine}/#{namespace}/#{key}"
    end
  end
  
  defp build_list_path(config) do
    namespace = config[:namespace] || "autonomous-opponent"
    engine = config[:engine] || "secret"
    
    if kv_v2?(config) do
      "#{engine}/metadata/#{namespace}"
    else
      "#{engine}/#{namespace}"
    end
  end
  
  defp build_metadata_path(config, key) do
    namespace = config[:namespace] || "autonomous-opponent"
    engine = config[:engine] || "secret"
    
    "#{engine}/metadata/#{namespace}/#{key}"
  end
  
  defp kv_v2?(config) do
    # Default to KV v2 unless explicitly set to v1
    config[:kv_version] != 1
  end
  
  defp build_metadata(opts) do
    %{
      "created_by" => opts[:created_by] || "system",
      "rotation" => opts[:rotation] || false,
      "expires_at" => opts[:expires_at],
      "tags" => opts[:tags] || []
    }
  end
end