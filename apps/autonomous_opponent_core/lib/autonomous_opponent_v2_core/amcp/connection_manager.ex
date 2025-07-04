defmodule AutonomousOpponentV2Core.AMCP.ConnectionManager do
  @moduledoc """
  Legacy interface for AMQP connections. Now delegates to ConnectionPool.
  
  This module maintains backward compatibility while using the new
  connection pool infrastructure for improved reliability.

  **Wisdom Preservation:** Maintaining backward compatibility allows
  gradual migration of existing code while immediately benefiting from
  the improved connection pooling and retry logic.
  """
  use GenServer
  require Logger

  alias AutonomousOpponentV2Core.AMCP.{ConnectionPool, Topology}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("ConnectionManager initialized, delegating to ConnectionPool")
    
    # Ensure topology is declared for all connections
    Task.start(fn ->
      Process.sleep(2000)  # Wait for pool to initialize
      declare_initial_topology()
    end)
    
    {:ok, %{}}
  end

  @impl true
  def handle_call(:get_channel, _from, state) do
    # Get a channel from the pool
    result = ConnectionPool.with_connection(fn channel -> 
      {:ok, channel}
    end)
    
    case result do
      {:ok, channel} -> {:reply, channel, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  @doc """
  Returns an AMQP channel for publishing and consuming messages.
  
  Note: This now returns a channel from the connection pool. The channel
  should be used immediately and not stored, as it will be returned to
  the pool after use.
  """
  def get_channel do
    GenServer.call(__MODULE__, :get_channel)
  end

  @doc """
  Publishes a message using the connection pool with retry logic.
  """
  def publish(exchange, routing_key, message, opts \\ []) do
    ConnectionPool.publish_with_retry(exchange, routing_key, message, opts)
  end

  @doc """
  Returns the health status of the AMQP connections.
  """
  def health_check do
    ConnectionPool.health_check()
  end

  defp declare_initial_topology do
    ConnectionPool.with_connection(fn channel ->
      Topology.declare_topology(channel)
    end)
  rescue
    e ->
      Logger.error("Failed to declare initial topology: #{inspect(e)}")
  end
end
