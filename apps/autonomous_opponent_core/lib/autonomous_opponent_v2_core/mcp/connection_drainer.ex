defmodule AutonomousOpponentV2Core.MCP.ConnectionDrainer do
  @moduledoc """
  Handles graceful shutdown of MCP Gateway connections during deployments.
  
  Features:
  - Notifies clients of impending shutdown
  - Stops accepting new connections
  - Waits for existing connections to close
  - Configurable drain timeout
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCP.Transport.{HTTPSSE, WebSocket}
  
  @default_drain_timeout 30_000  # 30 seconds
  @notification_interval 5_000   # Notify every 5 seconds during drain
  
  defmodule State do
    @moduledoc false
    defstruct [
      :drain_timeout,
      :drain_started_at,
      :accepting_connections,
      :draining,
      :notification_timer,
      :completion_callback
    ]
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Initiates graceful connection draining.
  
  Options:
  - timeout: Maximum time to wait for connections to close (default: 30s)
  - callback: Function to call when draining is complete
  """
  def start_draining(opts \\ []) do
    GenServer.call(__MODULE__, {:start_draining, opts})
  end
  
  @doc """
  Checks if the system is currently draining connections.
  """
  def draining? do
    GenServer.call(__MODULE__, :draining?)
  end
  
  @doc """
  Checks if the system is accepting new connections.
  """
  def accepting_connections? do
    GenServer.call(__MODULE__, :accepting_connections?)
  end
  
  @doc """
  Forces immediate shutdown without waiting for connections to close.
  """
  def force_shutdown do
    GenServer.cast(__MODULE__, :force_shutdown)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    drain_timeout = Keyword.get(opts, :drain_timeout, @default_drain_timeout)
    
    state = %State{
      drain_timeout: drain_timeout,
      accepting_connections: true,
      draining: false,
      notification_timer: nil,
      completion_callback: nil
    }
    
    # Subscribe to connection events
    EventBus.subscribe(:mcp_connection_closed)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_draining, opts}, _from, state) do
    if state.draining do
      {:reply, {:error, :already_draining}, state}
    else
      timeout = Keyword.get(opts, :timeout, state.drain_timeout)
      callback = Keyword.get(opts, :callback)
      
      Logger.info("Starting connection draining with timeout: #{timeout}ms")
      
      # Stop accepting new connections
      stop_accepting_connections()
      
      # Notify all connected clients
      notify_all_clients(:shutdown_pending, %{
        message: "Server is shutting down for maintenance",
        reconnect_after: timeout + 10_000  # Give extra time before reconnecting
      })
      
      # Start notification timer
      timer = Process.send_after(self(), :send_notification, @notification_interval)
      
      # Schedule timeout
      Process.send_after(self(), :drain_timeout, timeout)
      
      new_state = %{state |
        draining: true,
        accepting_connections: false,
        drain_started_at: DateTime.utc_now(),
        notification_timer: timer,
        completion_callback: callback
      }
      
      # Report to VSM
      EventBus.publish(:vsm_s3_control, %{
        event: :connection_draining_started,
        timeout: timeout
      })
      
      {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call(:draining?, _from, state) do
    {:reply, state.draining, state}
  end
  
  @impl true
  def handle_call(:accepting_connections?, _from, state) do
    {:reply, state.accepting_connections, state}
  end
  
  @impl true
  def handle_cast(:force_shutdown, state) do
    Logger.warning("Forcing immediate shutdown")
    
    # Close all connections immediately
    close_all_connections()
    
    # Cancel timers
    if state.notification_timer, do: Process.cancel_timer(state.notification_timer)
    
    # Run callback if set
    if state.completion_callback do
      state.completion_callback.(:forced)
    end
    
    new_state = %{state |
      draining: false,
      accepting_connections: false,
      notification_timer: nil
    }
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:send_notification, state) do
    if state.draining do
      # Calculate time remaining
      elapsed = DateTime.diff(DateTime.utc_now(), state.drain_started_at, :millisecond)
      remaining = max(0, state.drain_timeout - elapsed)
      
      # Notify clients of time remaining
      notify_all_clients(:shutdown_countdown, %{
        message: "Server shutdown in progress",
        time_remaining_ms: remaining
      })
      
      # Check if all connections are closed
      if all_connections_closed?() do
        Logger.info("All connections closed, completing drain")
        complete_draining(state, :success)
      else
        # Schedule next notification
        timer = Process.send_after(self(), :send_notification, @notification_interval)
        {:noreply, %{state | notification_timer: timer}}
      end
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:drain_timeout, state) do
    if state.draining do
      Logger.warning("Drain timeout reached, forcing closure of remaining connections")
      
      # Get count of remaining connections
      remaining = count_active_connections()
      Logger.info("Closing #{remaining} remaining connections")
      
      # Force close remaining connections
      close_all_connections()
      
      complete_draining(state, :timeout)
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event_bus, :mcp_connection_closed, _data}, state) do
    if state.draining && all_connections_closed?() do
      Logger.info("Last connection closed during drain")
      complete_draining(state, :success)
    else
      {:noreply, state}
    end
  end
  
  # Private functions
  
  defp stop_accepting_connections do
    # Update registry to reject new connections
    Registry.update_value(
      AutonomousOpponentV2Core.MCP.ConfigRegistry,
      :accepting_connections,
      fn _ -> false end
    )
    
    # Notify transports
    HTTPSSE.stop_accepting_connections()
    WebSocket.stop_accepting_connections()
    
    Logger.info("Stopped accepting new connections")
  end
  
  defp notify_all_clients(event_type, data) do
    # Notify via WebSocket
    Phoenix.PubSub.broadcast(
      AutonomousOpponentV2.PubSub,
      "mcp:all",
      {:system_notification, event_type, data}
    )
    
    # Notify via SSE
    Registry.dispatch(
      AutonomousOpponentV2Core.MCP.TransportRegistry,
      {:transport, :http_sse},
      fn entries ->
        for {pid, _} <- entries do
          send(pid, {:send_event, event_type, data})
        end
      end
    )
  end
  
  defp all_connections_closed? do
    count_active_connections() == 0
  end
  
  defp count_active_connections do
    websocket_count = Registry.count(
      AutonomousOpponentV2Core.MCP.TransportRegistry,
      {:transport, :websocket}
    )
    
    sse_count = Registry.count(
      AutonomousOpponentV2Core.MCP.TransportRegistry,
      {:transport, :http_sse}
    )
    
    websocket_count + sse_count
  end
  
  defp close_all_connections do
    # Close WebSocket connections
    Registry.dispatch(
      AutonomousOpponentV2Core.MCP.TransportRegistry,
      {:transport, :websocket},
      fn entries ->
        for {pid, _} <- entries do
          send(pid, :close_connection)
        end
      end
    )
    
    # Close SSE connections
    Registry.dispatch(
      AutonomousOpponentV2Core.MCP.TransportRegistry,
      {:transport, :http_sse},
      fn entries ->
        for {pid, _} <- entries do
          send(pid, :close_connection)
        end
      end
    )
  end
  
  defp complete_draining(state, reason) do
    # Cancel notification timer
    if state.notification_timer do
      Process.cancel_timer(state.notification_timer)
    end
    
    # Report to VSM
    EventBus.publish(:vsm_s3_control, %{
      event: :connection_draining_complete,
      reason: reason,
      duration_ms: DateTime.diff(DateTime.utc_now(), state.drain_started_at, :millisecond)
    })
    
    # Run callback if set
    if state.completion_callback do
      state.completion_callback.(reason)
    end
    
    # Allow connections again (for rolling deployments)
    Registry.update_value(
      AutonomousOpponentV2Core.MCP.ConfigRegistry,
      :accepting_connections,
      fn _ -> true end
    )
    
    Logger.info("Connection draining complete: #{reason}")
    
    new_state = %{state |
      draining: false,
      accepting_connections: true,
      drain_started_at: nil,
      notification_timer: nil,
      completion_callback: nil
    }
    
    {:noreply, new_state}
  end
end