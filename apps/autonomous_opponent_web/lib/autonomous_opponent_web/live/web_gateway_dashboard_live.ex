defmodule AutonomousOpponentWeb.WebGatewayDashboardLive do
  @moduledoc """
  LiveView dashboard for monitoring Web Gateway metrics in real-time.
  
  Displays:
  - Connection counts by transport type
  - Message throughput graphs
  - Circuit breaker status
  - VSM integration metrics
  """
  use AutonomousOpponentV2Web, :live_view
  alias AutonomousOpponentV2Core.WebGateway.Gateway

  @refresh_interval 1000  # Update every second
  @history_size 60        # Keep 60 seconds of history

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to gateway events
      Phoenix.PubSub.subscribe(AutonomousOpponentV2.PubSub, "mcp:metrics")
      
      # Schedule periodic updates
      :timer.send_interval(@refresh_interval, self(), :refresh_metrics)
    end
    
    socket =
      socket
      |> assign(:connections, %{websocket: 0, http_sse: 0, total: 0})
      |> assign(:throughput, %{current: 0, history: []})
      |> assign(:circuit_breakers, %{websocket: :closed, http_sse: :closed})
      |> assign(:vsm_metrics, %{
        s1_variety_absorption: 0,
        s2_coordination_active: false,
        s3_resource_usage: 0,
        s4_intelligence_events: 0,
        s5_policy_violations: 0,
        algedonic_signals: []
      })
      |> assign(:error_rates, %{websocket: 0, http_sse: 0})
      |> assign(:pool_status, %{available: 0, in_use: 0, overflow: 0})
      |> fetch_initial_metrics()
    
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mcp-dashboard">
      <h1 class="text-3xl font-bold mb-6">Web Gateway Dashboard</h1>
      
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <!-- Connection Counts -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">Active Connections</h2>
          <div class="space-y-3">
            <div class="flex justify-between items-center">
              <span class="text-gray-600">WebSocket</span>
              <span class="text-2xl font-bold text-blue-600"><%= @connections.websocket %></span>
            </div>
            <div class="flex justify-between items-center">
              <span class="text-gray-600">HTTP/SSE</span>
              <span class="text-2xl font-bold text-green-600"><%= @connections.http_sse %></span>
            </div>
            <hr />
            <div class="flex justify-between items-center">
              <span class="text-gray-800 font-semibold">Total</span>
              <span class="text-3xl font-bold"><%= @connections.total %></span>
            </div>
          </div>
        </div>
        
        <!-- Message Throughput -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">Message Throughput</h2>
          <div class="mb-4">
            <span class="text-3xl font-bold"><%= @throughput.current %></span>
            <span class="text-gray-600">msg/s</span>
          </div>
          <div class="h-32">
            <svg viewBox="0 0 300 100" class="w-full h-full">
              <polyline
                fill="none"
                stroke="#3B82F6"
                stroke-width="2"
                points={throughput_points(@throughput.history)}
              />
            </svg>
          </div>
        </div>
        
        <!-- Circuit Breakers -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">Circuit Breakers</h2>
          <div class="space-y-3">
            <div class="flex items-center justify-between">
              <span class="text-gray-600">WebSocket</span>
              <span class={circuit_breaker_class(@circuit_breakers.websocket)}>
                <%= String.upcase(to_string(@circuit_breakers.websocket)) %>
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-gray-600">HTTP/SSE</span>
              <span class={circuit_breaker_class(@circuit_breakers.http_sse)}>
                <%= String.upcase(to_string(@circuit_breakers.http_sse)) %>
              </span>
            </div>
          </div>
        </div>
        
        <!-- Connection Pool Status -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">Connection Pool</h2>
          <div class="space-y-3">
            <div class="flex justify-between">
              <span class="text-gray-600">Available</span>
              <span class="font-semibold text-green-600"><%= @pool_status.available %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-600">In Use</span>
              <span class="font-semibold text-blue-600"><%= @pool_status.in_use %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-600">Overflow</span>
              <span class="font-semibold text-orange-600"><%= @pool_status.overflow %></span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-2.5 mt-2">
              <div class="bg-blue-600 h-2.5 rounded-full" style={"width: #{pool_usage_percentage(@pool_status)}%"}></div>
            </div>
          </div>
        </div>
        
        <!-- VSM Integration Metrics -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">VSM Integration</h2>
          <div class="space-y-2 text-sm">
            <div class="flex justify-between">
              <span class="text-gray-600">S1 Variety Absorption</span>
              <span class="font-semibold"><%= @vsm_metrics.s1_variety_absorption %>/s</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-600">S2 Coordination</span>
              <span class={vsm_status_class(@vsm_metrics.s2_coordination_active)}>
                <%= if @vsm_metrics.s2_coordination_active, do: "ACTIVE", else: "IDLE" %>
              </span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-600">S3 Resource Usage</span>
              <span class="font-semibold"><%= @vsm_metrics.s3_resource_usage %>%</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-600">S4 Intelligence Events</span>
              <span class="font-semibold"><%= @vsm_metrics.s4_intelligence_events %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-600">S5 Policy Violations</span>
              <span class={policy_violation_class(@vsm_metrics.s5_policy_violations)}>
                <%= @vsm_metrics.s5_policy_violations %>
              </span>
            </div>
          </div>
        </div>
        
        <!-- Error Rates -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">Error Rates</h2>
          <div class="space-y-3">
            <div class="flex justify-between items-center">
              <span class="text-gray-600">WebSocket Errors</span>
              <span class={error_rate_class(@error_rates.websocket)}>
                <%= Float.round(@error_rates.websocket, 2) %>%
              </span>
            </div>
            <div class="flex justify-between items-center">
              <span class="text-gray-600">HTTP/SSE Errors</span>
              <span class={error_rate_class(@error_rates.http_sse)}>
                <%= Float.round(@error_rates.http_sse, 2) %>%
              </span>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Algedonic Signals -->
      <%= if length(@vsm_metrics.algedonic_signals) > 0 do %>
        <div class="mt-6 bg-red-50 border border-red-200 rounded-lg p-4">
          <h3 class="text-lg font-semibold text-red-800 mb-2">Algedonic Signals</h3>
          <div class="space-y-2">
            <%= for signal <- @vsm_metrics.algedonic_signals do %>
              <div class="flex items-center text-sm">
                <span class={algedonic_severity_class(signal.severity)}><%= signal.severity %></span>
                <span class="ml-2 text-gray-700"><%= signal.message %></span>
                <span class="ml-auto text-gray-500"><%= format_time(signal.timestamp) %></span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
      
      <!-- Refresh Info -->
      <div class="mt-6 text-center text-sm text-gray-500">
        Auto-refreshing every <%= @refresh_interval %>ms
      </div>
    </div>
    """
  end

  @impl true
  def handle_info(:refresh_metrics, socket) do
    {:noreply, fetch_metrics(socket)}
  end

  @impl true
  def handle_info({:mcp_metrics_update, metrics}, socket) do
    {:noreply, update_metrics(socket, metrics)}
  end

  defp fetch_initial_metrics(socket) do
    # Fetch initial metrics from Gateway
    case Gateway.get_dashboard_metrics() do
      {:ok, metrics} ->
        update_metrics(socket, metrics)
      _ ->
        socket
    end
  end

  defp fetch_metrics(socket) do
    # Fetch current metrics
    case Gateway.get_dashboard_metrics() do
      {:ok, metrics} ->
        update_metrics(socket, metrics)
      _ ->
        socket
    end
  end

  defp update_metrics(socket, metrics) do
    # Update throughput history
    current_throughput = metrics[:throughput] || 0
    history = Enum.take([current_throughput | socket.assigns.throughput.history], @history_size)
    
    socket
    |> assign(:connections, metrics[:connections] || socket.assigns.connections)
    |> assign(:throughput, %{current: current_throughput, history: history})
    |> assign(:circuit_breakers, metrics[:circuit_breakers] || socket.assigns.circuit_breakers)
    |> assign(:vsm_metrics, metrics[:vsm_metrics] || socket.assigns.vsm_metrics)
    |> assign(:error_rates, metrics[:error_rates] || socket.assigns.error_rates)
    |> assign(:pool_status, metrics[:pool_status] || socket.assigns.pool_status)
  end

  defp throughput_points(history) do
    if Enum.empty?(history) do
      ""
    else
      max_value = Enum.max([1 | history])
      width = 300
      height = 100
      
      history
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.map(fn {value, index} ->
        x = index * (width / @history_size)
        y = height - (value / max_value * height)
        "#{x},#{y}"
      end)
      |> Enum.join(" ")
    end
  end

  defp circuit_breaker_class(:open), do: "px-2 py-1 bg-green-100 text-green-800 rounded font-semibold"
  defp circuit_breaker_class(:half_open), do: "px-2 py-1 bg-yellow-100 text-yellow-800 rounded font-semibold"
  defp circuit_breaker_class(:closed), do: "px-2 py-1 bg-red-100 text-red-800 rounded font-semibold"

  defp vsm_status_class(true), do: "text-green-600 font-semibold"
  defp vsm_status_class(false), do: "text-gray-600"

  defp policy_violation_class(0), do: "text-green-600 font-semibold"
  defp policy_violation_class(n) when n < 5, do: "text-yellow-600 font-semibold"
  defp policy_violation_class(_), do: "text-red-600 font-semibold"

  defp error_rate_class(rate) when rate < 1.0, do: "text-green-600 font-semibold"
  defp error_rate_class(rate) when rate < 5.0, do: "text-yellow-600 font-semibold"
  defp error_rate_class(_), do: "text-red-600 font-semibold"

  defp algedonic_severity_class(:critical), do: "px-2 py-1 bg-red-600 text-white rounded text-xs font-bold"
  defp algedonic_severity_class(:high), do: "px-2 py-1 bg-red-500 text-white rounded text-xs font-bold"
  defp algedonic_severity_class(:medium), do: "px-2 py-1 bg-orange-500 text-white rounded text-xs font-bold"
  defp algedonic_severity_class(:low), do: "px-2 py-1 bg-yellow-500 text-white rounded text-xs font-bold"

  defp pool_usage_percentage(%{available: a, in_use: u, overflow: _o}) do
    total = a + u
    if total == 0 do
      0
    else
      round(u / total * 100)
    end
  end

  defp format_time(timestamp) do
    case timestamp do
      %DateTime{} = dt ->
        Calendar.strftime(dt, "%H:%M:%S")
      _ ->
        "N/A"
    end
  end
end