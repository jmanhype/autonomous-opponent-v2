defmodule AutonomousOpponentV2Core.Security.SecretsManager do
  @moduledoc """
  Central secrets management for the Autonomous Opponent system.
  
  This module provides a unified interface for secure secret handling, including:
  - Secure environment variable access
  - HashiCorp Vault integration
  - Secret rotation capabilities
  - Audit logging for secret access
  
  ## VSM Integration
  
  This module supports S4 (Intelligence) and S5 (Policy) subsystems by:
  - Securing API keys for intelligence operations
  - Enforcing security policies through centralized secret management
  - Triggering algedonic signals on security breaches
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Security.VaultClient
  # alias AutonomousOpponentV2Core.Security.Encryption
  
  defstruct [
    :vault_client,
    :cache,
    :rotation_schedule,
    :audit_log,
    :config
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Retrieve a secret value by key.
  
  Attempts to retrieve from:
  1. In-memory cache (if enabled)
  2. HashiCorp Vault (if configured)
  3. Environment variables (fallback)
  """
  def get_secret(key, opts \\ []) do
    GenServer.call(__MODULE__, {:get_secret, key, opts})
  end
  
  @doc """
  Store or update a secret in Vault.
  """
  def put_secret(key, value, opts \\ []) do
    GenServer.call(__MODULE__, {:put_secret, key, value, opts})
  end
  
  @doc """
  Rotate a secret (generate new value and update).
  """
  def rotate_secret(key, generator_fn \\ nil) do
    GenServer.call(__MODULE__, {:rotate_secret, key, generator_fn})
  end
  
  @doc """
  List all available secret keys (not values).
  """
  def list_secrets do
    GenServer.call(__MODULE__, :list_secrets)
  end
  
  @doc """
  Get audit log for secret access.
  """
  def get_audit_log(opts \\ []) do
    GenServer.call(__MODULE__, {:get_audit_log, opts})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    config = build_config(opts)
    
    # Vault client is started by supervisor if enabled
    vault_client = if config.vault_enabled do
      # Check if VaultClient is running
      case Process.whereis(VaultClient) do
        nil ->
          Logger.warning("Vault is enabled but VaultClient is not running")
          nil
        pid ->
          pid
      end
    else
      nil
    end
    
    state = %__MODULE__{
      vault_client: vault_client,
      cache: %{},
      rotation_schedule: init_rotation_schedule(config),
      audit_log: [],
      config: config
    }
    
    # Subscribe to security events
    EventBus.subscribe(:security_breach)
    EventBus.subscribe(:key_rotation_required)
    
    # Schedule periodic rotations
    schedule_rotations(state)
    
    Logger.info("Secrets Manager initialized with Vault: #{config.vault_enabled}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_secret, key, opts}, {from_pid, _}, state) do
    # Check cache first
    case get_from_cache(state.cache, key, opts) do
      {:ok, value} ->
        audit_access(state, key, from_pid, :cache_hit)
        {:reply, {:ok, value}, state}
        
      :miss ->
        # Try Vault
        case get_from_vault(state.vault_client, key) do
          {:ok, value} ->
            new_cache = maybe_cache_value(state.cache, key, value, opts)
            audit_access(state, key, from_pid, :vault_hit)
            {:reply, {:ok, value}, %{state | cache: new_cache}}
            
          :not_found ->
            # Fall back to environment
            case get_from_env(key, state.config) do
              {:ok, value} ->
                audit_access(state, key, from_pid, :env_hit)
                {:reply, {:ok, value}, state}
                
              :not_found ->
                audit_access(state, key, from_pid, :not_found)
                {:reply, {:error, :secret_not_found}, state}
            end
        end
    end
  end
  
  @impl true
  def handle_call({:put_secret, key, value, opts}, {from_pid, _}, state) do
    # Validate secret format
    case validate_secret(key, value, opts) do
      :ok ->
        # Store in Vault if available
        result = if state.vault_client do
          VaultClient.write_secret(state.vault_client, key, value, opts)
        else
          {:error, :vault_not_configured}
        end
        
        case result do
          :ok ->
            # Clear from cache to force refresh
            new_cache = Map.delete(state.cache, key)
            audit_write(state, key, from_pid, :success)
            
            # Publish event
            EventBus.publish(:secret_updated, %{key: key, timestamp: DateTime.utc_now()})
            
            {:reply, :ok, %{state | cache: new_cache}}
            
          {:error, reason} ->
            audit_write(state, key, from_pid, {:error, reason})
            {:reply, {:error, reason}, state}
        end
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:rotate_secret, key, generator_fn}, {from_pid, _}, state) do
    # Generate new secret value
    generator = generator_fn || default_generator_for_key(key)
    
    case generator.() do
      {:ok, new_value} ->
        # Store new value
        case handle_call({:put_secret, key, new_value, [rotation: true]}, {from_pid, nil}, state) do
          {:reply, :ok, new_state} ->
            # Publish rotation event
            EventBus.publish(:secret_rotated, %{
              key: key,
              timestamp: DateTime.utc_now(),
              next_rotation: calculate_next_rotation(key, state)
            })
            
            {:reply, {:ok, new_value}, new_state}
            
          {:reply, error, new_state} ->
            {:reply, error, new_state}
        end
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:list_secrets, _from, state) do
    # Get keys from all sources
    env_keys = list_env_secrets(state.config)
    vault_keys = if state.vault_client do
      case VaultClient.list_secrets(state.vault_client) do
        {:ok, keys} -> keys
        _ -> []
      end
    else
      []
    end
    
    all_keys = Enum.uniq(env_keys ++ vault_keys)
    {:reply, {:ok, all_keys}, state}
  end
  
  @impl true
  def handle_call({:get_audit_log, opts}, _from, state) do
    filtered_log = filter_audit_log(state.audit_log, opts)
    {:reply, {:ok, filtered_log}, state}
  end
  
  @impl true
  def handle_info(:rotate_secrets, state) do
    # Rotate secrets based on schedule
    rotated_keys = Enum.filter(state.rotation_schedule, fn {_key, schedule} ->
      should_rotate?(schedule)
    end)
    |> Enum.map(fn {key, _schedule} -> key end)
    
    # Perform rotations
    Enum.each(rotated_keys, fn key ->
      case rotate_secret(key) do
        {:ok, _} ->
          Logger.info("Successfully rotated secret: #{key}")
        {:error, reason} ->
          Logger.error("Failed to rotate secret #{key}: #{inspect(reason)}")
          # Trigger algedonic signal
          EventBus.publish(:security_alert, %{
            type: :rotation_failure,
            key: key,
            reason: reason,
            severity: :high
          })
      end
    end)
    
    # Schedule next rotation check
    schedule_rotations(state)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :security_breach, %{key: key}}, state) do
    # Immediate rotation on security breach
    Logger.warning("Security breach detected for key: #{key}. Rotating immediately.")
    
    case rotate_secret(key) do
      {:ok, _} ->
        Logger.info("Emergency rotation completed for: #{key}")
      {:error, reason} ->
        Logger.error("Emergency rotation failed for #{key}: #{inspect(reason)}")
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :key_rotation_required, %{key: key}}, state) do
    # External rotation request
    rotate_secret(key)
    {:noreply, state}
  end
  
  # Private Functions
  
  defp build_config(opts) do
    %{
      vault_enabled: opts[:vault_enabled] || System.get_env("VAULT_ENABLED") == "true",
      vault_config: %{
        address: opts[:vault_address] || System.get_env("VAULT_ADDR") || "http://localhost:8200",
        token: opts[:vault_token] || System.get_env("VAULT_TOKEN"),
        namespace: opts[:vault_namespace] || "autonomous-opponent",
        engine: opts[:vault_engine] || "secret"
      },
      cache_ttl: opts[:cache_ttl] || :timer.minutes(5),
      audit_retention: opts[:audit_retention] || :timer.hours(24),
      env_prefix: opts[:env_prefix] || "AUTONOMOUS_OPPONENT_",
      allowed_env_keys: opts[:allowed_env_keys] || [
        "OPENAI_API_KEY",
        "DATABASE_URL",
        "SECRET_KEY_BASE",
        "GUARDIAN_SECRET"
      ]
    }
  end
  
  defp init_rotation_schedule(_config) do
    # Default rotation schedule for known secrets
    %{
      "OPENAI_API_KEY" => %{
        interval: :timer.hours(24 * 30), # Monthly
        last_rotation: DateTime.utc_now()
      },
      "DATABASE_PASSWORD" => %{
        interval: :timer.hours(24 * 90), # Quarterly
        last_rotation: DateTime.utc_now()
      },
      "SECRET_KEY_BASE" => %{
        interval: :timer.hours(24 * 180), # Semi-annually
        last_rotation: DateTime.utc_now()
      }
    }
  end
  
  defp schedule_rotations(_state) do
    Process.send_after(self(), :rotate_secrets, :timer.hours(1))
  end
  
  defp get_from_cache(cache, key, _opts) do
    case Map.get(cache, key) do
      nil -> :miss
      {value, expiry} ->
        if DateTime.compare(DateTime.utc_now(), expiry) == :lt do
          {:ok, value}
        else
          :miss
        end
    end
  end
  
  defp get_from_vault(nil, _key), do: :not_found
  defp get_from_vault(vault_client, key) do
    case VaultClient.read_secret(vault_client, key) do
      {:ok, value} -> {:ok, value}
      _ -> :not_found
    end
  end
  
  defp get_from_env(key, config) do
    # Check if key is allowed
    if key in config.allowed_env_keys do
      env_key = config.env_prefix <> key
      case System.get_env(env_key) || System.get_env(key) do
        nil -> :not_found
        value -> {:ok, value}
      end
    else
      :not_found
    end
  end
  
  defp maybe_cache_value(cache, key, value, opts) do
    if Keyword.get(opts, :cache, true) do
      ttl = Keyword.get(opts, :ttl, :timer.minutes(5))
      expiry = DateTime.add(DateTime.utc_now(), ttl, :millisecond)
      Map.put(cache, key, {value, expiry})
    else
      cache
    end
  end
  
  defp validate_secret(key, value, _opts) do
    cond do
      is_nil(key) or key == "" ->
        {:error, :invalid_key}
        
      is_nil(value) or value == "" ->
        {:error, :invalid_value}
        
      String.contains?(key, " ") ->
        {:error, :key_contains_spaces}
        
      byte_size(value) > 65536 ->
        {:error, :value_too_large}
        
      true ->
        :ok
    end
  end
  
  defp default_generator_for_key(key) do
    case key do
      "OPENAI_API_KEY" ->
        fn -> {:ok, "sk-" <> generate_random_string(48)} end
        
      "SECRET_KEY_BASE" ->
        fn -> {:ok, generate_random_string(64)} end
        
      _ ->
        fn -> {:ok, generate_random_string(32)} end
    end
  end
  
  defp generate_random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64(padding: false)
    |> String.slice(0, length)
  end
  
  defp should_rotate?(%{interval: interval, last_rotation: last}) do
    diff = DateTime.diff(DateTime.utc_now(), last, :millisecond)
    diff >= interval
  end
  
  defp calculate_next_rotation(key, state) do
    case Map.get(state.rotation_schedule, key) do
      %{interval: interval} ->
        DateTime.add(DateTime.utc_now(), interval, :millisecond)
      _ ->
        DateTime.add(DateTime.utc_now(), :timer.hours(24 * 30), :millisecond)
    end
  end
  
  defp audit_access(state, key, from_pid, result) do
    entry = %{
      type: :access,
      key: key,
      pid: inspect(from_pid),
      result: result,
      timestamp: DateTime.utc_now()
    }
    
    # Keep limited audit history
    new_log = [entry | state.audit_log] |> Enum.take(1000)
    %{state | audit_log: new_log}
  end
  
  defp audit_write(state, key, from_pid, result) do
    entry = %{
      type: :write,
      key: key,
      pid: inspect(from_pid),
      result: result,
      timestamp: DateTime.utc_now()
    }
    
    new_log = [entry | state.audit_log] |> Enum.take(1000)
    %{state | audit_log: new_log}
  end
  
  defp filter_audit_log(log, opts) do
    log
    |> maybe_filter_by_type(opts[:type])
    |> maybe_filter_by_key(opts[:key])
    |> maybe_filter_by_time(opts[:since])
    |> Enum.take(opts[:limit] || 100)
  end
  
  defp maybe_filter_by_type(log, nil), do: log
  defp maybe_filter_by_type(log, type), do: Enum.filter(log, & &1.type == type)
  
  defp maybe_filter_by_key(log, nil), do: log
  defp maybe_filter_by_key(log, key), do: Enum.filter(log, & &1.key == key)
  
  defp maybe_filter_by_time(log, nil), do: log
  defp maybe_filter_by_time(log, since) do
    Enum.filter(log, fn entry ->
      DateTime.compare(entry.timestamp, since) == :gt
    end)
  end
  
  defp list_env_secrets(config) do
    config.allowed_env_keys
  end
end