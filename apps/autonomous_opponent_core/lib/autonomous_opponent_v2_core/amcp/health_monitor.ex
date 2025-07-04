defmodule AutonomousOpponentV2Core.AMCP.HealthMonitor do
  @moduledoc """
  Monitors the health of AMQP connections and infrastructure.
  
  Provides real-time health metrics, alerts on connection issues,
  and integrates with the VSM algedonic system for pain signals.
  
  **Wisdom Preservation:** Health monitoring is not just about detecting
  failures, but predicting them. By tracking metrics over time, we can
  identify degradation patterns before they become critical failures.
  """
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.AMCP.{ConnectionPool, Topology}
  alias AutonomousOpponentV2Core.EventBus
  
  @check_interval 30_000  # 30 seconds
  @unhealthy_threshold 3  # Number of failed checks before marking unhealthy
  
  defmodule State do
    @moduledoc false
    defstruct [
      :timer_ref,
      :consecutive_failures,
      :last_check_result,
      :metrics_history,
      :status
    ]
  end
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Schedule first health check
    timer_ref = Process.send_after(self(), :check_health, 1000)
    
    state = %State{
      timer_ref: timer_ref,
      consecutive_failures: 0,
      metrics_history: [],
      status: :initializing
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_info(:check_health, state) do
    # Cancel old timer if exists
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    
    # Perform health check
    check_result = perform_health_check()
    
    # Update state based on result
    new_state = process_health_check(check_result, state)
    
    # Schedule next check
    timer_ref = Process.send_after(self(), :check_health, @check_interval)
    
    {:noreply, %{new_state | timer_ref: timer_ref}}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      status: state.status,
      last_check: state.last_check_result,
      consecutive_failures: state.consecutive_failures,
      history: Enum.take(state.metrics_history, 10)
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call(:force_check, _from, state) do
    check_result = perform_health_check()
    new_state = process_health_check(check_result, state)
    {:reply, check_result, new_state}
  end
  
  defp perform_health_check do
    timestamp = DateTime.utc_now()
    
    # Check connection pool health
    pool_health = ConnectionPool.health_check()
    
    # Test message publishing
    publish_test = test_message_publishing()
    
    # Check queue depths (would need RabbitMQ management API in production)
    queue_status = check_queue_status()
    
    # Calculate overall health score
    health_score = calculate_health_score(pool_health, publish_test, queue_status)
    
    %{
      timestamp: timestamp,
      pool_health: pool_health,
      publish_test: publish_test,
      queue_status: queue_status,
      health_score: health_score,
      healthy: health_score > 0.7
    }
  end
  
  defp test_message_publishing do
    test_message = %{
      type: "health_check",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      node: node()
    }
    
    case ConnectionPool.publish_with_retry("vsm.events", "health.check", test_message) do
      :ok -> %{status: :ok, latency: 0}  # Would measure actual latency in production
      {:error, reason} -> %{status: :error, reason: reason}
    end
  rescue
    e -> %{status: :error, reason: inspect(e)}
  end
  
  defp check_queue_status do
    # In production, this would query RabbitMQ management API
    # For now, return a placeholder
    %{
      status: :unknown,
      message: "Queue depth monitoring not implemented"
    }
  end
  
  defp calculate_health_score(pool_health, publish_test, _queue_status) do
    scores = []
    
    # Pool health contributes 50%
    pool_score = if pool_health[:healthy], do: 0.5, else: 0.0
    scores = [pool_score | scores]
    
    # Publishing capability contributes 40%
    publish_score = if publish_test[:status] == :ok, do: 0.4, else: 0.0
    scores = [publish_score | scores]
    
    # Queue status contributes 10% (not implemented yet)
    queue_score = 0.1
    scores = [queue_score | scores]
    
    Enum.sum(scores)
  end
  
  defp process_health_check(check_result, state) do
    # Update metrics history (keep last 100 entries)
    metrics_history = [check_result | state.metrics_history] |> Enum.take(100)
    
    # Update failure count and status
    {consecutive_failures, status} = if check_result.healthy do
      # Reset failures on successful check
      {0, :healthy}
    else
      failures = state.consecutive_failures + 1
      
      # Determine status based on failure count
      status = cond do
        failures >= @unhealthy_threshold -> :critical
        failures > 0 -> :degraded
        true -> :healthy
      end
      
      # Send algedonic pain signal if critical
      if status == :critical and state.status != :critical do
        send_pain_signal(check_result)
      end
      
      {failures, status}
    end
    
    # Publish health event
    EventBus.publish(:amqp_health_check, %{
      status: status,
      check_result: check_result,
      consecutive_failures: consecutive_failures
    })
    
    %State{
      state |
      last_check_result: check_result,
      metrics_history: metrics_history,
      consecutive_failures: consecutive_failures,
      status: status
    }
  end
  
  defp send_pain_signal(check_result) do
    Logger.error("AMQP infrastructure critical - sending pain signal")
    
    pain_message = %{
      source: "amqp_health_monitor",
      severity: "critical",
      message: "AMQP connection pool is unhealthy",
      details: check_result,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    # Try to send via AMQP if possible
    ConnectionPool.with_connection(fn channel ->
      Topology.publish_algedonic(channel, :pain, pain_message)
    end)
    
    # Always send via EventBus as backup
    EventBus.publish(:algedonic_pain, pain_message)
  end
  
  @doc """
  Gets the current health status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end
  
  @doc """
  Forces an immediate health check.
  """
  def force_check do
    GenServer.call(__MODULE__, :force_check)
  end
  
  @doc """
  Returns a simplified health indicator for use in health endpoints.
  """
  def health_indicator do
    case get_status() do
      %{status: :healthy} -> :ok
      %{status: :degraded} -> :degraded
      _ -> :unhealthy
    end
  rescue
    _ -> :unknown
  end
end