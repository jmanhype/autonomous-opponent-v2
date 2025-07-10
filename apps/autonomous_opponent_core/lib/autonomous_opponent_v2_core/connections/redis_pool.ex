defmodule AutonomousOpponentV2Core.Connections.RedisPool do
  @moduledoc """
  Redis connection pool for distributed components.
  
  Provides managed Redis connections with:
  - Connection pooling via poolboy
  - Circuit breaker protection
  - Graceful degradation
  - Sentinel support for HA
  - TLS/SSL encryption
  - Comprehensive telemetry
  """
  
  use Supervisor
  require Logger
  
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  alias AutonomousOpponentV2Core.EventBus
  
  @pool_name :redis_pool
  @default_pool_size 10
  @default_overflow 5
  @circuit_breaker_name :redis_circuit
  @health_check_interval 30_000
  
  # Public API
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Executes a Redis command with circuit breaker protection.
  """
  def command(args, opts \\ []) do
    start_time = System.monotonic_time()
    
    result = CircuitBreaker.call(@circuit_breaker_name, fn ->
      :poolboy.transaction(@pool_name, fn worker ->
        Redix.command(worker, args, timeout: opts[:timeout] || 5000)
      end, opts[:checkout_timeout] || 5000)
    end)
    
    # Unwrap nested {:ok, result} from CircuitBreaker
    unwrapped_result = case result do
      {:ok, inner_result} -> inner_result
      error -> error
    end
    
    emit_telemetry(:command, start_time, unwrapped_result, args)
    handle_result(unwrapped_result, args)
  end
  
  @doc """
  Executes multiple Redis commands in a pipeline.
  """
  def pipeline(commands, opts \\ []) do
    start_time = System.monotonic_time()
    
    result = CircuitBreaker.call(@circuit_breaker_name, fn ->
      :poolboy.transaction(@pool_name, fn worker ->
        Redix.pipeline(worker, commands, timeout: opts[:timeout] || 5000)
      end, opts[:checkout_timeout] || 5000)
    end)
    
    # Unwrap nested {:ok, result} from CircuitBreaker
    unwrapped_result = case result do
      {:ok, inner_result} -> inner_result
      error -> error
    end
    
    emit_telemetry(:pipeline, start_time, unwrapped_result, length(commands))
    handle_result(unwrapped_result, commands)
  end
  
  @doc """
  Executes a Lua script with circuit breaker protection.
  """
  def eval_script(script, keys, args, opts \\ []) do
    command(["EVAL", script, length(keys)] ++ keys ++ args, opts)
  end
  
  @doc """
  Executes a cached Lua script by SHA.
  """
  def evalsha(sha, keys, args, opts \\ []) do
    case command(["EVALSHA", sha, length(keys)] ++ keys ++ args, opts) do
      {:error, %Redix.Error{message: "NOSCRIPT" <> _}} = error ->
        Logger.warning("Redis script not found, needs reloading: #{sha}")
        error
        
      result ->
        result
    end
  end
  
  @doc """
  Loads a Lua script into Redis and returns its SHA.
  """
  def load_script(script) do
    case command(["SCRIPT", "LOAD", script]) do
      {:ok, sha} when is_binary(sha) ->
        Logger.info("Loaded Redis script with SHA: #{sha}")
        {:ok, sha}
        
      error ->
        Logger.error("Failed to load Redis script: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Checks if Redis is available and healthy.
  """
  def health_check do
    case command(["PING"]) do
      {:ok, "PONG"} -> :ok
      error -> {:error, error}
    end
  end
  
  # Supervisor callbacks
  
  @impl true
  def init(opts) do
    # Initialize circuit breaker
    CircuitBreaker.initialize(@circuit_breaker_name)
    
    # Get Redis configuration
    {redis_config, pool_settings} = get_redis_config()
    
    # Pool configuration
    pool_config = [
      name: {:local, @pool_name},
      worker_module: Redix,
      size: pool_settings[:pool_size] || @default_pool_size,
      max_overflow: pool_settings[:max_overflow] || @default_overflow,
      strategy: :fifo
    ]
    
    # Start health check timer
    :timer.send_interval(@health_check_interval, self(), :health_check)
    
    children = [
      :poolboy.child_spec(@pool_name, pool_config, redis_config)
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @impl true
  def handle_info(:health_check, state) do
    spawn(fn ->
      case health_check() do
        :ok ->
          Logger.debug("Redis health check passed")
          
        {:error, reason} ->
          Logger.error("Redis health check failed: #{inspect(reason)}")
          
          # Emit algedonic pain signal
          EventBus.publish(:algedonic_pain, %{
            source: :redis_pool,
            severity: :high,
            reason: {:health_check_failed, reason},
            timestamp: DateTime.utc_now(),
            action: :investigate_redis_connection
          })
      end
    end)
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp get_redis_config do
    base_config = [
      host: Application.get_env(:autonomous_opponent_core, :redis_host, "localhost"),
      port: Application.get_env(:autonomous_opponent_core, :redis_port, 6379),
      database: Application.get_env(:autonomous_opponent_core, :redis_database, 0)
    ]
    
    # Store pool settings separately (not for Redix)
    pool_settings = [
      pool_size: Application.get_env(:autonomous_opponent_core, :redis_pool_size, @default_pool_size),
      max_overflow: Application.get_env(:autonomous_opponent_core, :redis_max_overflow, @default_overflow)
    ]
    
    # Add authentication if configured
    config = if redis_password = get_redis_password() do
      Keyword.put(base_config, :password, redis_password)
    else
      base_config
    end
    
    # Add SSL/TLS if configured
    config = if Application.get_env(:autonomous_opponent_core, :redis_ssl_enabled, false) do
      ssl_opts = [
        verify: :verify_peer,
        cacertfile: Application.get_env(:autonomous_opponent_core, :redis_cacertfile),
        certfile: Application.get_env(:autonomous_opponent_core, :redis_certfile),
        keyfile: Application.get_env(:autonomous_opponent_core, :redis_keyfile),
        depth: 3
      ]
      config
      |> Keyword.put(:ssl, true)
      |> Keyword.put(:socket_opts, [:inet6] ++ [ssl_options: ssl_opts])
    else
      config
    end
    
    # Add Sentinel configuration if available
    config = if sentinels = Application.get_env(:autonomous_opponent_core, :redis_sentinels) do
      config
      |> Keyword.put(:sentinels, sentinels)
      |> Keyword.put(:group, Application.get_env(:autonomous_opponent_core, :redis_sentinel_group, "mymaster"))
    else
      config
    end
    
    # Return both Redix config and pool settings
    {config, pool_settings}
  end
  
  defp get_redis_password do
    # Try multiple sources for Redis password
    cond do
      # Environment variable
      password = System.get_env("REDIS_PASSWORD") -> password
      
      # Application config
      password = Application.get_env(:autonomous_opponent_core, :redis_password) -> password
      
      # No password configured
      true -> nil
    end
  end
  
  defp handle_result({:ok, _} = result, _context), do: result
  
  defp handle_result({:error, %Redix.ConnectionError{reason: reason}} = error, context) do
    Logger.error("Redis connection error: #{inspect(reason)}, context: #{inspect(context)}")
    
    EventBus.publish(:redis_connection_failure, %{
      reason: reason,
      context: context,
      timestamp: DateTime.utc_now()
    })
    
    error
  end
  
  defp handle_result({:error, %Redix.Error{message: message}} = error, context) do
    Logger.error("Redis command error: #{message}, context: #{inspect(context)}")
    
    EventBus.publish(:redis_command_error, %{
      message: message,
      context: context,
      timestamp: DateTime.utc_now()
    })
    
    error
  end
  
  defp handle_result({:error, :circuit_open} = error, context) do
    Logger.warning("Redis circuit breaker open, context: #{inspect(context)}")
    
    EventBus.publish(:redis_circuit_open, %{
      context: context,
      timestamp: DateTime.utc_now()
    })
    
    error
  end
  
  defp handle_result(error, context) do
    Logger.error("Unexpected Redis error: #{inspect(error)}, context: #{inspect(context)}")
    error
  end
  
  defp emit_telemetry(operation, start_time, result, metadata) do
    duration = System.monotonic_time() - start_time
    
    measurements = %{
      duration: duration,
      pool_size: @default_pool_size
    }
    
    metadata = Map.new()
    |> Map.put(:operation, operation)
    |> Map.put(:success, match?({:ok, _}, result))
    |> Map.put(:metadata, metadata)
    
    :telemetry.execute(
      [:autonomous_opponent, :redis, operation],
      measurements,
      metadata
    )
  end
end