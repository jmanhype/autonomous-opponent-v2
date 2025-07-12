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
    if connected?(socket) do
      # Subscribe to pattern events
      EventBus.subscribe(:pattern_detected)
      EventBus.subscribe(:temporal_pattern_detected)
      EventBus.subscribe(:pattern_causality_detected)
      EventBus.subscribe(:algedonic_correlation_detected)
      EventBus.subscribe(:s3_intervention_complete)
      EventBus.subscribe(:s5_policy_updated)
      EventBus.subscribe(:vsm_pattern_flow)
      
      # Subscribe to WebSocket pattern channel for real-time updates
      PubSub.subscribe(AutonomousOpponentV2.PubSub, "patterns:analytics")
      
      # Start refresh timer
      Process.send_after(self(), :refresh_metrics, @refresh_interval)
    end
    
    socket = socket
    |> assign(:page_title, "Pattern Analytics Dashboard")
    |> assign(:recent_patterns, [])
    |> assign(:active_alerts, [])
    |> assign(:pattern_metrics, init_pattern_metrics())
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
    <div class="pattern-analytics-dashboard">
      <header class="dashboard-header">
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          🧠 Pattern Analytics Dashboard
        </h1>
        <div class="header-stats">
          <span class="stat-badge">
            <span class="stat-label">Patterns/min:</span>
            <span class="stat-value"><%= @pattern_metrics.patterns_per_minute %></span>
          </span>
          <span class="stat-badge">
            <span class="stat-label">Active Alerts:</span>
            <span class="stat-value <%= alert_color_class(length(@active_alerts)) %>">
              <%= length(@active_alerts) %>
            </span>
          </span>
          <span class="stat-badge">
            <span class="stat-label">Correlations:</span>
            <span class="stat-value"><%= @pattern_metrics.total_correlations %></span>
          </span>
        </div>
      </header>
      
      <div class="dashboard-controls">
        <button
          phx-click="set_view_mode"
          phx-value-mode="overview"
          class={"control-button " <> if(@view_mode == :overview, do: "active", else: "")}
        >
          Overview
        </button>
        <button
          phx-click="set_view_mode"
          phx-value-mode="patterns"
          class={"control-button " <> if(@view_mode == :patterns, do: "active", else: "")}
        >
          Patterns
        </button>
        <button
          phx-click="set_view_mode"
          phx-value-mode="correlations"
          class={"control-button " <> if(@view_mode == :correlations, do: "active", else: "")}
        >
          Correlations
        </button>
        <button
          phx-click="set_view_mode"
          phx-value-mode="interventions"
          class={"control-button " <> if(@view_mode == :interventions, do: "active", else: "")}
        >
          Interventions
        </button>
      </div>
      
      <div class="dashboard-content">
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
      
      <style>
        .pattern-analytics-dashboard {
          padding: 20px;
          background: #f5f5f5;
          min-height: 100vh;
        }
        
        .dashboard-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 20px;
          padding: 20px;
          background: white;
          border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .header-stats {
          display: flex;
          gap: 20px;
        }
        
        .stat-badge {
          display: flex;
          align-items: center;
          gap: 8px;
          padding: 8px 16px;
          background: #f0f0f0;
          border-radius: 20px;
        }
        
        .stat-label {
          color: #666;
          font-size: 14px;
        }
        
        .stat-value {
          font-weight: bold;
          font-size: 18px;
        }
        
        .dashboard-controls {
          display: flex;
          gap: 10px;
          margin-bottom: 20px;
        }
        
        .control-button {
          padding: 10px 20px;
          background: white;
          border: 1px solid #ddd;
          border-radius: 4px;
          cursor: pointer;
          transition: all 0.2s;
        }
        
        .control-button:hover {
          background: #f0f0f0;
        }
        
        .control-button.active {
          background: #4F46E5;
          color: white;
          border-color: #4F46E5;
        }
        
        .dashboard-content {
          display: grid;
          gap: 20px;
        }
        
        .dashboard-card {
          background: white;
          border-radius: 8px;
          padding: 20px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .pattern-item {
          padding: 12px;
          border-bottom: 1px solid #eee;
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        
        .pattern-item:last-child {
          border-bottom: none;
        }
        
        .pattern-type {
          font-weight: 600;
          color: #333;
        }
        
        .pattern-confidence {
          display: inline-block;
          padding: 4px 8px;
          border-radius: 4px;
          font-size: 12px;
          font-weight: 600;
        }
        
        .confidence-high {
          background: #10B981;
          color: white;
        }
        
        .confidence-medium {
          background: #F59E0B;
          color: white;
        }
        
        .confidence-low {
          background: #EF4444;
          color: white;
        }
        
        .severity-critical {
          color: #DC2626;
        }
        
        .severity-high {
          color: #F59E0B;
        }
        
        .severity-normal {
          color: #10B981;
        }
        
        .alert-high {
          color: #DC2626;
        }
        
        .alert-medium {
          color: #F59E0B;
        }
        
        .alert-low {
          color: #10B981;
        }
        
        .time-series-chart {
          height: 300px;
          position: relative;
        }
        
        .correlation-graph {
          height: 400px;
          background: #fafafa;
          border-radius: 4px;
          display: flex;
          align-items: center;
          justify-content: center;
          color: #999;
        }
        
        .intervention-item {
          display: grid;
          grid-template-columns: 1fr 2fr 1fr;
          gap: 10px;
          padding: 12px;
          border-bottom: 1px solid #eee;
        }
        
        .intervention-success {
          color: #10B981;
        }
        
        .intervention-failed {
          color: #EF4444;
        }
      </style>
    </div>
    """
  end
  
  defp render_overview(assigns) do
    ~H"""
    <div class="overview-grid">
      <!-- Real-time Pattern Stream -->
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">Real-time Pattern Stream</h2>
        <div class="pattern-stream">
          <%= for pattern <- Enum.take(@recent_patterns, 10) do %>
            <div class="pattern-item" phx-click="select_pattern" phx-value-id={pattern.id}>
              <div>
                <div class="pattern-type"><%= format_pattern_type(pattern.type) %></div>
                <div class="text-sm text-gray-500"><%= format_timestamp(pattern.timestamp) %></div>
              </div>
              <div class="flex items-center gap-2">
                <span class={"pattern-confidence " <> confidence_class(pattern.confidence)}>
                  <%= round(pattern.confidence * 100) %>%
                </span>
                <span class={"severity-" <> to_string(pattern.severity)}>
                  <%= pattern.severity %>
                </span>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Active Alerts -->
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">Active Alerts</h2>
        <div class="alerts-list">
          <%= if @active_alerts == [] do %>
            <p class="text-gray-500 text-center py-8">No active alerts</p>
          <% else %>
            <%= for alert <- @active_alerts do %>
              <div class="alert-item">
                <div class="alert-header">
                  <span class="alert-type"><%= alert.pattern_type %></span>
                  <span class="alert-routing"><%= alert.routing %></span>
                </div>
                <div class="alert-actions">
                  <%= length(alert.interventions) %> interventions,
                  <%= length(alert.policy_adjustments) %> policy changes
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
      
      <!-- Pattern Metrics Chart -->
      <div class="dashboard-card col-span-2">
        <h2 class="text-xl font-semibold mb-4">Pattern Detection Rate</h2>
        <div class="time-series-chart" phx-hook="PatternChart" id="pattern-chart">
          <canvas id="pattern-chart-canvas"></canvas>
        </div>
      </div>
      
      <!-- Subsystem Statistics -->
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">VSM Subsystem Patterns</h2>
        <div class="subsystem-stats">
          <%= for {subsystem, stats} <- @subsystem_stats do %>
            <div class="subsystem-stat">
              <div class="subsystem-name"><%= format_subsystem(subsystem) %></div>
              <div class="subsystem-count"><%= stats.count %></div>
              <div class="subsystem-bar">
                <div class="bar-fill" style={"width: #{stats.percentage}%"}></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Correlation Summary -->
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">Pattern Correlations</h2>
        <div class="correlation-summary">
          <div class="correlation-stat">
            <span class="label">Total Correlations:</span>
            <span class="value"><%= @pattern_metrics.total_correlations %></span>
          </div>
          <div class="correlation-stat">
            <span class="label">Causality Chains:</span>
            <span class="value"><%= @pattern_metrics.causality_chains %></span>
          </div>
          <div class="correlation-stat">
            <span class="label">Avg Chain Length:</span>
            <span class="value"><%= @pattern_metrics.avg_chain_length %></span>
          </div>
          <div class="correlation-stat">
            <span class="label">Algedonic Correlations:</span>
            <span class="value text-red-600"><%= @pattern_metrics.algedonic_correlations %></span>
          </div>
        </div>
      </div>
    </div>
    
    <style>
      .overview-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 20px;
      }
      
      .col-span-2 {
        grid-column: span 2;
      }
      
      .subsystem-stat {
        margin-bottom: 12px;
      }
      
      .subsystem-name {
        font-weight: 600;
        margin-bottom: 4px;
      }
      
      .subsystem-count {
        font-size: 24px;
        font-weight: bold;
        color: #4F46E5;
      }
      
      .subsystem-bar {
        height: 8px;
        background: #e5e5e5;
        border-radius: 4px;
        overflow: hidden;
      }
      
      .bar-fill {
        height: 100%;
        background: #4F46E5;
        transition: width 0.3s;
      }
      
      .correlation-summary {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 12px;
      }
      
      .correlation-stat {
        display: flex;
        flex-direction: column;
      }
      
      .correlation-stat .label {
        font-size: 12px;
        color: #666;
        margin-bottom: 4px;
      }
      
      .correlation-stat .value {
        font-size: 20px;
        font-weight: bold;
      }
    </style>
    """
  end
  
  defp render_patterns_view(assigns) do
    ~H"""
    <div class="patterns-view">
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">Pattern Detection History</h2>
        <div class="pattern-filters mb-4">
          <select phx-change="filter_patterns" class="filter-select">
            <option value="all">All Patterns</option>
            <option value="high_confidence">High Confidence (>80%)</option>
            <option value="critical">Critical Severity</option>
            <option value="operational">Operational</option>
            <option value="strategic">Strategic</option>
          </select>
        </div>
        <div class="patterns-table">
          <table class="w-full">
            <thead>
              <tr>
                <th class="text-left">Timestamp</th>
                <th class="text-left">Type</th>
                <th class="text-left">Source</th>
                <th class="text-center">Confidence</th>
                <th class="text-center">Severity</th>
                <th class="text-center">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for pattern <- @recent_patterns do %>
                <tr class="pattern-row" phx-click="view_pattern_details" phx-value-id={pattern.id}>
                  <td><%= format_timestamp(pattern.timestamp) %></td>
                  <td class="font-semibold"><%= format_pattern_type(pattern.type) %></td>
                  <td><%= pattern.source %></td>
                  <td class="text-center">
                    <span class={"pattern-confidence " <> confidence_class(pattern.confidence)}>
                      <%= round(pattern.confidence * 100) %>%
                    </span>
                  </td>
                  <td class="text-center">
                    <span class={"severity-" <> to_string(pattern.severity)}>
                      <%= pattern.severity %>
                    </span>
                  </td>
                  <td class="text-center">
                    <button class="action-button" phx-click="analyze_pattern" phx-value-id={pattern.id}>
                      Analyze
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
      
      <%= if @selected_pattern do %>
        <div class="dashboard-card">
          <h2 class="text-xl font-semibold mb-4">Pattern Details</h2>
          <div class="pattern-details">
            <div class="detail-row">
              <span class="detail-label">Pattern ID:</span>
              <span class="detail-value"><%= @selected_pattern.id %></span>
            </div>
            <div class="detail-row">
              <span class="detail-label">Type:</span>
              <span class="detail-value"><%= @selected_pattern.type %></span>
            </div>
            <div class="detail-row">
              <span class="detail-label">Metadata:</span>
              <pre class="detail-value"><%= Jason.encode!(@selected_pattern.metadata, pretty: true) %></pre>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    
    <style>
      .patterns-view {
        display: grid;
        gap: 20px;
      }
      
      .filter-select {
        padding: 8px 12px;
        border: 1px solid #ddd;
        border-radius: 4px;
        background: white;
      }
      
      .patterns-table {
        overflow-x: auto;
      }
      
      .patterns-table table {
        min-width: 800px;
      }
      
      .patterns-table th {
        padding: 12px;
        border-bottom: 2px solid #e5e5e5;
        font-weight: 600;
        color: #666;
      }
      
      .patterns-table td {
        padding: 12px;
        border-bottom: 1px solid #f0f0f0;
      }
      
      .pattern-row {
        cursor: pointer;
        transition: background 0.2s;
      }
      
      .pattern-row:hover {
        background: #f9f9f9;
      }
      
      .action-button {
        padding: 4px 12px;
        background: #4F46E5;
        color: white;
        border: none;
        border-radius: 4px;
        font-size: 12px;
        cursor: pointer;
      }
      
      .pattern-details {
        display: grid;
        gap: 12px;
      }
      
      .detail-row {
        display: grid;
        grid-template-columns: 150px 1fr;
        gap: 10px;
      }
      
      .detail-label {
        font-weight: 600;
        color: #666;
      }
      
      .detail-value {
        font-family: monospace;
        background: #f5f5f5;
        padding: 8px;
        border-radius: 4px;
        overflow-x: auto;
      }
    </style>
    """
  end
  
  defp render_correlations_view(assigns) do
    ~H"""
    <div class="correlations-view">
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">Pattern Correlation Analysis</h2>
        <div class="correlation-graph" phx-hook="CorrelationGraph" id="correlation-graph">
          <div class="graph-placeholder">
            Correlation network visualization would appear here
          </div>
        </div>
      </div>
      
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">Causality Chains</h2>
        <div class="causality-chains">
          <%= for chain <- get_causality_chains(@correlation_data) do %>
            <div class="causality-chain">
              <div class="chain-header">
                <span class="chain-length">Chain Length: <%= length(chain.patterns) %></span>
                <span class="chain-confidence"><%= round(chain.confidence * 100) %>%</span>
              </div>
              <div class="chain-flow">
                <%= for {pattern, index} <- Enum.with_index(chain.patterns) do %>
                  <div class="chain-node">
                    <div class="node-type"><%= pattern.type %></div>
                    <div class="node-time"><%= format_relative_time(pattern.timestamp) %></div>
                  </div>
                  <%= if index < length(chain.patterns) - 1 do %>
                    <div class="chain-arrow">→</div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">Correlation Metrics</h2>
        <div class="correlation-metrics">
          <div class="metric-card">
            <h3>Correlation Strength Distribution</h3>
            <div class="strength-distribution">
              <div class="strength-bar">
                <div class="bar weak" style="height: 20%"></div>
                <div class="bar-label">Weak<br/><0.3</div>
              </div>
              <div class="strength-bar">
                <div class="bar medium" style="height: 45%"></div>
                <div class="bar-label">Medium<br/>0.3-0.7</div>
              </div>
              <div class="strength-bar">
                <div class="bar strong" style="height: 80%"></div>
                <div class="bar-label">Strong<br/>>0.7</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    
    <style>
      .correlations-view {
        display: grid;
        gap: 20px;
      }
      
      .causality-chains {
        display: grid;
        gap: 16px;
      }
      
      .causality-chain {
        padding: 16px;
        background: #f9f9f9;
        border-radius: 8px;
        border: 1px solid #e5e5e5;
      }
      
      .chain-header {
        display: flex;
        justify-content: space-between;
        margin-bottom: 12px;
      }
      
      .chain-flow {
        display: flex;
        align-items: center;
        gap: 8px;
        overflow-x: auto;
      }
      
      .chain-node {
        padding: 8px 12px;
        background: white;
        border: 1px solid #ddd;
        border-radius: 4px;
        min-width: 120px;
        text-align: center;
      }
      
      .node-type {
        font-weight: 600;
        font-size: 12px;
      }
      
      .node-time {
        font-size: 10px;
        color: #666;
        margin-top: 4px;
      }
      
      .chain-arrow {
        color: #666;
        font-size: 20px;
      }
      
      .strength-distribution {
        display: flex;
        justify-content: space-around;
        align-items: flex-end;
        height: 150px;
        margin-top: 20px;
      }
      
      .strength-bar {
        display: flex;
        flex-direction: column;
        align-items: center;
        flex: 1;
      }
      
      .strength-bar .bar {
        width: 60px;
        background: #4F46E5;
        border-radius: 4px 4px 0 0;
        margin-bottom: 8px;
      }
      
      .bar-label {
        text-align: center;
        font-size: 12px;
        color: #666;
      }
    </style>
    """
  end
  
  defp render_interventions_view(assigns) do
    ~H"""
    <div class="interventions-view">
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">S3 Control Interventions</h2>
        <div class="interventions-list">
          <%= for intervention <- @intervention_history do %>
            <div class="intervention-item">
              <div>
                <div class="intervention-pattern"><%= intervention.pattern_type %></div>
                <div class="intervention-time"><%= format_timestamp(intervention.timestamp) %></div>
              </div>
              <div class="intervention-actions">
                <%= for action <- intervention.actions do %>
                  <span class="action-tag"><%= format_action(action) %></span>
                <% end %>
              </div>
              <div class={"intervention-" <> if(intervention.success, do: "success", else: "failed")}>
                <%= if intervention.success, do: "✓ Success", else: "✗ Failed" %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">S5 Policy Adjustments</h2>
        <div class="policy-list">
          <%= for adjustment <- @policy_adjustments do %>
            <div class="policy-item">
              <div class="policy-header">
                <span class="policy-pattern"><%= adjustment.pattern_type %></span>
                <span class="policy-time"><%= format_timestamp(adjustment.timestamp) %></span>
              </div>
              <div class="policy-constraints">
                <%= for {constraint, value} <- adjustment.constraints_applied do %>
                  <div class="constraint">
                    <span class="constraint-name"><%= constraint %></span>
                    <span class="constraint-value"><%= inspect(value) %></span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <div class="dashboard-card">
        <h2 class="text-xl font-semibold mb-4">Intervention Effectiveness</h2>
        <div class="effectiveness-chart" phx-hook="EffectivenessChart" id="effectiveness-chart">
          <canvas id="effectiveness-chart-canvas"></canvas>
        </div>
      </div>
    </div>
    
    <style>
      .interventions-view {
        display: grid;
        gap: 20px;
      }
      
      .action-tag {
        display: inline-block;
        padding: 4px 8px;
        background: #e5e7eb;
        border-radius: 4px;
        font-size: 12px;
        margin-right: 4px;
      }
      
      .policy-item {
        padding: 16px;
        border-bottom: 1px solid #e5e5e5;
      }
      
      .policy-item:last-child {
        border-bottom: none;
      }
      
      .policy-header {
        display: flex;
        justify-content: space-between;
        margin-bottom: 12px;
      }
      
      .policy-pattern {
        font-weight: 600;
      }
      
      .policy-time {
        color: #666;
        font-size: 14px;
      }
      
      .policy-constraints {
        display: grid;
        gap: 8px;
      }
      
      .constraint {
        display: flex;
        justify-content: space-between;
        padding: 8px;
        background: #f5f5f5;
        border-radius: 4px;
      }
      
      .constraint-name {
        font-weight: 500;
      }
      
      .constraint-value {
        font-family: monospace;
        font-size: 14px;
      }
    </style>
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
  def handle_event("filter_patterns", %{"value" => filter}, socket) do
    # Implement pattern filtering logic
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("analyze_pattern", %{"id" => pattern_id}, socket) do
    # Trigger pattern analysis
    send(self(), {:analyze_pattern, pattern_id})
    {:noreply, socket}
  end
  
  # Handle incoming pattern events
  
  @impl true
  def handle_info({:event, :pattern_detected, pattern_data}, socket) do
    new_pattern = %{
      id: generate_pattern_id(),
      type: pattern_data[:pattern_type] || :unknown,
      source: pattern_data[:source] || :unknown,
      confidence: pattern_data[:confidence] || 0.0,
      severity: pattern_data[:severity] || :normal,
      timestamp: DateTime.utc_now(),
      metadata: pattern_data
    }
    
    socket = socket
    |> update(:recent_patterns, fn patterns ->
      [new_pattern | patterns] |> Enum.take(@max_recent_patterns)
    end)
    |> update_pattern_metrics()
    |> update_subsystem_stats(new_pattern)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :pattern_causality_detected, causality_data}, socket) do
    socket = socket
    |> update(:correlation_data, fn data ->
      Map.put(data, causality_data[:root_pattern][:id], causality_data)
    end)
    |> update_correlation_metrics(causality_data)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :s3_intervention_complete, result}, socket) do
    intervention = %{
      pattern_type: result[:pattern_type],
      pattern_id: result[:pattern_id],
      actions: result[:actions_taken],
      success: result[:success],
      timestamp: result[:timestamp]
    }
    
    socket = update(socket, :intervention_history, fn history ->
      [intervention | history] |> Enum.take(50)
    end)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :s5_policy_updated, update}, socket) do
    adjustment = %{
      pattern_type: update[:pattern_type],
      pattern_id: update[:pattern_id],
      constraints_applied: update[:adjustments_made] || %{},
      timestamp: update[:timestamp]
    }
    
    socket = update(socket, :policy_adjustments, fn adjustments ->
      [adjustment | adjustments] |> Enum.take(50)
    end)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(:refresh_metrics, socket) do
    # Refresh metrics periodically
    Process.send_after(self(), :refresh_metrics, @refresh_interval)
    
    # Fetch latest data
    active_alerts = fetch_active_alerts()
    pattern_metrics = calculate_current_metrics(socket)
    
    socket = socket
    |> assign(:active_alerts, active_alerts)
    |> assign(:pattern_metrics, pattern_metrics)
    |> update_time_series_data()
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:analyze_pattern, pattern_id}, socket) do
    # Fetch correlation analysis for the pattern
    case PatternCorrelationAnalyzer.get_correlations(pattern_id, []) do
      {:ok, correlations} ->
        # Update UI with correlation data
        {:noreply, socket}
      _ ->
        {:noreply, socket}
    end
  end
  
  # Helper Functions
  
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
    %{
      timestamps: [],
      pattern_counts: [],
      alert_counts: [],
      intervention_counts: []
    }
  end
  
  defp init_subsystem_stats do
    %{
      s1: %{count: 0, percentage: 0},
      s2: %{count: 0, percentage: 0},
      s3: %{count: 0, percentage: 0},
      s4: %{count: 0, percentage: 0},
      s5: %{count: 0, percentage: 0},
      unknown: %{count: 0, percentage: 0}
    }
  end
  
  defp update_pattern_metrics(socket) do
    recent_patterns = socket.assigns.recent_patterns
    
    # Calculate patterns per minute
    one_minute_ago = DateTime.add(DateTime.utc_now(), -60, :second)
    recent_count = Enum.count(recent_patterns, fn p ->
      DateTime.compare(p.timestamp, one_minute_ago) == :gt
    end)
    
    metrics = socket.assigns.pattern_metrics
    |> Map.put(:patterns_per_minute, recent_count)
    |> Map.put(:total_patterns, length(recent_patterns))
    
    assign(socket, :pattern_metrics, metrics)
  end
  
  defp update_subsystem_stats(socket, pattern) do
    subsystem = detect_subsystem(pattern.source)
    
    update(socket, :subsystem_stats, fn stats ->
      new_stats = Map.update!(stats, subsystem, fn s ->
        %{s | count: s.count + 1}
      end)
      
      # Recalculate percentages
      total = new_stats
      |> Map.values()
      |> Enum.map(& &1.count)
      |> Enum.sum()
      
      if total > 0 do
        Map.new(new_stats, fn {k, v} ->
          {k, %{v | percentage: round(v.count / total * 100)}}
        end)
      else
        new_stats
      end
    end)
  end
  
  defp update_correlation_metrics(socket, causality_data) do
    update(socket, :pattern_metrics, fn metrics ->
      metrics
      |> Map.update(:causality_chains, 1, &(&1 + 1))
      |> Map.put(:avg_chain_length, 
        (metrics.avg_chain_length * (metrics.causality_chains - 1) + 
         length(causality_data[:causality_chain])) / metrics.causality_chains
      )
    end)
  end
  
  defp update_time_series_data(socket) do
    now = DateTime.utc_now()
    
    update(socket, :time_series_data, fn data ->
      %{
        timestamps: ([now | data.timestamps] |> Enum.take(@chart_data_points)),
        pattern_counts: ([socket.assigns.pattern_metrics.patterns_per_minute | data.pattern_counts] 
                        |> Enum.take(@chart_data_points)),
        alert_counts: ([length(socket.assigns.active_alerts) | data.alert_counts] 
                      |> Enum.take(@chart_data_points)),
        intervention_counts: ([count_recent_interventions(socket) | data.intervention_counts] 
                            |> Enum.take(@chart_data_points))
      }
    end)
  end
  
  defp fetch_active_alerts do
    case S3S5PatternAlertSystem.get_active_alerts() do
      alerts when is_list(alerts) -> alerts
      _ -> []
    end
  end
  
  defp calculate_current_metrics(socket) do
    socket.assigns.pattern_metrics
  end
  
  defp count_recent_interventions(socket) do
    one_minute_ago = DateTime.add(DateTime.utc_now(), -60, :second)
    
    Enum.count(socket.assigns.intervention_history, fn i ->
      DateTime.compare(i.timestamp, one_minute_ago) == :gt
    end)
  end
  
  defp detect_subsystem(source) do
    case source do
      src when src in [:s1_operations, "s1_operations"] -> :s1
      src when src in [:s2_coordination, "s2_coordination"] -> :s2
      src when src in [:s3_control, "s3_control"] -> :s3
      src when src in [:s4_intelligence, "s4_intelligence"] -> :s4
      src when src in [:s5_policy, "s5_policy"] -> :s5
      _ -> :unknown
    end
  end
  
  defp get_causality_chains(correlation_data) do
    correlation_data
    |> Map.values()
    |> Enum.filter(& &1[:causality_chain])
    |> Enum.map(fn data ->
      %{
        patterns: data[:causality_chain],
        confidence: :rand.uniform()  # Calculate actual confidence
      }
    end)
    |> Enum.take(10)
  end
  
  # Formatting helpers
  
  defp format_pattern_type(type) do
    type
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  
  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%H:%M:%S")
  end
  
  defp format_relative_time(timestamp) do
    seconds_ago = DateTime.diff(DateTime.utc_now(), timestamp)
    
    cond do
      seconds_ago < 60 -> "#{seconds_ago}s ago"
      seconds_ago < 3600 -> "#{div(seconds_ago, 60)}m ago"
      true -> "#{div(seconds_ago, 3600)}h ago"
    end
  end
  
  defp format_subsystem(subsystem) do
    case subsystem do
      :s1 -> "S1 Operations"
      :s2 -> "S2 Coordination"
      :s3 -> "S3 Control"
      :s4 -> "S4 Intelligence"
      :s5 -> "S5 Policy"
      _ -> "Unknown"
    end
  end
  
  defp format_action({action, _params}) do
    action
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
  
  defp confidence_class(confidence) when confidence >= 0.8, do: "confidence-high"
  defp confidence_class(confidence) when confidence >= 0.5, do: "confidence-medium"
  defp confidence_class(_), do: "confidence-low"
  
  defp alert_color_class(count) when count > 10, do: "alert-high"
  defp alert_color_class(count) when count > 5, do: "alert-medium"
  defp alert_color_class(_), do: "alert-low"
  
  defp generate_pattern_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end
end