defmodule AutonomousOpponentV2Core.MCPGateway.HealthMonitor do
  @moduledoc """
  Health monitoring for MCP Gateway components.
  
  Monitors:
  - Transport health (HTTP+SSE, WebSocket connections)
  - Connection pool status
  - Router performance
  - Backend availability
  
  ## Wisdom Preservation
  
  ### Why Health Monitoring?
  A gateway is only as reliable as its weakest component. Health monitoring
  provides early warning of degradation before total failure. It's the
  immune system that detects and responds to disease.
  
  ### Monitoring Philosophy
  1. **Proactive, not Reactive**: Check health regularly, don't wait for failures
  2. **Holistic View**: Monitor all layers - transport, routing, backends
  3. **Actionable Alerts**: Health checks should trigger automatic remediation
  """
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Core.Metrics
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCPGateway.{ConnectionPool, Router, TransportRegistry}
  
  # Health status
  @type health_status :: :healthy | :degraded | :unhealthy
  
  # Client API
  
  def start_link(opts) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Get current health status
  """
  def status(name \\ __MODULE__) do
    GenServer.call(name, :status)
  end
  
  @doc """
  Perform immediate health check
  """
  def check_now(name \\ __MODULE__) do
    GenServer.call(name, :check_now)
  end
  
  @doc """
  Register a custom health check
  """
  def register_check(name \\ __MODULE__, check_name, check_fun) do
    GenServer.call(name, {:register_check, check_name, check_fun})
  end
  
  # Server implementation
  
  defstruct [
    :check_interval,
    :unhealthy_threshold,
    :healthy_threshold,
    checks: %{},
    results: %{},
    status_history: [],
    overall_status: :healthy
  ]
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      check_interval: opts[:check_interval] || 5_000,
      unhealthy_threshold: opts[:unhealthy_threshold] || 3,
      healthy_threshold: opts[:healthy_threshold] || 2,
      checks: init_default_checks(),
      results: %{},
      status_history: [],
      overall_status: :healthy
    }
    
    # Schedule first health check
    Process.send_after(self(), :run_checks, 1_000)
    
    EventBus.publish(:mcp_health_monitor_started, %{
      check_interval: state.check_interval
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      overall: state.overall_status,
      components: format_component_status(state),
      last_check: get_last_check_time(state),
      history: Enum.take(state.status_history, 10)
    }
    
    {:reply, status, state}
  end
  
  def handle_call(:check_now, _from, state) do
    state = run_all_checks(state)
    {:reply, state.overall_status, state}
  end
  
  def handle_call({:register_check, check_name, check_fun}, _from, state) do
    checks = Map.put(state.checks, check_name, check_fun)
    {:reply, :ok, %{state | checks: checks}}
  end
  
  @impl true
  def handle_info(:run_checks, state) do
    state = run_all_checks(state)
    
    # Schedule next check
    Process.send_after(self(), :run_checks, state.check_interval)
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp init_default_checks do
    %{
      connection_pool: &check_connection_pool/0,
      router: &check_router/0,
      transport_registry: &check_transport_registry/0,
      memory: &check_memory_usage/0,
      cpu: &check_cpu_usage/0
    }
  end
  
  defp run_all_checks(state) do
    # Run each health check
    results = 
      state.checks
      |> Enum.map(fn {name, check_fun} ->
        result = run_single_check(name, check_fun)
        {name, result}
      end)
      |> Map.new()
    
    # Calculate overall status
    overall_status = calculate_overall_status(results, state)
    
    # Update history
    history_entry = %{
      timestamp: System.monotonic_time(:millisecond),
      status: overall_status,
      results: results
    }
    
    history = [history_entry | state.status_history] |> Enum.take(100)
    
    # Emit events if status changed
    if overall_status != state.overall_status do
      emit_status_change(state.overall_status, overall_status)
    end
    
    # Record metrics
    record_health_metrics(results, overall_status)
    
    %{state | 
      results: results,
      overall_status: overall_status,
      status_history: history
    }
  end
  
  defp run_single_check(name, check_fun) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      case check_fun.() do
        :ok -> 
          %{status: :healthy, latency: System.monotonic_time(:millisecond) - start_time}
          
        {:ok, details} ->
          %{
            status: :healthy,
            latency: System.monotonic_time(:millisecond) - start_time,
            details: details
          }
          
        {:degraded, reason} ->
          %{
            status: :degraded,
            latency: System.monotonic_time(:millisecond) - start_time,
            reason: reason
          }
          
        {:error, reason} ->
          %{
            status: :unhealthy,
            latency: System.monotonic_time(:millisecond) - start_time,
            error: reason
          }
      end
    rescue
      e ->
        Logger.error("Health check #{name} failed: #{inspect(e)}")
        %{
          status: :unhealthy,
          latency: System.monotonic_time(:millisecond) - start_time,
          error: :check_failed,
          exception: inspect(e)
        }
    end
  end
  
  defp check_connection_pool do
    case ConnectionPool.status() do
      %{total_connections: total, waiting_queue_size: waiting} ->
        cond do
          waiting > 10 ->
            {:degraded, "High waiting queue: #{waiting}"}
            
          total == 0 ->
            {:error, "No connections available"}
            
          true ->
            {:ok, %{connections: total, waiting: waiting}}
        end
        
      _ ->
        {:error, "Unable to get pool status"}
    end
  end
  
  defp check_router do
    case Router.status() do
      %{active_routes: active, total_routes: total} when active > 0 ->
        health_percentage = (active / total) * 100
        
        cond do
          health_percentage < 50 ->
            {:error, "Only #{health_percentage}% routes healthy"}
            
          health_percentage < 80 ->
            {:degraded, "#{health_percentage}% routes healthy"}
            
          true ->
            {:ok, %{healthy_routes: active, total_routes: total}}
        end
        
      _ ->
        {:error, "No active routes"}
    end
  end
  
  defp check_transport_registry do
    case TransportRegistry.status() do
      %{registered_transports: transports} when length(transports) > 0 ->
        {:ok, %{transports: transports}}
        
      _ ->
        {:error, "No transports registered"}
    end
  end
  
  defp check_memory_usage do
    # Get memory usage
    memory = :erlang.memory()
    total = memory[:total]
    used_percentage = (memory[:processes] / total) * 100
    
    cond do
      used_percentage > 90 ->
        {:error, "Memory usage critical: #{used_percentage}%"}
        
      used_percentage > 75 ->
        {:degraded, "Memory usage high: #{used_percentage}%"}
        
      true ->
        {:ok, %{memory_used_percentage: used_percentage}}
    end
  end
  
  defp check_cpu_usage do
    # Simplified CPU check using scheduler utilization
    utilization = :scheduler.utilization(1)
    avg_utilization = 
      utilization
      |> Enum.map(fn {_, util, _} -> util end)
      |> Enum.sum()
      |> Kernel./(length(utilization))
      |> Kernel.*(100)
    
    cond do
      avg_utilization > 90 ->
        {:error, "CPU usage critical: #{avg_utilization}%"}
        
      avg_utilization > 75 ->
        {:degraded, "CPU usage high: #{avg_utilization}%"}
        
      true ->
        {:ok, %{cpu_utilization: avg_utilization}}
    end
  end
  
  defp calculate_overall_status(results, state) do
    # Count statuses
    status_counts = 
      results
      |> Map.values()
      |> Enum.reduce(%{healthy: 0, degraded: 0, unhealthy: 0}, fn result, acc ->
        Map.update(acc, result.status, 1, &(&1 + 1))
      end)
    
    # Apply thresholds
    cond do
      status_counts.unhealthy >= state.unhealthy_threshold ->
        :unhealthy
        
      status_counts.degraded >= state.unhealthy_threshold ->
        :degraded
        
      status_counts.healthy >= state.healthy_threshold ->
        :healthy
        
      true ->
        :degraded
    end
  end
  
  defp emit_status_change(old_status, new_status) do
    event = case {old_status, new_status} do
      {:healthy, :degraded} -> :mcp_health_degraded
      {:healthy, :unhealthy} -> :mcp_health_failed
      {:degraded, :unhealthy} -> :mcp_health_failed
      {:degraded, :healthy} -> :mcp_health_recovered
      {:unhealthy, :healthy} -> :mcp_health_recovered
      {:unhealthy, :degraded} -> :mcp_health_improving
      _ -> nil
    end
    
    if event do
      EventBus.publish(event, %{
        old_status: old_status,
        new_status: new_status,
        timestamp: System.monotonic_time(:millisecond)
      })
      
      # Log status change
      Logger.info("MCP Gateway health changed: #{old_status} -> #{new_status}")
    end
  end
  
  defp record_health_metrics(results, overall_status) do
    # Record overall status as gauge
    status_value = case overall_status do
      :healthy -> 2
      :degraded -> 1
      :unhealthy -> 0
    end
    
    Metrics.gauge(:mcp_gateway_metrics, "health.overall", status_value)
    
    # Record individual component statuses
    Enum.each(results, fn {component, result} ->
      component_value = case result.status do
        :healthy -> 2
        :degraded -> 1
        :unhealthy -> 0
      end
      
      Metrics.gauge(:mcp_gateway_metrics, "health.component", component_value, %{
        component: component
      })
      
      # Record check latency
      if result[:latency] do
        Metrics.histogram(:mcp_gateway_metrics, "health.check_duration", result.latency, %{
          component: component
        })
      end
    end)
  end
  
  defp format_component_status(state) do
    state.results
    |> Enum.map(fn {component, result} ->
      {component, %{
        status: result.status,
        details: Map.get(result, :details, Map.get(result, :reason, Map.get(result, :error)))
      }}
    end)
    |> Map.new()
  end
  
  defp get_last_check_time(state) do
    case state.status_history do
      [%{timestamp: ts} | _] -> ts
      _ -> nil
    end
  end
end