defmodule AutonomousOpponentV2Web.MetricsDashboardLive do
  @moduledoc """
  Real-time metrics dashboard for VSM subsystem monitoring.
  Displays system health, variety flow, algedonic balance, and alerts.
  """
  use AutonomousOpponentV2Web, :live_view
  
  
  @refresh_interval 1000 # Update every second
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time updates
      AutonomousOpponentV2Core.EventBus.subscribe(:metrics_updated)
      AutonomousOpponentV2Core.EventBus.subscribe(:alert_triggered)
      
      # Schedule periodic refresh
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end
    
    socket = 
      socket
      |> assign(:dashboard_data, fetch_dashboard_data())
      |> assign(:alerts, [])
      |> assign(:prometheus_endpoint, "/metrics")
    
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="metrics-dashboard">
      <h1 class="text-3xl font-bold mb-6">VSM Metrics Dashboard</h1>
      
      <!-- System Health Overview -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div class="bg-white rounded-lg shadow p-6" id="system-health">
          <h2 class="text-xl font-semibold mb-2">System Health</h2>
          <div class={health_class(@dashboard_data.system_health)}>
            <%= format_health(@dashboard_data.system_health) %>
          </div>
        </div>
        
        <div class="bg-white rounded-lg shadow p-6" id="algedonic-balance">
          <h2 class="text-xl font-semibold mb-2">Algedonic Balance</h2>
          <div class={algedonic_class(@dashboard_data.algedonic_balance)}>
            <%= @dashboard_data.algedonic_balance %>
          </div>
          <div class="text-sm text-gray-600 mt-1">
            <%= algedonic_description(@dashboard_data.algedonic_balance) %>
          </div>
        </div>
        
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-2">Active Alerts</h2>
          <div class="text-2xl font-bold text-red-600">
            <%= length(@alerts) %>
          </div>
        </div>
      </div>
      
      <!-- VSM Subsystems -->
      <div class="bg-white rounded-lg shadow p-6 mb-6">
        <h2 class="text-xl font-semibold mb-4">VSM Subsystems</h2>
        <div class="grid grid-cols-5 gap-4">
          <%= for {subsystem, data} <- @dashboard_data.subsystems do %>
            <div class="text-center">
              <h3 class="font-semibold"><%= format_subsystem(subsystem) %></h3>
              <div class="text-2xl font-bold mt-2">
                <%= data.health_score %>%
              </div>
              <div class="text-sm text-gray-600">
                <%= data.metrics_count %> metrics
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Variety Flow -->
      <div class="bg-white rounded-lg shadow p-6 mb-6">
        <h2 class="text-xl font-semibold mb-4">Variety Flow (Ashby's Law)</h2>
        <div class="grid grid-cols-3 gap-4">
          <div>
            <h3 class="font-semibold">Absorbed</h3>
            <div class="text-2xl font-bold text-blue-600">
              <%= @dashboard_data.variety_flow.total_absorbed %>
            </div>
          </div>
          <div>
            <h3 class="font-semibold">Generated</h3>
            <div class="text-2xl font-bold text-green-600">
              <%= @dashboard_data.variety_flow.total_generated %>
            </div>
          </div>
          <div>
            <h3 class="font-semibold">Attenuation</h3>
            <div class="text-2xl font-bold text-purple-600">
              <%= format_float(@dashboard_data.variety_flow.avg_attenuation) %>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Cybernetic Loops -->
      <div class="bg-white rounded-lg shadow p-6 mb-6">
        <h2 class="text-xl font-semibold mb-4">Cybernetic Control Loops</h2>
        <div class="grid grid-cols-3 gap-4">
          <div>
            <h3 class="font-semibold">Active Loops</h3>
            <div class="text-2xl font-bold">
              <%= @dashboard_data.cybernetic_loops.feedback_loops_active %>
            </div>
          </div>
          <div>
            <h3 class="font-semibold">Avg Latency</h3>
            <div class="text-2xl font-bold">
              <%= @dashboard_data.cybernetic_loops.avg_loop_latency_ms %>ms
            </div>
          </div>
          <div>
            <h3 class="font-semibold">Effectiveness</h3>
            <div class="text-2xl font-bold">
              <%= format_percentage(@dashboard_data.cybernetic_loops.control_effectiveness) %>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Active Alerts -->
      <%= if length(@alerts) > 0 do %>
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4 text-red-600">Active Alerts</h2>
          <div class="space-y-2">
            <%= for alert <- @alerts do %>
              <div class={alert_class(alert.severity)}>
                <div class="font-semibold"><%= alert.alert %></div>
                <div class="text-sm"><%= alert.message %></div>
                <div class="text-xs text-gray-600">
                  Value: <%= alert.value %> (threshold: <%= alert.threshold %>)
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
      
      <!-- Export Links -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-xl font-semibold mb-4">Export & Integration</h2>
        <div class="space-y-2">
          <div>
            <a href={@prometheus_endpoint} target="_blank" 
               class="text-blue-600 hover:underline">
              Prometheus Metrics Endpoint
            </a>
            <span class="text-sm text-gray-600 ml-2">
              (for Grafana/Prometheus integration)
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  @impl true
  def handle_info(:refresh, socket) do
    socket = 
      socket
      |> assign(:dashboard_data, fetch_dashboard_data())
      |> assign(:alerts, fetch_alerts())
    
    {:noreply, socket}
  end
  
  def handle_info({:event, :metrics_updated, _data}, socket) do
    # Real-time update triggered by metrics change
    socket = assign(socket, :dashboard_data, fetch_dashboard_data())
    {:noreply, socket}
  end
  
  def handle_info({:event, :alert_triggered, alert}, socket) do
    # Add new alert to the list
    alerts = [alert | socket.assigns.alerts] |> Enum.take(10)
    {:noreply, assign(socket, :alerts, alerts)}
  end
  
  # Private functions
  
  defp fetch_dashboard_data do
    case Process.whereis(AutonomousOpponentV2Core.Core.Metrics) do
      nil -> default_dashboard_data()
      _pid -> 
        try do
          AutonomousOpponentV2Core.Core.Metrics.get_vsm_dashboard(AutonomousOpponentV2Core.Core.Metrics)
        rescue
          _ -> default_dashboard_data()
        end
    end
  end
  
  defp fetch_alerts do
    case Process.whereis(AutonomousOpponentV2Core.Core.Metrics) do
      nil -> []
      _pid ->
        try do
          AutonomousOpponentV2Core.Core.Metrics.check_alerts(AutonomousOpponentV2Core.Core.Metrics)
        rescue
          _ -> []
        end
    end
  end
  
  defp default_dashboard_data do
    %{
      subsystems: %{
        s1: %{metrics_count: 0, health_score: 0},
        s2: %{metrics_count: 0, health_score: 0},
        s3: %{metrics_count: 0, health_score: 0},
        s4: %{metrics_count: 0, health_score: 0},
        s5: %{metrics_count: 0, health_score: 0}
      },
      variety_flow: %{
        total_absorbed: 0,
        total_generated: 0,
        avg_attenuation: 0
      },
      algedonic_balance: 0,
      cybernetic_loops: %{
        feedback_loops_active: 0,
        avg_loop_latency_ms: 0,
        control_effectiveness: 0
      },
      system_health: :unknown
    }
  end
  
  defp health_class(:excellent), do: "text-3xl font-bold text-green-600"
  defp health_class(:good), do: "text-3xl font-bold text-green-500"
  defp health_class(:fair), do: "text-3xl font-bold text-yellow-500"
  defp health_class(:poor), do: "text-3xl font-bold text-red-600"
  defp health_class(_), do: "text-3xl font-bold text-gray-600"
  
  defp format_health(:excellent), do: "Excellent"
  defp format_health(:good), do: "Good"
  defp format_health(:fair), do: "Fair"
  defp format_health(:poor), do: "Poor"
  defp format_health(_), do: "Unknown"
  
  defp algedonic_class(balance) when balance > 10, do: "text-3xl font-bold text-green-600"
  defp algedonic_class(balance) when balance > 0, do: "text-3xl font-bold text-green-500"
  defp algedonic_class(balance) when balance > -10, do: "text-3xl font-bold text-yellow-500"
  defp algedonic_class(_), do: "text-3xl font-bold text-red-600"
  
  defp algedonic_description(balance) when balance > 10, do: "System experiencing pleasure"
  defp algedonic_description(balance) when balance > 0, do: "Positive balance"
  defp algedonic_description(balance) when balance > -10, do: "Mild discomfort"
  defp algedonic_description(_), do: "System experiencing pain"
  
  defp alert_class(:critical), do: "p-3 bg-red-100 border border-red-400 rounded"
  defp alert_class(:error), do: "p-3 bg-orange-100 border border-orange-400 rounded"
  defp alert_class(:warning), do: "p-3 bg-yellow-100 border border-yellow-400 rounded"
  defp alert_class(_), do: "p-3 bg-blue-100 border border-blue-400 rounded"
  
  defp format_subsystem(:s1), do: "S1 - Operations"
  defp format_subsystem(:s2), do: "S2 - Coordination"
  defp format_subsystem(:s3), do: "S3 - Control"
  defp format_subsystem(:s4), do: "S4 - Intelligence"
  defp format_subsystem(:s5), do: "S5 - Policy"
  defp format_subsystem(s), do: to_string(s)
  
  defp format_float(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_float(value), do: "#{value}"
  
  defp format_percentage(value) when is_float(value), do: "#{round(value * 100)}%"
  defp format_percentage(value), do: "#{value}%"
end