defmodule AutonomousOpponentV2Core.Connections.PoolManager do
  @moduledoc """
  Centralized connection pool manager for all external services.
  
  This module manages connection pools for HTTP clients using Finch,
  providing:
  - Configurable pool sizes per service
  - Health checks and monitoring
  - Circuit breaking per pool
  - Telemetry integration
  - Automatic retry logic
  - Connection draining on shutdown
  
  ## Configuration
  
  Configure pools in your config files:
  
      config :autonomous_opponent_core, :connection_pools,
        openai: [
          size: 50,
          max_idle_time: 5_000,
          conn_opts: [
            transport_opts: [
              timeout: 30_000,
              tcp: [:inet6, nodelay: true]
            ]
          ]
        ],
        anthropic: [
          size: 25,
          max_idle_time: 5_000
        ],
        default: [
          size: 10,
          max_idle_time: 10_000
        ]
  """
  
  use Supervisor
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  
  @type pool_name :: atom()
  @type pool_config :: keyword()
  
  # Public API
  
  @doc """
  Starts the pool manager supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Makes an HTTP request using the specified pool.
  """
  @spec request(pool_name(), Finch.Request.t(), keyword()) :: 
    {:ok, Finch.Response.t()} | {:error, term()}
  def request(pool_name, request, opts \\ []) do
    finch_name = get_finch_name(pool_name)
    circuit_breaker_name = get_circuit_breaker_name(pool_name)
    
    # Check circuit breaker
    case AutonomousOpponentV2Core.Core.CircuitBreaker.call(circuit_breaker_name, fn ->
      do_request(finch_name, request, opts)
    end) do
      {:ok, response} ->
        record_success(pool_name)
        {:ok, response}
        
      {:error, :circuit_open} ->
        record_circuit_open(pool_name)
        {:error, :circuit_open}
        
      {:error, reason} = error ->
        record_failure(pool_name, reason)
        error
    end
  end
  
  @doc """
  Makes an HTTP request and streams the response.
  """
  @spec stream(pool_name(), Finch.Request.t(), term(), (term(), term() -> term())) :: 
    {:ok, term()} | {:error, term()}
  def stream(pool_name, request, acc, fun) do
    finch_name = get_finch_name(pool_name)
    circuit_breaker_name = get_circuit_breaker_name(pool_name)
    
    case AutonomousOpponentV2Core.Core.CircuitBreaker.call(circuit_breaker_name, fn ->
      do_stream(finch_name, request, acc, fun)
    end) do
      {:ok, result} ->
        record_success(pool_name)
        {:ok, result}
        
      {:error, :circuit_open} ->
        record_circuit_open(pool_name)
        {:error, :circuit_open}
        
      {:error, reason} = error ->
        record_failure(pool_name, reason)
        error
    end
  end
  
  @doc """
  Performs a health check on the specified pool.
  """
  @spec health_check(pool_name()) :: :ok | {:error, term()}
  def health_check(pool_name) do
    config = get_pool_config(pool_name)
    health_check_url = Keyword.get(config, :health_check_url)
    
    if health_check_url do
      request = Finch.build(:get, health_check_url)
      
      case request(pool_name, request, timeout: 5_000) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok
          
        {:ok, %{status: status}} ->
          {:error, {:unhealthy, status}}
          
        {:error, :circuit_open} ->
          {:error, :circuit_open}
          
        {:error, reason} ->
          {:error, reason}
          
        # Handle double-nested ok from circuit breaker
        {:ok, {:ok, %{status: status}}} when status in 200..299 ->
          :ok
          
        {:ok, {:ok, %{status: status}}} ->
          {:error, {:unhealthy, status}}
          
        {:ok, {:error, reason}} ->
          {:error, reason}
      end
    else
      # No health check configured, assume healthy
      :ok
    end
  end
  
  @doc """
  Gets current pool statistics.
  """
  @spec get_stats(pool_name()) :: map()
  def get_stats(pool_name) do
    %{
      pool: pool_name,
      circuit_breaker: AutonomousOpponentV2Core.Core.CircuitBreaker.get_state(get_circuit_breaker_name(pool_name)),
      telemetry: get_telemetry_stats(pool_name)
    }
  end
  
  @doc """
  Drains all connections in preparation for shutdown.
  """
  @spec drain_connections() :: :ok
  def drain_connections do
    Logger.info("Draining all connection pools...")
    
    # Get all pool names
    pools = get_configured_pools()
    
    # Drain each pool
    Enum.each(pools, fn {pool_name, _config} ->
      finch_name = get_finch_name(pool_name)
      
      # Finch doesn't have explicit drain, but we can stop accepting new requests
      EventBus.publish(:pool_draining, %{
        pool: pool_name,
        timestamp: DateTime.utc_now()
      })
    end)
    
    # Wait for in-flight requests to complete
    Process.sleep(5_000)
    
    :ok
  end
  
  # Supervisor callbacks
  
  @impl true
  def init(_opts) do
    children = build_children()
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  # Private functions
  
  defp build_children do
    pools = get_configured_pools()
    
    # Create a Finch instance for each configured pool
    finch_children = Enum.map(pools, fn {name, config} ->
      pool_config = build_finch_pool_config(config)
      
      Supervisor.child_spec(
        {Finch, 
         name: get_finch_name(name),
         pools: pool_config},
        id: get_finch_name(name)
      )
    end)
    
    # Create circuit breakers for each pool
    circuit_breaker_children = Enum.map(pools, fn {name, config} ->
      circuit_config = Keyword.get(config, :circuit_breaker, [])
      
      opts = [
        name: get_circuit_breaker_name(name),
        failure_threshold: Keyword.get(circuit_config, :threshold, 5),
        recovery_time_ms: Keyword.get(circuit_config, :timeout, 60_000),
        timeout_ms: 5_000
      ]
      
      Supervisor.child_spec(
        {CircuitBreaker, opts},
        id: get_circuit_breaker_name(name)
      )
    end)
    
    # Health check worker
    health_check_children = [
      {AutonomousOpponentV2Core.Connections.HealthChecker, pools: pools}
    ]
    
    finch_children ++ circuit_breaker_children ++ health_check_children
  end
  
  defp build_finch_pool_config(config) do
    default_config = [
      size: Keyword.get(config, :size, 10),
      count: Keyword.get(config, :count, 1),
      conn_max_idle_time: Keyword.get(config, :conn_max_idle_time, 10_000),
      conn_opts: Keyword.get(config, :conn_opts, [])
    ]
    
    # Configure pools for specific hosts if provided
    case Keyword.get(config, :hosts) do
      nil ->
        # Default pool for all hosts
        %{default: default_config}
        
      hosts when is_list(hosts) ->
        # Specific pools for each host
        Map.new(hosts, fn host ->
          {host, default_config}
        end)
    end
  end
  
  defp do_request(finch_name, request, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    start_time = System.monotonic_time(:millisecond)
    
    try do
      case Finch.request(request, finch_name, receive_timeout: timeout) do
        {:ok, response} ->
          duration = System.monotonic_time(:millisecond) - start_time
          record_request_duration(finch_name, duration)
          {:ok, response}
          
        {:error, reason} = error ->
          error
      end
    catch
      kind, reason ->
        Logger.error("Request failed: #{inspect({kind, reason})}")
        {:error, {kind, reason}}
    end
  end
  
  defp do_stream(finch_name, request, acc, fun) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      case Finch.stream(request, finch_name, acc, fun) do
        {:ok, result} ->
          duration = System.monotonic_time(:millisecond) - start_time
          record_request_duration(finch_name, duration)
          {:ok, result}
          
        {:error, reason} = error ->
          error
      end
    catch
      kind, reason ->
        Logger.error("Stream failed: #{inspect({kind, reason})}")
        {:error, {kind, reason}}
    end
  end
  
  defp get_configured_pools do
    default_pools = [
      openai: [
        size: 50,
        conn_max_idle_time: 5_000,
        hosts: ["https://api.openai.com"],
        health_check_url: "https://api.openai.com/v1/models",
        circuit_breaker: [threshold: 10, timeout: 60_000]
      ],
      anthropic: [
        size: 25,
        conn_max_idle_time: 5_000,
        hosts: ["https://api.anthropic.com"],
        circuit_breaker: [threshold: 5, timeout: 30_000]
      ],
      google_ai: [
        size: 25,
        conn_max_idle_time: 5_000,
        hosts: ["https://generativelanguage.googleapis.com"],
        circuit_breaker: [threshold: 5, timeout: 30_000]
      ],
      local_llm: [
        size: 10,
        conn_max_idle_time: 10_000,
        hosts: ["http://localhost:11434"],
        circuit_breaker: [threshold: 3, timeout: 15_000]
      ],
      default: [
        size: 10,
        conn_max_idle_time: 10_000,
        circuit_breaker: [threshold: 5, timeout: 30_000]
      ]
    ]
    
    configured = Application.get_env(:autonomous_opponent_core, :connection_pools, [])
    
    Keyword.merge(default_pools, configured)
  end
  
  defp get_pool_config(pool_name) do
    pools = get_configured_pools()
    Keyword.get(pools, pool_name, Keyword.get(pools, :default))
  end
  
  defp get_finch_name(pool_name) do
    :"#{__MODULE__}.Finch.#{pool_name}"
  end
  
  defp get_circuit_breaker_name(pool_name) do
    :"#{__MODULE__}.CircuitBreaker.#{pool_name}"
  end
  
  # Telemetry functions
  
  defp record_success(pool_name) do
    :telemetry.execute(
      [:pool_manager, :request, :success],
      %{count: 1},
      %{pool: pool_name}
    )
    
    EventBus.publish(:pool_request_success, %{
      pool: pool_name,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp record_failure(pool_name, reason) do
    :telemetry.execute(
      [:pool_manager, :request, :failure],
      %{count: 1},
      %{pool: pool_name, reason: reason}
    )
    
    EventBus.publish(:pool_request_failure, %{
      pool: pool_name,
      reason: reason,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp record_circuit_open(pool_name) do
    :telemetry.execute(
      [:pool_manager, :circuit, :open],
      %{count: 1},
      %{pool: pool_name}
    )
    
    EventBus.publish(:pool_circuit_open, %{
      pool: pool_name,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp record_request_duration(finch_name, duration) do
    :telemetry.execute(
      [:pool_manager, :request, :duration],
      %{duration: duration},
      %{pool: finch_name}
    )
  end
  
  defp get_telemetry_stats(pool_name) do
    # This would integrate with your telemetry collector
    # For now, return a placeholder
    %{
      requests_total: 0,
      requests_success: 0,
      requests_failed: 0,
      avg_duration_ms: 0
    }
  end
  
end