# This module is conditionally compiled based on AMQP availability
if Code.ensure_loaded?(AMQP) do
  defmodule AutonomousOpponentV2Core.AMCP.ConnectionPool do
    @moduledoc """
    Manages a pool of AMQP connections with automatic retry, health monitoring,
    and exponential backoff for resilient message transport.
    
    **Wisdom Preservation:** Connection pooling prevents single point of failure,
    enables load distribution, and provides resilience through redundancy.
    Exponential backoff prevents thundering herd problems during recovery.
    """
    use GenServer
    require Logger
    
    alias AMQP.{Connection, Channel}
    alias AutonomousOpponentV2Core.AMCP.Topology
    alias AutonomousOpponentV2Core.CircuitBreaker
    
    @default_pool_size 5
    @initial_backoff 1_000
    @max_backoff 30_000
    @heartbeat_interval 30_000
    @connection_timeout 5_000
    
    defmodule State do
      @moduledoc false
      defstruct [
        :pool_size,
        :connection_opts,
        connections: %{},
        channels: %{},
        health_status: %{},
        retry_counts: %{},
        backoff_times: %{}
      ]
    end
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    @impl true
    def init(opts) do
      pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
      connection_opts = Application.get_env(:autonomous_opponent_core, :amqp_connection, [])
      
      # Add heartbeat and connection timeout
      connection_opts = connection_opts
        |> Keyword.put(:heartbeat, 30)
        |> Keyword.put(:connection_timeout, @connection_timeout)
      
      state = %State{
        pool_size: pool_size,
        connection_opts: connection_opts
      }
      
      # Start initial connections
      send(self(), :init_connections)
      
      # Schedule periodic health checks
      Process.send_after(self(), :health_check, @heartbeat_interval)
      
      {:ok, state}
    end
    
    @impl true
    def handle_info(:init_connections, state) do
      state = Enum.reduce(1..state.pool_size, state, fn conn_id, acc ->
        establish_connection(conn_id, acc)
      end)
      
      {:noreply, state}
    end
    
    @impl true
    def handle_info(:health_check, state) do
      state = perform_health_check(state)
      Process.send_after(self(), :health_check, @heartbeat_interval)
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:retry_connection, conn_id}, state) do
      state = establish_connection(conn_id, state)
      {:noreply, state}
    end
    
    @impl true
    def handle_call(:get_channel, _from, state) do
      case get_healthy_channel(state) do
        {:ok, channel} ->
          {:reply, {:ok, channel}, state}
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
    
    @impl true
    def handle_call(:health_status, _from, state) do
      status = %{
        total_connections: state.pool_size,
        healthy_connections: Enum.count(state.health_status, fn {_, healthy} -> healthy end),
        connection_details: state.health_status
      }
      {:reply, status, state}
    end
    
    @impl true
    def terminate(_reason, state) do
      Logger.info("Shutting down AMQP connection pool...")
      
      # Close all connections gracefully
      Enum.each(state.connections, fn {_id, conn} ->
        try do
          Connection.close(conn)
        catch
          _, _ -> :ok
        end
      end)
      
      :ok
    end
    
    # Private functions
    
    defp establish_connection(conn_id, state) do
      retry_count = Map.get(state.retry_counts, conn_id, 0)
      backoff = calculate_backoff(retry_count)
      
      case connect_with_retry(state.connection_opts) do
        {:ok, connection} ->
          case Channel.open(connection) do
            {:ok, channel} ->
              # Setup topology for this channel
              Topology.declare_topology(channel)
              
              Logger.info("AMQP connection #{conn_id} established successfully")
              
              # Clear circuit breaker if it was open
              CircuitBreaker.success(:amqp_connection)
              
              %{state |
                connections: Map.put(state.connections, conn_id, connection),
                channels: Map.put(state.channels, conn_id, channel),
                health_status: Map.put(state.health_status, conn_id, true),
                retry_counts: Map.put(state.retry_counts, conn_id, 0),
                backoff_times: Map.delete(state.backoff_times, conn_id)
              }
              
            {:error, reason} ->
              Logger.error("Failed to open channel for connection #{conn_id}: #{inspect(reason)}")
              Connection.close(connection)
              schedule_retry(conn_id, state, backoff)
          end
          
        {:error, reason} ->
          Logger.error("Failed to establish connection #{conn_id}: #{inspect(reason)}")
          
          # Notify circuit breaker of failure
          CircuitBreaker.failure(:amqp_connection)
          
          schedule_retry(conn_id, state, backoff)
      end
    end
    
    defp connect_with_retry(opts) do
      case CircuitBreaker.call(:amqp_connection, fn -> Connection.open(opts) end) do
        {:ok, _} = result -> result
        {:error, :circuit_open} -> {:error, :circuit_breaker_open}
        error -> error
      end
    end
    
    defp schedule_retry(conn_id, state, backoff) do
      Process.send_after(self(), {:retry_connection, conn_id}, backoff)
      
      %{state |
        health_status: Map.put(state.health_status, conn_id, false),
        retry_counts: Map.update(state.retry_counts, conn_id, 1, &(&1 + 1)),
        backoff_times: Map.put(state.backoff_times, conn_id, backoff)
      }
    end
    
    defp calculate_backoff(retry_count) do
      backoff = @initial_backoff * :math.pow(2, retry_count)
      min(round(backoff), @max_backoff)
    end
    
    defp get_healthy_channel(state) do
      healthy_channels = state.channels
        |> Enum.filter(fn {conn_id, _} -> 
          Map.get(state.health_status, conn_id, false)
        end)
        |> Enum.map(fn {_, channel} -> channel end)
      
      case healthy_channels do
        [] -> 
          {:error, :no_healthy_connections}
        channels ->
          # Simple round-robin selection
          channel = Enum.random(channels)
          {:ok, channel}
      end
    end
    
    defp perform_health_check(state) do
      Enum.reduce(state.connections, state, fn {conn_id, conn}, acc ->
        if Connection.alive?(conn) do
          acc
        else
          Logger.warning("Connection #{conn_id} is not alive, marking as unhealthy")
          
          # Mark as unhealthy and schedule reconnection
          acc = %{acc | health_status: Map.put(acc.health_status, conn_id, false)}
          
          # Try to close the dead connection
          try do
            Connection.close(conn)
          catch
            _, _ -> :ok
          end
          
          # Remove from active connections
          acc = %{acc |
            connections: Map.delete(acc.connections, conn_id),
            channels: Map.delete(acc.channels, conn_id)
          }
          
          # Schedule immediate reconnection attempt
          send(self(), {:retry_connection, conn_id})
          
          acc
        end
      end)
    end
    
    # Public API
    
    @doc """
    Gets a healthy channel from the pool.
    """
    def get_channel do
      GenServer.call(__MODULE__, :get_channel)
    end
    
    @doc """
    Returns the health status of all connections in the pool.
    """
    def health_status do
      GenServer.call(__MODULE__, :health_status)
    end
  end
else
  # Stub implementation when AMQP is not available
  defmodule AutonomousOpponentV2Core.AMCP.ConnectionPool do
    @moduledoc """
    Stub implementation of AMCP ConnectionPool when AMQP is not available.
    """
    use GenServer
    require Logger
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    @impl true
    def init(_opts) do
      Logger.warning("AMQP ConnectionPool running in stub mode - AMQP not available")
      {:ok, %{}}
    end
    
    @impl true
    def handle_call(:get_channel, _from, state) do
      {:reply, {:error, :amqp_not_available}, state}
    end
    
    @impl true
    def handle_call(:health_status, _from, state) do
      status = %{
        total_connections: 0,
        healthy_connections: 0,
        connection_details: %{},
        error: :amqp_not_available
      }
      {:reply, status, state}
    end
    
    def get_channel do
      GenServer.call(__MODULE__, :get_channel)
    end
    
    def health_status do
      GenServer.call(__MODULE__, :health_status)
    end
  end
end