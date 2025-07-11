defmodule AutonomousOpponentWeb.PatternFlowLive do
  @moduledoc """
  Real-time pattern flow visualization dashboard.
  
  Displays:
  - Live pattern stream with variety metrics
  - HNSW index statistics
  - VSM subsystem pattern distribution
  - Algedonic signal intensity
  - Cluster-wide pattern consensus
  """
  
  use AutonomousOpponentV2Web, :live_view
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge
  alias Phoenix.Socket.Broadcast
  
  @refresh_interval 1000  # 1 second
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to pattern events
      EventBus.subscribe(:patterns_indexed)
      EventBus.subscribe(:pattern_matched)
      EventBus.subscribe(:algedonic_signal)
      
      # Schedule periodic updates
      :timer.send_interval(@refresh_interval, self(), :refresh_stats)
    end
    
    {:ok, 
     socket
     |> assign(:patterns, [])
     |> assign(:stats, %{})
     |> assign(:monitoring, %{})
     |> assign(:algedonic_signals, [])
     |> assign(:vsm_distribution, %{})
     |> load_initial_data()
    }
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="pattern-flow-dashboard">
      <h1 class="text-3xl font-bold mb-6">HNSW Pattern Flow Dashboard</h1>
      
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <!-- Pattern Statistics -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">Pattern Statistics</h2>
          <dl class="space-y-2">
            <div class="flex justify-between">
              <dt class="text-gray-600">Total Patterns</dt>
              <dd class="font-mono"><%= @stats[:patterns_indexed] || 0 %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-600">Dedup Rate</dt>
              <dd class="font-mono"><%= format_percentage(@stats[:dedup_rate]) %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-600">Buffer Size</dt>
              <dd class="font-mono"><%= @stats[:buffer_size] || 0 %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-600">Indexing Lag</dt>
              <dd class="font-mono"><%= @stats[:indexing_lag] || 0 %></dd>
            </div>
          </dl>
        </div>
        
        <!-- HNSW Performance -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">HNSW Performance</h2>
          <dl class="space-y-2">
            <div class="flex justify-between">
              <dt class="text-gray-600">Index Size</dt>
              <dd class="font-mono"><%= @stats[:hnsw_stats][:size] || 0 %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-600">Avg Search Time</dt>
              <dd class="font-mono"><%= format_ms(@stats[:hnsw_stats][:avg_search_time]) %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-600">Backpressure</dt>
              <dd class={[
                "font-mono",
                @stats[:backpressure_active] && "text-red-600"
              ]}>
                <%= if @stats[:backpressure_active], do: "ACTIVE", else: "Normal" %>
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-600">Cache Size</dt>
              <dd class="font-mono"><%= @stats[:cache_size] || 0 %></dd>
            </div>
          </dl>
        </div>
        
        <!-- System Health -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">System Health</h2>
          <%= if @monitoring[:health] do %>
            <div class={[
              "text-2xl font-bold text-center mb-4",
              health_color(@monitoring[:health][:status])
            ]}>
              <%= String.upcase(to_string(@monitoring[:health][:status])) %>
            </div>
            
            <%= if length(@monitoring[:health][:warnings] || []) > 0 do %>
              <div class="mt-4">
                <h3 class="font-semibold text-yellow-600">Warnings:</h3>
                <ul class="text-sm text-gray-600 mt-2">
                  <%= for warning <- @monitoring[:health][:warnings] do %>
                    <li class="flex items-start">
                      <span class="text-yellow-500 mr-1">⚠</span>
                      <%= warning %>
                    </li>
                  <% end %>
                </ul>
              </div>
            <% end %>
          <% else %>
            <p class="text-gray-500">Loading...</p>
          <% end %>
        </div>
      </div>
      
      <!-- Algedonic Signals -->
      <%= if length(@algedonic_signals) > 0 do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-6 mb-8">
          <h2 class="text-xl font-semibold text-red-800 mb-4">
            🚨 Algedonic Signals (Last 10)
          </h2>
          <div class="space-y-2">
            <%= for signal <- Enum.take(@algedonic_signals, 10) do %>
              <div class="flex items-center justify-between p-2 bg-white rounded">
                <div>
                  <span class="font-mono text-sm"><%= signal.source %></span>
                  <span class="text-gray-600 ml-2"><%= signal.type %></span>
                </div>
                <div class="flex items-center">
                  <div class="w-32 bg-gray-200 rounded-full h-2 mr-2">
                    <div 
                      class="bg-red-600 h-2 rounded-full"
                      style={"width: #{signal.intensity * 100}%"}
                    ></div>
                  </div>
                  <span class="font-mono text-sm"><%= Float.round(signal.intensity, 2) %></span>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
      
      <!-- Live Pattern Stream -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-xl font-semibold mb-4">Live Pattern Stream</h2>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead>
              <tr>
                <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Time</th>
                <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Pattern ID</th>
                <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Confidence</th>
                <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Source</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for pattern <- Enum.take(@patterns, 20) do %>
                <tr>
                  <td class="px-4 py-2 whitespace-nowrap text-sm text-gray-900">
                    <%= format_timestamp(pattern.timestamp) %>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap text-sm font-mono text-gray-900">
                    <%= String.slice(pattern.id || "unknown", 0..7) %>...
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap text-sm text-gray-900">
                    <%= pattern.type || "unknown" %>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap text-sm text-gray-900">
                    <div class="flex items-center">
                      <div class="w-16 bg-gray-200 rounded-full h-2 mr-2">
                        <div 
                          class="bg-blue-600 h-2 rounded-full"
                          style={"width: #{pattern.confidence * 100}%"}
                        ></div>
                      </div>
                      <%= Float.round(pattern.confidence, 2) %>
                    </div>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap text-sm text-gray-900">
                    <%= pattern.source %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
  
  # Event handlers
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :pattern_matched} = event}, socket) do
    pattern = %{
      id: event.data[:pattern_id],
      type: get_in(event.data, [:match_context, :type]) || "unknown",
      confidence: get_in(event.data, [:match_context, :confidence]) || 0.0,
      source: to_string(get_in(event.data, [:match_context, :source]) || "unknown"),
      timestamp: event.timestamp
    }
    
    patterns = [pattern | socket.assigns.patterns] |> Enum.take(100)
    
    {:noreply, assign(socket, :patterns, patterns)}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :algedonic_signal} = event}, socket) do
    if event.data[:intensity] > 0.5 do
      signal = %{
        type: event.data[:type],
        intensity: event.data[:intensity],
        source: to_string(event.data[:source]),
        timestamp: event.timestamp
      }
      
      signals = [signal | socket.assigns.algedonic_signals] |> Enum.take(20)
      
      {:noreply, assign(socket, :algedonic_signals, signals)}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_info(:refresh_stats, socket) do
    {:noreply, load_stats(socket)}
  end
  
  @impl true
  def handle_info(_, socket) do
    {:noreply, socket}
  end
  
  # Private helpers
  
  defp load_initial_data(socket) do
    socket
    |> load_stats()
    |> load_monitoring()
  end
  
  defp load_stats(socket) do
    stats = case Process.whereis(AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge) do
      nil -> %{}
      _pid -> 
        try do
          AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_stats()
        rescue
          _ -> %{}
        end
    end
    
    assign(socket, :stats, stats)
  end
  
  defp load_monitoring(socket) do
    monitoring = case Process.whereis(AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge) do
      nil -> %{}
      _pid -> 
        try do
          AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_monitoring_info()
        rescue
          _ -> %{}
        end
    end
    
    assign(socket, :monitoring, monitoring)
  end
  
  defp format_percentage(nil), do: "0%"
  defp format_percentage(rate) when is_number(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end
  
  defp format_ms(nil), do: "0ms"
  defp format_ms(time) when is_number(time) do
    "#{Float.round(time, 2)}ms"
  end
  
  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end
  defp format_timestamp(_), do: "unknown"
  
  defp health_color(:healthy), do: "text-green-600"
  defp health_color(:degraded), do: "text-yellow-600"
  defp health_color(:warning), do: "text-orange-600"
  defp health_color(:error), do: "text-red-600"
  defp health_color(_), do: "text-gray-600"
end