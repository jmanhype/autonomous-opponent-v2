defmodule AutonomousOpponentV2Web.BeliefConsensusLive do
  @moduledoc """
  LiveView dashboard for monitoring CRDT Belief Consensus across VSM levels.
  
  Displays:
  - Real-time belief updates and consensus status
  - Byzantine node detection alerts
  - Voting progress and reputation scores
  - Delta sync metrics and bandwidth usage
  - Pattern-belief correlations
  - Algedonic bypass events
  """
  
  use AutonomousOpponentV2Web, :live_view
  require Logger
  
  alias AutonomousOpponentV2Core.VSM.BeliefConsensus
  alias AutonomousOpponentV2Core.VSM.BeliefConsensus.{ByzantineDetector, DeltaSync, PatternIntegration}
  alias Phoenix.PubSub
  
  @refresh_interval 1_000  # Update every second
  @vsm_levels [:s1, :s2, :s3, :s4, :s5]
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to PubSub topics
      PubSub.subscribe(AutonomousOpponentV2Web.PubSub, "belief:updates")
      PubSub.subscribe(AutonomousOpponentV2Web.PubSub, "consensus:changes")
      PubSub.subscribe(AutonomousOpponentV2Web.PubSub, "byzantine:alerts")
      PubSub.subscribe(AutonomousOpponentV2Web.PubSub, "algedonic:events")
      
      # Subscribe to EventBus events
      Task.start(fn ->
        try do
          if Process.whereis(AutonomousOpponentV2Core.EventBus) do
            AutonomousOpponentV2Core.EventBus.subscribe(:belief_consensus_update)
            AutonomousOpponentV2Core.EventBus.subscribe(:byzantine_node_detected)
            AutonomousOpponentV2Core.EventBus.subscribe(:algedonic_pain)
            AutonomousOpponentV2Core.EventBus.subscribe(:pattern_belief_correlation)
          end
        rescue
          error -> 
            Logger.warning("Failed to subscribe to EventBus: #{inspect(error)}")
        end
      end)
      
      # Start refresh timer
      :timer.send_interval(@refresh_interval, self(), :refresh_metrics)
    end
    
    socket =
      socket
      |> assign(:page_title, "Belief Consensus Monitor")
      |> assign(:vsm_levels, @vsm_levels)
      |> assign(:selected_level, :s4)
      |> assign(:consensus_data, %{})
      |> assign(:belief_history, [])
      |> assign(:byzantine_nodes, [])
      |> assign(:sync_metrics, %{})
      |> assign(:pattern_correlations, [])
      |> assign(:algedonic_events, [])
      |> assign(:voting_progress, %{})
      |> assign(:system_health, calculate_system_health())
      |> load_initial_data()
    
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="belief-consensus-dashboard">
      <header class="mb-6">
        <h1 class="text-3xl font-bold">🧠 CRDT Belief Consensus Monitor</h1>
        <p class="text-gray-600 dark:text-gray-400">
          Real-time monitoring of distributed belief consensus across VSM levels
        </p>
      </header>
      
      <!-- System Health Overview -->
      <div class="system-health-card bg-gray-50 dark:bg-gray-800 p-6 rounded-lg mb-6">
        <h3 class="text-lg font-semibold mb-4">System Health</h3>
        <div class="grid grid-cols-4 gap-4">
          <div class="metric-card">
            <div class="metric-label">Consensus Quality</div>
            <div class="metric-value text-2xl font-bold">
              <%= format_percentage(@system_health.consensus_quality) %>
            </div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Active Nodes</div>
            <div class="metric-value text-2xl font-bold">
              <%= @system_health.active_nodes %>
            </div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Byzantine Nodes</div>
            <div class="metric-value text-2xl font-bold text-red-600">
              <%= length(@byzantine_nodes) %>
            </div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Sync Efficiency</div>
            <div class="metric-value text-2xl font-bold">
              <%= format_percentage(@system_health.sync_efficiency) %>
            </div>
          </div>
        </div>
      </div>
      
      <!-- VSM Level Selector -->
      <div class="level-selector mb-6">
        <form phx-change="select_level" class="flex items-center space-x-4">
          <label for="level" class="text-sm font-medium">VSM Level:</label>
          <select 
            name="level" 
            id="level"
            value={@selected_level}
            class="rounded border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800"
          >
            <%= for level <- @vsm_levels do %>
              <option value={level} selected={level == @selected_level}>
                <%= vsm_level_name(level) %>
              </option>
            <% end %>
          </select>
        </form>
      </div>
      
      <!-- Main Content Grid -->
      <div class="grid grid-cols-2 gap-6">
        <!-- Left Column -->
        <div class="space-y-6">
          <!-- Current Consensus -->
          <div class="consensus-card bg-white dark:bg-gray-900 p-6 rounded-lg shadow">
            <h3 class="text-lg font-semibold mb-4">
              Current Consensus - <%= vsm_level_name(@selected_level) %>
            </h3>
            <%= if consensus = Map.get(@consensus_data, @selected_level) do %>
              <div class="space-y-3">
                <%= for belief <- consensus.beliefs do %>
                  <div class="belief-item p-3 bg-gray-50 dark:bg-gray-800 rounded">
                    <div class="font-medium"><%= belief.content %></div>
                    <div class="text-sm text-gray-600 dark:text-gray-400">
                      Weight: <%= Float.round(belief.weight, 2) %> | 
                      Confidence: <%= format_percentage(belief.confidence) %>
                    </div>
                  </div>
                <% end %>
                <div class="mt-4 text-sm text-gray-600">
                  Consensus Strength: <%= format_percentage(consensus.strength) %>
                </div>
              </div>
            <% else %>
              <div class="text-gray-500">No consensus data available</div>
            <% end %>
          </div>
          
          <!-- Voting Progress -->
          <div class="voting-card bg-white dark:bg-gray-900 p-6 rounded-lg shadow">
            <h3 class="text-lg font-semibold mb-4">Active Voting</h3>
            <%= if map_size(@voting_progress) > 0 do %>
              <div class="space-y-3">
                <%= for {belief_id, progress} <- @voting_progress do %>
                  <div class="voting-item">
                    <div class="flex justify-between mb-1">
                      <span class="text-sm">Belief <%= String.slice(belief_id, 0..7) %>...</span>
                      <span class="text-sm"><%= progress.vote_count %> votes</span>
                    </div>
                    <div class="w-full bg-gray-200 rounded-full h-2">
                      <div 
                        class="bg-blue-600 h-2 rounded-full"
                        style={"width: #{progress.percentage}%"}
                      />
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-gray-500">No active voting</div>
            <% end %>
          </div>
        </div>
        
        <!-- Right Column -->
        <div class="space-y-6">
          <!-- Byzantine Alerts -->
          <%= if length(@byzantine_nodes) > 0 do %>
            <div class="byzantine-alert bg-red-50 dark:bg-red-900/20 p-6 rounded-lg shadow">
              <h3 class="text-lg font-semibold mb-4 text-red-700 dark:text-red-400">
                ⚠️ Byzantine Nodes Detected
              </h3>
              <div class="space-y-2">
                <%= for node <- @byzantine_nodes do %>
                  <div class="text-sm">
                    <span class="font-medium"><%= node.node_id %></span>
                    <span class="text-red-600">- Patterns: <%= Enum.join(node.patterns, ", ") %></span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
          
          <!-- Delta Sync Metrics -->
          <div class="sync-metrics bg-white dark:bg-gray-900 p-6 rounded-lg shadow">
            <h3 class="text-lg font-semibold mb-4">Delta Sync Performance</h3>
            <%= if sync = Map.get(@sync_metrics, @selected_level) do %>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <div class="text-sm text-gray-600">Delta Buffer</div>
                  <div class="text-xl font-semibold"><%= sync.delta_buffer_size %></div>
                </div>
                <div>
                  <div class="text-sm text-gray-600">Compression</div>
                  <div class="text-xl font-semibold">
                    <%= format_percentage(sync.compression_ratio) %>
                  </div>
                </div>
                <div>
                  <div class="text-sm text-gray-600">Bandwidth</div>
                  <div class="text-xl font-semibold">
                    <%= format_bytes(sync.total_bandwidth) %>
                  </div>
                </div>
                <div>
                  <div class="text-sm text-gray-600">Success Rate</div>
                  <div class="text-xl font-semibold">
                    <%= format_percentage(sync.sync_success_rate) %>
                  </div>
                </div>
              </div>
            <% else %>
              <div class="text-gray-500">Loading sync metrics...</div>
            <% end %>
          </div>
          
          <!-- Pattern Correlations -->
          <div class="correlations bg-white dark:bg-gray-900 p-6 rounded-lg shadow">
            <h3 class="text-lg font-semibold mb-4">Pattern-Belief Correlations</h3>
            <%= if length(@pattern_correlations) > 0 do %>
              <div class="space-y-2">
                <%= for correlation <- Enum.take(@pattern_correlations, 5) do %>
                  <div class="flex justify-between text-sm">
                    <span>
                      <%= String.slice(correlation.pattern1, 0..10) %> ↔ 
                      <%= String.slice(correlation.pattern2, 0..10) %>
                    </span>
                    <span class="font-medium">
                      <%= Float.round(correlation.strength, 2) %>
                    </span>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-gray-500">No pattern correlations detected</div>
            <% end %>
          </div>
        </div>
      </div>
      
      <!-- Belief History Timeline -->
      <div class="belief-history mt-6 bg-white dark:bg-gray-900 p-6 rounded-lg shadow">
        <h3 class="text-lg font-semibold mb-4">Recent Belief Activity</h3>
        <div class="timeline space-y-3">
          <%= for event <- Enum.take(@belief_history, 10) do %>
            <div class="timeline-item flex items-start">
              <div class={"timeline-icon w-2 h-2 rounded-full mt-1.5 mr-3 #{event_color(event.type)}"} />
              <div class="flex-1">
                <div class="flex justify-between">
                  <span class="font-medium"><%= event.description %></span>
                  <span class="text-sm text-gray-500">
                    <%= format_time_ago(event.timestamp) %>
                  </span>
                </div>
                <div class="text-sm text-gray-600"><%= event.details %></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Algedonic Events -->
      <%= if length(@algedonic_events) > 0 do %>
        <div class="algedonic-events mt-6 bg-yellow-50 dark:bg-yellow-900/20 p-6 rounded-lg shadow">
          <h3 class="text-lg font-semibold mb-4 text-yellow-700 dark:text-yellow-400">
            ⚡ Algedonic Bypass Events
          </h3>
          <div class="space-y-3">
            <%= for event <- Enum.take(@algedonic_events, 5) do %>
              <div class="p-3 bg-yellow-100 dark:bg-yellow-900/30 rounded">
                <div class="font-medium"><%= event.belief_content %></div>
                <div class="text-sm text-yellow-700 dark:text-yellow-500">
                  Urgency: <%= format_percentage(event.urgency) %> | 
                  Level: <%= event.level %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
  
  @impl true
  def handle_event("select_level", %{"level" => level}, socket) do
    selected_level = String.to_atom(level)
    
    socket =
      socket
      |> assign(:selected_level, selected_level)
      |> load_level_data(selected_level)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(:refresh_metrics, socket) do
    socket =
      socket
      |> update_metrics()
      |> update_system_health()
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:belief_consensus_update, data}, socket) do
    socket =
      socket
      |> update_consensus_data(data)
      |> add_to_history(:consensus_update, data)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:byzantine_node_detected, data}, socket) do
    socket =
      socket
      |> update(:byzantine_nodes, fn nodes ->
        [data | nodes] |> Enum.uniq_by(& &1.node_id) |> Enum.take(10)
      end)
      |> add_to_history(:byzantine_detection, data)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:algedonic_pain, data}, socket) do
    algedonic_event = %{
      belief_content: data[:belief] || "Emergency signal",
      urgency: data[:urgency] || 1.0,
      level: data[:level] || :unknown,
      timestamp: DateTime.utc_now()
    }
    
    socket =
      socket
      |> update(:algedonic_events, fn events ->
        [algedonic_event | events] |> Enum.take(20)
      end)
      |> add_to_history(:algedonic_bypass, algedonic_event)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:pattern_belief_correlation, data}, socket) do
    socket =
      socket
      |> update(:pattern_correlations, fn corrs ->
        [data | corrs] |> Enum.uniq_by(& {&1.pattern1, &1.pattern2}) |> Enum.take(20)
      end)
    
    {:noreply, socket}
  end
  
  # Private functions
  
  defp load_initial_data(socket) do
    socket
    |> load_all_consensus_data()
    |> load_byzantine_nodes()
    |> load_sync_metrics()
    |> load_pattern_correlations()
  end
  
  defp load_all_consensus_data(socket) do
    consensus_data = Enum.reduce(@vsm_levels, %{}, fn level, acc ->
      case BeliefConsensus.get_consensus(level) do
        {:ok, consensus} -> Map.put(acc, level, consensus)
        _ -> acc
      end
    end)
    
    assign(socket, :consensus_data, consensus_data)
  end
  
  defp load_byzantine_nodes(socket) do
    nodes = ByzantineDetector.get_byzantine_nodes()
    |> Enum.map(fn node_id ->
      # Get actual patterns from detector
      patterns = ByzantineDetector.get_node_patterns(node_id)
      %{
        node_id: node_id,
        patterns: patterns,
        timestamp: DateTime.utc_now()
      }
    end)
    
    assign(socket, :byzantine_nodes, nodes)
  end
  
  defp load_sync_metrics(socket) do
    metrics = Enum.reduce(@vsm_levels, %{}, fn level, acc ->
      case DeltaSync.get_metrics(level) do
        metrics when is_map(metrics) -> Map.put(acc, level, metrics)
        _ -> acc
      end
    end)
    
    assign(socket, :sync_metrics, metrics)
  end
  
  defp load_pattern_correlations(socket) do
    case PatternIntegration.get_correlations() do
      {:ok, correlations} ->
        assign(socket, :pattern_correlations, correlations)
      _ ->
        socket
    end
  end
  
  defp load_level_data(socket, level) do
    socket
    |> load_level_consensus(level)
    |> load_level_sync_metrics(level)
    |> load_voting_progress(level)
  end
  
  defp load_level_consensus(socket, level) do
    case BeliefConsensus.get_consensus(level) do
      {:ok, consensus} ->
        update(socket, :consensus_data, &Map.put(&1, level, consensus))
      _ ->
        socket
    end
  end
  
  defp load_level_sync_metrics(socket, level) do
    case DeltaSync.get_metrics(level) do
      metrics when is_map(metrics) ->
        update(socket, :sync_metrics, &Map.put(&1, level, metrics))
      _ ->
        socket
    end
  end
  
  defp load_voting_progress(socket, level) do
    # In production, get active voting from BeliefConsensus
    # For now, return empty
    assign(socket, :voting_progress, %{})
  end
  
  defp update_metrics(socket) do
    selected_level = socket.assigns.selected_level
    
    socket
    |> load_level_consensus(selected_level)
    |> load_level_sync_metrics(selected_level)
  end
  
  defp update_system_health(socket) do
    assign(socket, :system_health, calculate_system_health())
  end
  
  defp calculate_system_health do
    # In production, aggregate health metrics from all components
    %{
      consensus_quality: 0.85,
      active_nodes: Node.list() |> length() |> Kernel.+(1),
      sync_efficiency: 0.92,
      overall_health: 0.88
    }
  end
  
  defp update_consensus_data(socket, data) do
    level = data[:level] || socket.assigns.selected_level
    
    update(socket, :consensus_data, fn consensus_map ->
      Map.update(consensus_map, level, data, fn _old -> data end)
    end)
  end
  
  defp add_to_history(socket, event_type, data) do
    event = %{
      type: event_type,
      description: format_event_description(event_type, data),
      details: format_event_details(event_type, data),
      timestamp: DateTime.utc_now()
    }
    
    update(socket, :belief_history, fn history ->
      [event | history] |> Enum.take(100)
    end)
  end
  
  defp format_event_description(:consensus_update, data) do
    "Consensus updated for #{data[:level] || "unknown"}"
  end
  defp format_event_description(:byzantine_detection, data) do
    "Byzantine node detected: #{data[:node_id]}"
  end
  defp format_event_description(:algedonic_bypass, _data) do
    "Algedonic bypass activated"
  end
  defp format_event_description(_, _), do: "Unknown event"
  
  defp format_event_details(:consensus_update, data) do
    "#{data[:vote_count] || 0} votes, #{length(data[:beliefs] || [])} beliefs"
  end
  defp format_event_details(:byzantine_detection, data) do
    "Patterns: #{Enum.join(data[:patterns] || [], ", ")}"
  end
  defp format_event_details(:algedonic_bypass, data) do
    "Urgency: #{format_percentage(data[:urgency])}"
  end
  defp format_event_details(_, _), do: ""
  
  defp vsm_level_name(:s1), do: "S1 - Operations"
  defp vsm_level_name(:s2), do: "S2 - Coordination"
  defp vsm_level_name(:s3), do: "S3 - Control"
  defp vsm_level_name(:s4), do: "S4 - Intelligence"
  defp vsm_level_name(:s5), do: "S5 - Policy"
  defp vsm_level_name(_), do: "Unknown"
  
  defp event_color(:consensus_update), do: "bg-green-500"
  defp event_color(:byzantine_detection), do: "bg-red-500"
  defp event_color(:algedonic_bypass), do: "bg-yellow-500"
  defp event_color(_), do: "bg-gray-500"
  
  defp format_percentage(nil), do: "0%"
  defp format_percentage(value) when is_float(value) do
    "#{round(value * 100)}%"
  end
  defp format_percentage(value) when is_integer(value) do
    "#{value}%"
  end
  
  defp format_bytes(nil), do: "0 B"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end
  defp format_bytes(bytes) do
    "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  end
  
  defp format_time_ago(nil), do: "unknown"
  defp format_time_ago(timestamp) do
    seconds = DateTime.diff(DateTime.utc_now(), timestamp)
    
    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86400)}d ago"
    end
  end
end