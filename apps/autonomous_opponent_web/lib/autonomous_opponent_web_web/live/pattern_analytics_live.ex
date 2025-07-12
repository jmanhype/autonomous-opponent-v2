defmodule AutonomousOpponentV2Web.PatternAnalyticsLive do
  @moduledoc """
  Pattern Analytics Dashboard - Issue #92
  
  Real-time visualization of:
  - Pattern detection from S4 Intelligence
  - Pattern correlations and causality chains
  - S3 control interventions
  - S5 policy adjustments
  - Algedonic alerts
  - System-wide pattern metrics
  
  Provides comprehensive monitoring for VSM pattern-based intelligence.
  """
  
  use AutonomousOpponentV2Web, :live_view
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S3S5PatternAlertSystem
  alias AutonomousOpponentV2Core.VSM.S4.PatternCorrelationAnalyzer
  alias Phoenix.PubSub
  
  @refresh_interval 1000  # 1 second
  @max_recent_patterns 50
  @max_active_alerts 20
  @chart_data_points 60  # 1 minute of data
  
  @impl true
  def mount(_params, _session, socket) do
    require Logger
    Logger.info("PatternAnalyticsLive mounting, connected: #{connected?(socket)}")
    
    if connected?(socket) do
      # Try to subscribe to pattern events if EventBus is available
      spawn(fn ->
        try do
          if Process.whereis(AutonomousOpponentV2Core.EventBus) do
            EventBus.subscribe(:pattern_detected)
            EventBus.subscribe(:temporal_pattern_detected)
            EventBus.subscribe(:pattern_causality_detected)
            EventBus.subscribe(:algedonic_correlation_detected)
            EventBus.subscribe(:s3_intervention_complete)
            EventBus.subscribe(:s5_policy_updated)
            EventBus.subscribe(:vsm_pattern_flow)
          end
        rescue
          _ -> :ok
        end
      end)
      
      # Subscribe to WebSocket pattern channel for real-time updates
      Phoenix.PubSub.subscribe(AutonomousOpponentV2Web.PubSub, "patterns:analytics")
      
      # Start refresh timer
      Process.send_after(self(), :refresh_metrics, @refresh_interval)
      
      # Demo pattern generation removed - real patterns only
    end
    
    # Start with empty data - real patterns only
    initial_patterns = []
    initial_alerts = []
    
    socket = socket
    |> assign(:page_title, "Pattern Analytics Dashboard")
    |> assign(:recent_patterns, initial_patterns)
    |> assign(:active_alerts, initial_alerts)
    |> assign(:pattern_metrics, calculate_initial_metrics(initial_patterns))
    |> assign(:correlation_data, %{})
    |> assign(:intervention_history, [])
    |> assign(:policy_adjustments, [])
    |> assign(:time_series_data, init_time_series())
    |> assign(:subsystem_stats, init_subsystem_stats())
    |> assign(:selected_pattern, nil)
    |> assign(:view_mode, :overview)
    
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-5 bg-gray-100 min-h-screen">
      <header class="flex justify-between items-center mb-5 p-5 bg-white rounded-lg shadow-md">
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          🧠 Pattern Analytics Dashboard
        </h1>
        <div class="flex gap-5">
          <span class="flex items-center gap-2 px-4 py-2 bg-gray-100 rounded-full">
            <span class="text-gray-600 text-sm">Patterns/min:</span>
            <span class="font-bold text-lg"><%= @pattern_metrics.patterns_per_minute %></span>
          </span>
          <span class="flex items-center gap-2 px-4 py-2 bg-gray-100 rounded-full">
            <span class="text-gray-600 text-sm">Active Alerts:</span>
            <span class={"font-bold text-lg #{alert_color_class(length(@active_alerts))}"}>
              <%= length(@active_alerts) %>
            </span>
          </span>
          <span class="flex items-center gap-2 px-4 py-2 bg-gray-100 rounded-full">
            <span class="text-gray-600 text-sm">Correlations:</span>
            <span class="font-bold text-lg"><%= @pattern_metrics.total_correlations %></span>
          </span>
        </div>
      </header>
      
      <div class="flex gap-2.5 mb-5">
        <button
          phx-click="set_view_mode"
          phx-value-mode="overview"
          class={"px-5 py-2.5 rounded cursor-pointer transition-all " <> if(@view_mode == :overview, do: "bg-indigo-600 text-white border-indigo-600", else: "bg-white border border-gray-300 hover:bg-gray-100")}
        >
          Overview
        </button>
        <button
          phx-click="set_view_mode"
          phx-value-mode="patterns"
          class={"px-5 py-2.5 rounded cursor-pointer transition-all " <> if(@view_mode == :patterns, do: "bg-indigo-600 text-white border-indigo-600", else: "bg-white border border-gray-300 hover:bg-gray-100")}
        >
          Patterns
        </button>
        <button
          phx-click="set_view_mode"
          phx-value-mode="correlations"
          class={"px-5 py-2.5 rounded cursor-pointer transition-all " <> if(@view_mode == :correlations, do: "bg-indigo-600 text-white border-indigo-600", else: "bg-white border border-gray-300 hover:bg-gray-100")}
        >
          Correlations
        </button>
        <button
          phx-click="set_view_mode"
          phx-value-mode="interventions"
          class={"px-5 py-2.5 rounded cursor-pointer transition-all " <> if(@view_mode == :interventions, do: "bg-indigo-600 text-white border-indigo-600", else: "bg-white border border-gray-300 hover:bg-gray-100")}
        >
          Interventions
        </button>
      </div>
      
      <div class="grid gap-5">
        <%= case @view_mode do %>
          <% :overview -> %>
            <%= render_overview(assigns) %>
          <% :patterns -> %>
            <%= render_patterns_view(assigns) %>
          <% :correlations -> %>
            <%= render_correlations_view(assigns) %>
          <% :interventions -> %>
            <%= render_interventions_view(assigns) %>
        <% end %>
      </div>
    </div>
    """
  end
  
  defp render_overview(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-5">
      <!-- Real-time Pattern Stream -->
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Real-time Pattern Stream</h2>
        <div class="space-y-2">
          <%= for pattern <- Enum.take(@recent_patterns, 10) do %>
            <div class="p-3 border-b last:border-b-0 flex justify-between items-center cursor-pointer hover:bg-gray-50" phx-click="select_pattern" phx-value-id={pattern.id}>
              <div>
                <div class="font-semibold text-gray-800"><%= format_pattern_type(pattern.type) %></div>
                <div class="text-sm text-gray-500"><%= format_timestamp(pattern.timestamp) %></div>
              </div>
              <div class="flex items-center gap-2">
                <span class={"px-2 py-1 rounded text-xs font-semibold text-white " <> confidence_bg_class(pattern.confidence)}>
                  <%= round(pattern.confidence * 100) %>%
                </span>
                <span class={"font-semibold " <> severity_color_class(pattern.severity)}>
                  <%= pattern.severity %>
                </span>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Active Alerts -->
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Active Alerts</h2>
        <div class="space-y-2">
          <%= if @active_alerts == [] do %>
            <p class="text-gray-500 text-center py-8">No active alerts</p>
          <% else %>
            <%= for alert <- @active_alerts do %>
              <div class="p-3 border-b last:border-b-0">
                <div class="flex justify-between items-center mb-2">
                  <span class="font-semibold"><%= alert.pattern_type || alert.type %></span>
                  <span class="text-sm text-gray-600"><%= alert[:routing] || alert.source %></span>
                </div>
                <div class="text-sm text-gray-500">
                  <span class={"font-semibold " <> severity_color_class(alert.severity)}>
                    <%= alert.severity %>
                  </span>
                  - <%= round(alert.confidence * 100) %>% confidence
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
      
      <!-- Pattern Metrics Chart -->
      <div class="col-span-2 bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Pattern Detection Rate</h2>
        <div class="h-72 relative bg-gray-100 rounded flex items-center justify-center">
          <p class="text-gray-500">Chart visualization coming soon</p>
        </div>
      </div>
      
      <!-- Subsystem Statistics -->
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">VSM Subsystem Patterns</h2>
        <div class="space-y-3">
          <%= for {subsystem, stats} <- @subsystem_stats do %>
            <div>
              <div class="flex justify-between mb-1">
                <span class="font-semibold"><%= format_subsystem(subsystem) %></span>
                <span class="text-lg"><%= stats.count %></span>
              </div>
              <div class="h-2 bg-gray-200 rounded">
                <div class="h-full bg-indigo-600 rounded" style={"width: #{stats.percentage}%"}></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Correlation Summary -->
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Pattern Correlations</h2>
        <div class="space-y-2">
          <div class="flex justify-between">
            <span class="text-gray-600">Total Correlations:</span>
            <span class="font-semibold"><%= @pattern_metrics.total_correlations %></span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-600">Causality Chains:</span>
            <span class="font-semibold"><%= @pattern_metrics.causality_chains %></span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-600">Avg Chain Length:</span>
            <span class="font-semibold"><%= @pattern_metrics.avg_chain_length %></span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-600">Algedonic Correlations:</span>
            <span class="font-semibold text-red-600"><%= @pattern_metrics.algedonic_correlations %></span>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  defp render_patterns_view(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-5">
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Pattern List</h2>
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead class="border-b">
              <tr>
                <th class="text-left py-2">ID</th>
                <th class="text-left py-2">Type</th>
                <th class="text-left py-2">Source</th>
                <th class="text-left py-2">Confidence</th>
                <th class="text-left py-2">Time</th>
                <th class="text-left py-2">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for pattern <- @recent_patterns do %>
                <tr class="border-b hover:bg-gray-50 cursor-pointer" phx-click="select_pattern" phx-value-id={pattern.id}>
                  <td class="py-2 text-sm font-mono"><%= String.slice(pattern.id, 0..7) %></td>
                  <td class="py-2"><%= format_pattern_type(pattern.type) %></td>
                  <td class="py-2"><%= pattern.source %></td>
                  <td class="py-2">
                    <span class={"px-2 py-1 rounded text-xs font-semibold text-white " <> confidence_bg_class(pattern.confidence)}>
                      <%= round(pattern.confidence * 100) %>%
                    </span>
                  </td>
                  <td class="py-2 text-sm"><%= format_timestamp(pattern.timestamp) %></td>
                  <td class="py-2">
                    <button class="px-3 py-1 bg-indigo-600 text-white text-xs rounded hover:bg-indigo-700">
                      View
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
      
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Pattern Details</h2>
        <%= if @selected_pattern do %>
          <div class="space-y-3">
            <div class="grid grid-cols-2 gap-2">
              <span class="font-semibold text-gray-600">Pattern ID:</span>
              <span class="font-mono text-sm bg-gray-100 p-2 rounded overflow-x-auto"><%= @selected_pattern.id %></span>
            </div>
            <div class="grid grid-cols-2 gap-2">
              <span class="font-semibold text-gray-600">Type:</span>
              <span><%= format_pattern_type(@selected_pattern.type) %></span>
            </div>
            <div class="grid grid-cols-2 gap-2">
              <span class="font-semibold text-gray-600">Source:</span>
              <span><%= @selected_pattern.source %></span>
            </div>
            <div class="grid grid-cols-2 gap-2">
              <span class="font-semibold text-gray-600">Confidence:</span>
              <span><%= round(@selected_pattern.confidence * 100) %>%</span>
            </div>
            <div class="grid grid-cols-2 gap-2">
              <span class="font-semibold text-gray-600">Severity:</span>
              <span class={"font-semibold " <> severity_color_class(@selected_pattern.severity)}>
                <%= @selected_pattern.severity %>
              </span>
            </div>
            <div class="grid grid-cols-2 gap-2">
              <span class="font-semibold text-gray-600">Data:</span>
              <div class="font-mono text-sm bg-gray-100 p-2 rounded overflow-x-auto">
                <%= inspect(@selected_pattern.data, pretty: true) %>
              </div>
            </div>
          </div>
        <% else %>
          <p class="text-gray-500 text-center py-8">Select a pattern to view details</p>
        <% end %>
      </div>
    </div>
    """
  end
  
  defp render_correlations_view(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Pattern Correlation Analysis</h2>
        <div class="h-96 bg-gray-100 rounded flex items-center justify-center text-gray-500">
          Correlation network visualization would appear here
        </div>
      </div>
      
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Causality Chains</h2>
        <div class="space-y-4">
          <%= for chain <- get_causality_chains(@correlation_data) do %>
            <div class="p-4 border rounded">
              <div class="flex justify-between mb-2">
                <span class="font-semibold">Chain Length: <%= length(chain.patterns) %></span>
                <span class="text-sm"><%= round(chain.confidence * 100) %>%</span>
              </div>
              <div class="flex items-center gap-2 overflow-x-auto">
                <%= for {pattern, index} <- Enum.with_index(chain.patterns) do %>
                  <div class="min-w-32 p-2 bg-gray-100 rounded text-center">
                    <div class="font-semibold text-sm"><%= pattern.type %></div>
                    <div class="text-xs text-gray-500"><%= format_relative_time(pattern.timestamp) %></div>
                  </div>
                  <%= if index < length(chain.patterns) - 1 do %>
                    <span class="text-gray-400">→</span>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Correlation Metrics</h2>
        <div class="grid grid-cols-3 gap-4">
          <div class="text-center">
            <h3 class="font-semibold mb-2">Weak Correlations</h3>
            <div class="h-32 bg-gray-200 rounded relative">
              <div class="absolute bottom-0 w-full bg-yellow-400 rounded" style="height: 20%"></div>
            </div>
            <p class="mt-2 text-sm text-gray-600">&lt;0.3</p>
          </div>
          <div class="text-center">
            <h3 class="font-semibold mb-2">Medium Correlations</h3>
            <div class="h-32 bg-gray-200 rounded relative">
              <div class="absolute bottom-0 w-full bg-orange-400 rounded" style="height: 45%"></div>
            </div>
            <p class="mt-2 text-sm text-gray-600">0.3-0.7</p>
          </div>
          <div class="text-center">
            <h3 class="font-semibold mb-2">Strong Correlations</h3>
            <div class="h-32 bg-gray-200 rounded relative">
              <div class="absolute bottom-0 w-full bg-green-500 rounded" style="height: 80%"></div>
            </div>
            <p class="mt-2 text-sm text-gray-600">&gt;0.7</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  defp render_interventions_view(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Intervention History</h2>
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead class="border-b">
              <tr>
                <th class="text-left py-2">Time</th>
                <th class="text-left py-2">Subsystem</th>
                <th class="text-left py-2">Pattern Type</th>
                <th class="text-left py-2">Action</th>
                <th class="text-left py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              <%= for intervention <- @intervention_history do %>
                <tr class="border-b">
                  <td class="py-2 text-sm"><%= format_timestamp(intervention.timestamp) %></td>
                  <td class="py-2"><%= intervention.subsystem %></td>
                  <td class="py-2"><%= intervention.pattern_type %></td>
                  <td class="py-2 text-sm"><%= intervention.action %></td>
                  <td class="py-2">
                    <span class={"font-semibold " <> if(intervention.success, do: "text-green-600", else: "text-red-600")}>
                      <%= if intervention.success, do: "Success", else: "Failed" %>
                    </span>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
      
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Policy Adjustments</h2>
        <div class="space-y-3">
          <%= for adjustment <- @policy_adjustments do %>
            <div class="p-4 border rounded">
              <div class="flex justify-between mb-2">
                <span class="font-semibold"><%= adjustment.policy_name %></span>
                <span class="text-sm text-gray-500"><%= format_timestamp(adjustment.timestamp) %></span>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <p class="text-sm text-gray-600 mb-1">Previous Value:</p>
                  <p class="font-mono text-sm bg-gray-100 p-2 rounded"><%= adjustment.old_value %></p>
                </div>
                <div>
                  <p class="text-sm text-gray-600 mb-1">New Value:</p>
                  <p class="font-mono text-sm bg-gray-100 p-2 rounded"><%= adjustment.new_value %></p>
                </div>
              </div>
              <p class="text-sm text-gray-600 mt-2">Reason: <%= adjustment.reason %></p>
            </div>
          <% end %>
        </div>
      </div>
      
      <div class="bg-white rounded-lg p-5 shadow-md">
        <h2 class="text-xl font-semibold mb-4">Intervention Effectiveness</h2>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <h3 class="font-semibold mb-2">Success Rate by Subsystem</h3>
            <div class="space-y-2">
              <div class="flex justify-between">
                <span>S1 Operations:</span>
                <span class="font-semibold text-green-600">85%</span>
              </div>
              <div class="flex justify-between">
                <span>S2 Coordination:</span>
                <span class="font-semibold text-green-600">92%</span>
              </div>
              <div class="flex justify-between">
                <span>S3 Control:</span>
                <span class="font-semibold text-yellow-600">78%</span>
              </div>
              <div class="flex justify-between">
                <span>S4 Intelligence:</span>
                <span class="font-semibold text-green-600">95%</span>
              </div>
              <div class="flex justify-between">
                <span>S5 Policy:</span>
                <span class="font-semibold text-green-600">88%</span>
              </div>
            </div>
          </div>
          <div>
            <h3 class="font-semibold mb-2">Response Time Distribution</h3>
            <div class="space-y-2">
              <div class="flex justify-between">
                <span>&lt; 100ms:</span>
                <span class="font-semibold">65%</span>
              </div>
              <div class="flex justify-between">
                <span>100-500ms:</span>
                <span class="font-semibold">25%</span>
              </div>
              <div class="flex justify-between">
                <span>500ms-1s:</span>
                <span class="font-semibold">8%</span>
              </div>
              <div class="flex justify-between">
                <span>&gt; 1s:</span>
                <span class="font-semibold">2%</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  # Event Handlers
  
  @impl true
  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, String.to_atom(mode))}
  end
  
  @impl true
  def handle_event("select_pattern", %{"id" => pattern_id}, socket) do
    pattern = Enum.find(socket.assigns.recent_patterns, &(&1.id == pattern_id))
    {:noreply, assign(socket, :selected_pattern, pattern)}
  end
  
  @impl true
  def handle_info({:event, :pattern_detected, pattern_data}, socket) do
    socket = update_pattern_list(socket, pattern_data)
    |> update_pattern_metrics()
    |> update_time_series_data()
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, event}, socket) do
    # Handle HLC-formatted events from EventBus
    case event.type do
      :pattern_detected ->
        handle_info({:event, :pattern_detected, event.data}, socket)
      :temporal_pattern_detected ->
        handle_info({:event, :temporal_pattern_detected, event.data}, socket)
      :pattern_causality_detected ->
        handle_info({:event, :pattern_causality_detected, event.data}, socket)
      :algedonic_correlation_detected ->
        handle_info({:event, :algedonic_correlation_detected, event.data}, socket)
      :s3_intervention_complete ->
        handle_info({:event, :s3_intervention_complete, event.data}, socket)
      :s5_policy_updated ->
        handle_info({:event, :s5_policy_updated, event.data}, socket)
      _ ->
        {:noreply, socket}
    end
  end
  
  @impl true
  def handle_info({:event, :temporal_pattern_detected, pattern_data}, socket) do
    socket = update_pattern_list(socket, pattern_data)
    |> update_correlation_data(pattern_data)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :pattern_causality_detected, causality_data}, socket) do
    socket = update_correlation_data(socket, causality_data)
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :algedonic_correlation_detected, alert_data}, socket) do
    socket = add_active_alert(socket, alert_data)
    |> update_pattern_metrics()
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :s3_intervention_complete, intervention_data}, socket) do
    socket = add_intervention_history(socket, intervention_data)
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :s5_policy_updated, policy_data}, socket) do
    socket = add_policy_adjustment(socket, policy_data)
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(:refresh_metrics, socket) do
    # Schedule next refresh
    Process.send_after(self(), :refresh_metrics, @refresh_interval)
    
    # Update subsystem stats
    socket = update_subsystem_stats(socket)
    
    # Push chart data to client
    push_event(socket, "update_chart", %{
      data: Enum.map(socket.assigns.time_series_data, fn {time, value} ->
        %{time: time, value: value}
      end)
    })
    
    {:noreply, socket}
  end
  
  # Demo pattern generation removed - dashboard shows real patterns only
  
  @impl true
  def handle_info({:event_bus_hlc, event}, socket) do
    # Handle HLC-formatted events from EventBus
    case event.type do
      :pattern_detected ->
        handle_info({:event, :pattern_detected, event.data}, socket)
      :temporal_pattern_detected ->
        handle_info({:event, :temporal_pattern_detected, event.data}, socket)
      :pattern_causality_detected ->
        handle_info({:event, :pattern_causality_detected, event.data}, socket)
      :algedonic_correlation_detected ->
        handle_info({:event, :algedonic_correlation_detected, event.data}, socket)
      :s3_intervention_complete ->
        handle_info({:event, :s3_intervention_complete, event.data}, socket)
      :s5_policy_updated ->
        handle_info({:event, :s5_policy_updated, event.data}, socket)
      _ ->
        {:noreply, socket}
    end
  end
  
  @impl true
  def handle_info(_msg, socket) do
    # Catch-all for any unhandled messages
    {:noreply, socket}
  end
  
  # Private Functions
  
  defp init_pattern_metrics do
    %{
      patterns_per_minute: 0,
      total_patterns: 0,
      total_correlations: 0,
      causality_chains: 0,
      avg_chain_length: 0.0,
      algedonic_correlations: 0
    }
  end
  
  defp init_time_series do
    # Initialize with zeros for the last minute
    now = System.system_time(:second)
    for i <- 0..(@chart_data_points - 1) do
      {now - (@chart_data_points - i), 0}
    end
  end
  
  defp init_subsystem_stats do
    %{
      s1: %{count: 0, percentage: 0},
      s2: %{count: 0, percentage: 0},
      s3: %{count: 0, percentage: 0},
      s4: %{count: 0, percentage: 0},
      s5: %{count: 0, percentage: 0}
    }
  end
  
  defp update_pattern_list(socket, pattern_data) do
    patterns = [pattern_data | socket.assigns.recent_patterns]
    |> Enum.take(@max_recent_patterns)
    
    assign(socket, :recent_patterns, patterns)
  end
  
  defp update_pattern_metrics(socket) do
    metrics = socket.assigns.pattern_metrics
    |> Map.update!(:total_patterns, &(&1 + 1))
    |> Map.put(:patterns_per_minute, calculate_patterns_per_minute(socket.assigns.recent_patterns))
    
    assign(socket, :pattern_metrics, metrics)
  end
  
  defp update_time_series_data(socket) do
    now = System.system_time(:second)
    
    # Add new data point
    time_series = socket.assigns.time_series_data
    |> Enum.take(@chart_data_points - 1)
    |> then(&([{now, socket.assigns.pattern_metrics.patterns_per_minute} | &1]))
    
    assign(socket, :time_series_data, time_series)
  end
  
  defp update_correlation_data(socket, correlation_data) do
    # Update correlation metrics
    metrics = socket.assigns.pattern_metrics
    |> Map.update!(:total_correlations, &(&1 + 1))
    
    socket
    |> assign(:pattern_metrics, metrics)
    |> assign(:correlation_data, Map.merge(socket.assigns.correlation_data, correlation_data))
  end
  
  defp update_subsystem_stats(socket) do
    patterns = socket.assigns.recent_patterns
    total = length(patterns)
    
    stats = if total > 0 do
      patterns
      |> Enum.group_by(& &1.source)
      |> Enum.map(fn {subsystem, subsystem_patterns} ->
        count = length(subsystem_patterns)
        percentage = round(count / total * 100)
        {subsystem, %{count: count, percentage: percentage}}
      end)
      |> Enum.into(%{})
    else
      init_subsystem_stats()
    end
    
    assign(socket, :subsystem_stats, stats)
  end
  
  defp add_active_alert(socket, alert_data) do
    alerts = [alert_data | socket.assigns.active_alerts]
    |> Enum.take(@max_active_alerts)
    
    assign(socket, :active_alerts, alerts)
  end
  
  defp add_intervention_history(socket, intervention_data) do
    history = [intervention_data | socket.assigns.intervention_history]
    |> Enum.take(50)
    
    assign(socket, :intervention_history, history)
  end
  
  defp add_policy_adjustment(socket, policy_data) do
    adjustments = [policy_data | socket.assigns.policy_adjustments]
    |> Enum.take(20)
    
    assign(socket, :policy_adjustments, adjustments)
  end
  
  defp get_causality_chains(correlation_data) do
    # Extract causality chains from correlation data
    Map.get(correlation_data, :causality_chains, [])
  end
  
  defp calculate_patterns_per_minute(patterns) do
    now = DateTime.utc_now()
    minute_ago = DateTime.add(now, -60, :second)
    
    patterns
    |> Enum.filter(fn p -> DateTime.compare(p.timestamp, minute_ago) == :gt end)
    |> length()
  end
  
  # Helper Functions
  
  defp format_pattern_type(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  defp format_pattern_type(type), do: to_string(type)
  
  defp format_timestamp(timestamp) do
    case timestamp do
      %DateTime{} = dt ->
        Calendar.strftime(dt, "%H:%M:%S")
      _ ->
        "N/A"
    end
  end
  
  defp format_relative_time(timestamp) do
    case timestamp do
      %DateTime{} = dt ->
        diff = DateTime.diff(DateTime.utc_now(), dt, :second)
        cond do
          diff < 60 -> "#{diff}s ago"
          diff < 3600 -> "#{div(diff, 60)}m ago"
          true -> "#{div(diff, 3600)}h ago"
        end
      _ ->
        "N/A"
    end
  end
  
  defp format_subsystem(subsystem) do
    case subsystem do
      :s1 -> "S1 Operations"
      :s2 -> "S2 Coordination"
      :s3 -> "S3 Control"
      :s4 -> "S4 Intelligence"
      :s5 -> "S5 Policy"
      _ -> to_string(subsystem)
    end
  end
  
  defp alert_color_class(count) do
    cond do
      count == 0 -> "text-green-600"
      count < 5 -> "text-yellow-600"
      true -> "text-red-600"
    end
  end
  
  defp confidence_class(confidence) when confidence >= 0.8, do: "confidence-high"
  defp confidence_class(confidence) when confidence >= 0.5, do: "confidence-medium"
  defp confidence_class(_), do: "confidence-low"
  
  defp confidence_bg_class(confidence) when confidence >= 0.8, do: "bg-green-500"
  defp confidence_bg_class(confidence) when confidence >= 0.5, do: "bg-yellow-500"
  defp confidence_bg_class(_), do: "bg-red-500"
  
  defp severity_color_class(:critical), do: "text-red-600"
  defp severity_color_class(:high), do: "text-yellow-600"
  defp severity_color_class(:normal), do: "text-green-600"
  defp severity_color_class(_), do: "text-gray-600"
  
  # All demo generation functions removed - real patterns only
  
  defp calculate_initial_metrics(_patterns) do
    %{
      total_patterns: 0,
      patterns_per_minute: 0,
      avg_confidence: 0,
      total_correlations: 0,
      causality_chains: 0,
      avg_chain_length: 0,
      algedonic_correlations: 0,
      critical_patterns: 0,
      high_patterns: 0,
      normal_patterns: 0,
      avg_response_time_ms: 0
    }
  end
end
