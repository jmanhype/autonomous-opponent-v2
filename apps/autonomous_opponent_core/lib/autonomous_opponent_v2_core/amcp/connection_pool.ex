defmodule AutonomousOpponentV2Core.AMCP.ConnectionPool do
  @moduledoc """
  Manages a pool of AMQP connections for improved reliability and performance.
  
  This module implements:
  - Connection pooling using Poolboy
  - Automatic retry with exponential backoff
  - Health monitoring
  - Graceful degradation when AMQP is unavailable
  
  **Wisdom Preservation:** Connection pooling prevents single points of failure,
  distributes load, and enables better resource utilization. The exponential
  backoff prevents overwhelming RabbitMQ during recovery scenarios.
  """
  use Supervisor
  require Logger

  @pool_name :amqp_connection_pool
  @max_retries 5
  @initial_backoff 1000  # 1 second
  @max_backoff 60000     # 60 seconds

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    pool_config = [
      name: {:local, @pool_name},
      worker_module: AutonomousOpponentV2Core.AMCP.ConnectionWorker,
      size: get_pool_size(),
      max_overflow: get_max_overflow(),
      strategy: :lifo
    ]

    children = [
      :poolboy.child_spec(@pool_name, pool_config, [])
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Checks out a connection from the pool and executes the given function.
  Automatically returns the connection to the pool when done.
  """
  def with_connection(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    
    :poolboy.transaction(
      @pool_name,
      fn worker ->
        case GenServer.call(worker, :get_channel, timeout) do
          {:ok, channel} -> fun.(channel)
          {:error, reason} -> {:error, reason}
        end
      end,
      timeout
    )
  rescue
    e ->
      Logger.error("Connection pool error: #{inspect(e)}")
      {:error, :pool_error}
  end

  @doc """
  Publishes a message with automatic retry logic.
  """
  def publish_with_retry(exchange, routing_key, payload, opts \\ []) do
    retry_publish(exchange, routing_key, payload, opts, 0)
  end

  defp retry_publish(exchange, routing_key, payload, opts, attempt) when attempt < @max_retries do
    case with_connection(fn channel ->
      publish_message(channel, exchange, routing_key, payload, opts)
    end) do
      :ok -> 
        :ok
      
      {:error, reason} ->
        backoff = calculate_backoff(attempt)
        Logger.warning("Publish failed (attempt #{attempt + 1}/#{@max_retries}): #{inspect(reason)}. Retrying in #{backoff}ms...")
        Process.sleep(backoff)
        retry_publish(exchange, routing_key, payload, opts, attempt + 1)
    end
  end

  defp retry_publish(_exchange, _routing_key, _payload, _opts, _attempt) do
    Logger.error("Failed to publish message after #{@max_retries} attempts")
    {:error, :max_retries_exceeded}
  end

  defp publish_message(channel, exchange, routing_key, payload, opts) do
    try do
      cond do
        channel == :stub_channel ->
          # Stub mode
          Logger.debug("Publishing in stub mode - using stub channel")
          :ok
          
        Code.ensure_loaded?(AMQP) and function_exported?(AMQP.Basic, :publish, 5) ->
          # Real AMQP mode
          AMQP.Basic.publish(
            channel,
            exchange,
            routing_key,
            Jason.encode!(payload),
            Keyword.merge([persistent: true], opts)
          )
          
        true ->
          # AMQP not available
          Logger.warning("Publishing in stub mode - AMQP not available")
          :ok
      end
    rescue
      e ->
        {:error, e}
    end
  end

  defp calculate_backoff(attempt) do
    backoff = @initial_backoff * :math.pow(2, attempt) |> round()
    min(backoff, @max_backoff)
  end

  @doc """
  Returns the health status of the connection pool.
  """
  def health_check do
    pool_status = :poolboy.status(@pool_name)
    
    healthy_workers = 
      with_connection(fn _channel ->
        :ok
      end, timeout: 1000) == :ok

    %{
      pool_status: pool_status,
      healthy: healthy_workers,
      pool_size: get_pool_size(),
      max_overflow: get_max_overflow()
    }
  rescue
    _ -> %{healthy: false, error: "Pool not available"}
  end

  defp get_pool_size do
    Application.get_env(:autonomous_opponent_core, :amqp_pool_size, 10)
  end

  defp get_max_overflow do
    Application.get_env(:autonomous_opponent_core, :amqp_max_overflow, 5)
  end
end