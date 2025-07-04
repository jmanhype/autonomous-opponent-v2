# This module is conditionally compiled based on AMQP availability
if Code.ensure_loaded?(AMQP) do
  defmodule AutonomousOpponentV2Core.AMCP.HealthMonitor do
    @moduledoc """
    Monitors AMQP connection health, publishes metrics to EventBus,
    and integrates with the system's health check infrastructure.
    
    **Wisdom Preservation:** Proactive health monitoring enables early
    detection of issues, allowing the system to adapt before failures
    cascade. Publishing health events enables system-wide awareness.
    """
    use GenServer
    require Logger
    
    alias AutonomousOpponentV2Core.AMCP.ConnectionPool
    alias AutonomousOpponentV2Core.EventBus
    
    @check_interval 5_000
    @unhealthy_threshold 0.5  # Less than 50% healthy connections triggers alert
    
    defmodule State do
      @moduledoc false
      defstruct [
        check_interval: @check_interval,
        last_status: nil,
        consecutive_failures: 0,
        algedonic_triggered: false
      ]
    end
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    @impl true
    def init(opts) do
      check_interval = Keyword.get(opts, :check_interval, @check_interval)
      
      state = %State{
        check_interval: check_interval
      }
      
      # Schedule first health check
      Process.send_after(self(), :perform_check, 1_000)
      
      # Subscribe to EventBus for system health requests
      EventBus.subscribe(:health_check_request)
      
      {:ok, state}
    end
    
    @impl true
    def handle_info(:perform_check, state) do
      state = perform_health_check(state)
      
      # Schedule next check
      Process.send_after(self(), :perform_check, state.check_interval)
      
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:event, :health_check_request, _data}, state) do
      # Respond to system-wide health check request
      health_data = get_current_health()
      
      EventBus.publish(:health_check_response, %{
        component: :amqp,
        status: health_data.status,
        details: health_data
      })
      
      {:noreply, state}
    end
    
    @impl true
    def handle_call(:get_health, _from, state) do
      health_data = get_current_health()
      {:reply, health_data, state}
    end
    
    # Private functions
    
    defp perform_health_check(state) do
      health_data = get_current_health()
      
      # Determine if status changed
      status_changed = state.last_status != health_data.status
      
      # Update consecutive failures
      consecutive_failures = if health_data.status == :unhealthy do
        state.consecutive_failures + 1
      else
        0
      end
      
      # Publish health event if status changed or still unhealthy
      if status_changed or health_data.status == :unhealthy do
        EventBus.publish(:amqp_health_changed, health_data)
        
        Logger.info("AMQP health status: #{health_data.status}, " <>
                   "healthy: #{health_data.healthy_connections}/#{health_data.total_connections}")
      end
      
      # Trigger algedonic signal if unhealthy for too long
      algedonic_triggered = if consecutive_failures >= 3 and not state.algedonic_triggered do
        trigger_algedonic_signal(health_data)
        true
      else
        state.algedonic_triggered
      end
      
      # Reset algedonic trigger when healthy
      algedonic_triggered = if health_data.status == :healthy do
        false
      else
        algedonic_triggered
      end
      
      %{state |
        last_status: health_data.status,
        consecutive_failures: consecutive_failures,
        algedonic_triggered: algedonic_triggered
      }
    end
    
    defp get_current_health do
      pool_status = ConnectionPool.health_status()
      
      health_percentage = if pool_status.total_connections > 0 do
        pool_status.healthy_connections / pool_status.total_connections
      else
        0.0
      end
      
      status = cond do
        pool_status.total_connections == 0 -> :critical
        health_percentage < @unhealthy_threshold -> :unhealthy
        health_percentage < 1.0 -> :degraded
        true -> :healthy
      end
      
      %{
        status: status,
        healthy_connections: pool_status.healthy_connections,
        total_connections: pool_status.total_connections,
        health_percentage: health_percentage,
        connection_details: pool_status.connection_details,
        timestamp: DateTime.utc_now()
      }
    end
    
    defp trigger_algedonic_signal(health_data) do
      Logger.error("AMQP health critical - triggering algedonic signal")
      
      EventBus.publish(:algedonic_signal, %{
        source: :amqp_health_monitor,
        severity: :high,
        message: "AMQP connectivity severely degraded",
        details: health_data,
        recommended_action: :escalate_to_s3
      })
    end
    
    # Public API
    
    @doc """
    Gets the current health status of AMQP connections.
    """
    def get_health do
      GenServer.call(__MODULE__, :get_health)
    end
    
    @doc """
    Checks if AMQP is currently healthy.
    """
    def healthy? do
      case get_health() do
        %{status: :healthy} -> true
        %{status: :degraded} -> true
        _ -> false
      end
    end
  end
else
  # Stub implementation when AMQP is not available
  defmodule AutonomousOpponentV2Core.AMCP.HealthMonitor do
    @moduledoc """
    Stub implementation of AMCP HealthMonitor when AMQP is not available.
    """
    use GenServer
    require Logger
    
    alias AutonomousOpponentV2Core.EventBus
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    @impl true
    def init(_opts) do
      Logger.warning("AMQP HealthMonitor running in stub mode - AMQP not available")
      
      # Subscribe to health check requests
      EventBus.subscribe(:health_check_request)
      
      {:ok, %{}}
    end
    
    @impl true
    def handle_info({:event, :health_check_request, _data}, state) do
      EventBus.publish(:health_check_response, %{
        component: :amqp,
        status: :unavailable,
        details: %{error: :amqp_not_available}
      })
      
      {:noreply, state}
    end
    
    @impl true
    def handle_call(:get_health, _from, state) do
      health_data = %{
        status: :unavailable,
        healthy_connections: 0,
        total_connections: 0,
        health_percentage: 0.0,
        error: :amqp_not_available,
        timestamp: DateTime.utc_now()
      }
      {:reply, health_data, state}
    end
    
    def get_health do
      GenServer.call(__MODULE__, :get_health)
    end
    
    def healthy? do
      false
    end
  end
end