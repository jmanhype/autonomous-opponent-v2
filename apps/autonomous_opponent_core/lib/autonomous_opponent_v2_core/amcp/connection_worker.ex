defmodule AutonomousOpponentV2Core.AMCP.ConnectionWorker do
  @moduledoc """
  Worker process that maintains a single AMQP connection and channel.
  Handles connection lifecycle, heartbeats, and automatic reconnection.
  
  **Wisdom Preservation:** Each worker maintains its own connection to provide
  isolation and prevent cascading failures. The worker monitors the connection
  and automatically reconnects when necessary.
  """
  use GenServer
  require Logger

  @reconnect_interval 5000
  @heartbeat_interval 30

  defmodule State do
    @moduledoc false
    defstruct [:connection, :channel, :monitor_ref, :reconnect_timer]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    # Start connection process asynchronously to avoid blocking supervisor
    send(self(), :connect)
    {:ok, %State{}}
  end

  @impl true
  def handle_info(:connect, state) do
    state = close_existing_connection(state)
    
    case establish_connection() do
      {:ok, connection, channel} ->
        monitor_ref = Process.monitor(connection.pid)
        
        new_state = %State{
          connection: connection,
          channel: channel,
          monitor_ref: monitor_ref,
          reconnect_timer: nil
        }
        
        Logger.info("AMQP connection established successfully")
        {:noreply, new_state}
      
      {:error, reason} ->
        Logger.error("Failed to establish AMQP connection: #{inspect(reason)}")
        timer = Process.send_after(self(), :connect, @reconnect_interval)
        {:noreply, %State{reconnect_timer: timer}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{monitor_ref: ref} = state) do
    Logger.warning("AMQP connection lost: #{inspect(reason)}. Reconnecting...")
    send(self(), :connect)
    {:noreply, %State{state | connection: nil, channel: nil, monitor_ref: nil}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_channel, _from, %State{channel: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call(:get_channel, _from, %State{channel: channel} = state) do
    if channel_alive?(channel) do
      {:reply, {:ok, channel}, state}
    else
      Logger.warning("Channel is dead, reconnecting...")
      send(self(), :connect)
      {:reply, {:error, :channel_closed}, %State{state | channel: nil}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    close_existing_connection(state)
    :ok
  end

  defp establish_connection do
    if amqp_available?() do
      connection_opts = build_connection_options()
      
      case safe_connection_open(connection_opts) do
        {:ok, connection} ->
          case safe_channel_open(connection) do
            {:ok, channel} ->
              # Configure channel for better reliability
              configure_channel(channel)
              {:ok, connection, channel}
            
            {:error, reason} ->
              safe_connection_close(connection)
              {:error, {:channel_error, reason}}
          end
        
        {:error, reason} ->
          {:error, {:connection_error, reason}}
      end
    else
      Logger.warning("AMQP not available, running in stub mode")
      {:ok, :stub_connection, :stub_channel}
    end
  end

  defp build_connection_options do
    base_opts = Application.get_env(:autonomous_opponent_core, :amqp_connection, [])
    
    # Add/override critical connection parameters
    Keyword.merge(base_opts, [
      heartbeat: @heartbeat_interval,
      connection_timeout: 10_000,
      # For network recovery
      automatically_recover: false,  # We handle recovery ourselves
      # TCP keepalive settings
      socket_options: [
        keepalive: true,
        nodelay: true
      ]
    ])
  end

  defp configure_channel(channel) do
    if amqp_available?() and channel != :stub_channel do
      try do
        # Set QoS to prevent overwhelming consumers
        AMQP.Basic.qos(channel, prefetch_count: 10)
        
        # Set up confirms for reliable publishing
        if function_exported?(AMQP.Confirm, :select, 1) do
          AMQP.Confirm.select(channel)
        end
      rescue
        e ->
          Logger.warning("Failed to configure channel: #{inspect(e)}")
      end
    end
  end

  defp channel_alive?(channel) do
    case channel do
      :stub_channel -> true
      _ -> 
        # Check if channel process is alive
        is_pid(channel.pid) and Process.alive?(channel.pid)
    end
  rescue
    _ -> false
  end

  defp close_existing_connection(%State{connection: nil} = state), do: state
  
  defp close_existing_connection(%State{connection: :stub_connection} = state) do
    %State{state | connection: nil, channel: nil}
  end
  
  defp close_existing_connection(%State{connection: conn, monitor_ref: ref} = state) do
    if ref, do: Process.demonitor(ref, [:flush])
    safe_connection_close(conn)
    %State{state | connection: nil, channel: nil, monitor_ref: nil}
  end

  defp amqp_available? do
    Code.ensure_loaded?(AMQP) and function_exported?(AMQP.Connection, :open, 1)
  end

  # Safe wrappers for AMQP operations that handle both real and stub modes
  defp safe_connection_open(opts) do
    if amqp_available?() do
      try do
        AMQP.Connection.open(opts)
      rescue
        e -> {:error, e}
      end
    else
      {:ok, :stub_connection}
    end
  end

  defp safe_channel_open(connection) do
    case connection do
      :stub_connection -> 
        {:ok, :stub_channel}
      
      conn ->
        try do
          AMQP.Channel.open(conn)
        rescue
          e -> {:error, e}
        end
    end
  end

  defp safe_connection_close(connection) do
    case connection do
      :stub_connection -> :ok
      conn ->
        try do
          AMQP.Connection.close(conn)
        rescue
          _ -> :ok
        end
    end
  end
end