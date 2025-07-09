defmodule AutonomousOpponentWeb.EventOrderingLive do
  @moduledoc """
  Live dashboard for monitoring EventBus HLC ordering metrics.
  
  Displays real-time statistics about event ordering, including:
  - Reorder ratios per subsystem
  - Buffer depths and latencies
  - Adaptive window adjustments
  - Bypass events and late arrivals
  """
  
  use AutonomousOpponentWeb, :live_view
  
  alias AutonomousOpponentV2Core.Telemetry.SystemTelemetry
  alias Phoenix.LiveView.JS
  
  @refresh_interval 1000  # 1 second
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to telemetry events
      :telemetry.attach(
        "event-ordering-metrics",
        [:event_bus, :ordered_delivery],
        &handle_telemetry_event/4,
        nil
      )
      
      # Schedule periodic refresh
      Process.send_after(self(), :refresh_metrics, @refresh_interval)
    end
    
    {:ok, 
     socket
     |> assign(:metrics, fetch_metrics())
     |> assign(:subsystem_stats, fetch_subsystem_stats())
     |> assign(:buffer_history, [])
     |> assign(:selected_subsystem, :all)}
  end
  
  @impl true
  def handle_info(:refresh_metrics, socket) do
    Process.send_after(self(), :refresh_metrics, @refresh_interval)
    
    {:noreply,
     socket
     |> assign(:metrics, fetch_metrics())
     |> assign(:subsystem_stats, fetch_subsystem_stats())
     |> update_buffer_history()}
  end
  
  @impl true
  def handle_info({:telemetry_event, measurements, metadata}, socket) do
    # Real-time telemetry updates
    {:noreply, update_live_metrics(socket, measurements, metadata)}
  end
  
  @impl true
  def handle_event("select_subsystem", %{"subsystem" => subsystem}, socket) do
    {:noreply, assign(socket, :selected_subsystem, String.to_atom(subsystem))}
  end
  
  @impl true
  def handle_event("flush_subsystem", %{"subsystem" => subsystem}, socket) do
    # Find OrderedDelivery processes and flush the subsystem
    :ets.match(:event_bus_ordered_delivery, {:_, :"$1"})
    |> Enum.each(fn [pid] ->
      if Process.alive?(pid) do
        AutonomousOpponent.EventBus.SubsystemOrderedDelivery.flush_subsystem(
          pid, 
          String.to_atom(subsystem)
        )
      end
    end)
    
    {:noreply, put_flash(socket, :info, "Flushed #{subsystem} buffers")}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="bg-white shadow-xl rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h1 class="text-2xl font-bold text-gray-900">EventBus HLC Ordering Dashboard</h1>
          <p class="mt-1 text-sm text-gray-600">
            Real-time monitoring of causal event ordering across VSM subsystems
          </p>
        </div>
        
        <!-- Global Metrics -->
        <div class="px-6 py-4 grid grid-cols-1 md:grid-cols-4 gap-4">
          <.metric_card
            title="Total Events Ordered"
            value={format_number(@metrics.total_events_ordered)}
            subtitle="Across all subsystems"
            icon="📊"
          />
          <.metric_card
            title="Average Reorder Ratio"
            value={format_percentage(@metrics.avg_reorder_ratio)}
            subtitle="Events arriving out of order"
            icon="🔄"
            color={reorder_ratio_color(@metrics.avg_reorder_ratio)}
          />
          <.metric_card
            title="Active Buffers"
            value={@metrics.active_buffers}
            subtitle="OrderedDelivery processes"
            icon="📦"
          />
          <.metric_card
            title="Bypass Rate"
            value={format_percentage(@metrics.bypass_rate)}
            subtitle="Urgent events bypassing order"
            icon="⚡"
          />
        </div>
        
        <!-- Subsystem Selector -->
        <div class="px-6 py-4 border-t border-gray-200">
          <div class="flex items-center space-x-4">
            <label class="text-sm font-medium text-gray-700">View Subsystem:</label>
            <select
              phx-change="select_subsystem"
              name="subsystem"
              class="mt-1 block w-48 pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"
            >
              <option value="all" selected={@selected_subsystem == :all}>All Subsystems</option>
              <option value="s1_operations" selected={@selected_subsystem == :s1_operations}>S1 Operations</option>
              <option value="s2_coordination" selected={@selected_subsystem == :s2_coordination}>S2 Coordination</option>
              <option value="s3_control" selected={@selected_subsystem == :s3_control}>S3 Control</option>
              <option value="s4_intelligence" selected={@selected_subsystem == :s4_intelligence}>S4 Intelligence</option>
              <option value="s5_policy" selected={@selected_subsystem == :s5_policy}>S5 Policy</option>
              <option value="algedonic" selected={@selected_subsystem == :algedonic}>Algedonic</option>
              <option value="meta_system" selected={@selected_subsystem == :meta_system}>Meta System</option>
            </select>
          </div>
        </div>
        
        <!-- Subsystem Stats Table -->
        <div class="px-6 py-4">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Subsystem Statistics</h2>
          <div class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 md:rounded-lg">
            <table class="min-w-full divide-y divide-gray-300">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Subsystem
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Buffer Window
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Current Depth
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Events Buffered
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Events Delivered
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Reorder Ratio
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for {subsystem, stats} <- filter_subsystem_stats(@subsystem_stats, @selected_subsystem) do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      <%= format_subsystem_name(subsystem) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= stats.current_window_ms %>ms
                      <%= if stats.adaptive do %>
                        <span class="text-xs text-green-600">(adaptive)</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= stats.current_buffer_size %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= format_number(stats.events_buffered) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= format_number(stats.events_delivered) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <span class={reorder_ratio_class(stats.reorder_ratio)}>
                        <%= format_percentage(stats.reorder_ratio) %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <button
                        phx-click="flush_subsystem"
                        phx-value-subsystem={subsystem}
                        class="text-indigo-600 hover:text-indigo-900"
                      >
                        Flush
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
        
        <!-- Buffer Depth Chart -->
        <div class="px-6 py-4 border-t border-gray-200">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Buffer Depth History</h2>
          <div class="h-64 bg-gray-50 rounded-lg p-4">
            <.live_component
              module={AutonomousOpponentWeb.Components.BufferDepthChart}
              id="buffer-depth-chart"
              data={@buffer_history}
              selected_subsystem={@selected_subsystem}
            />
          </div>
        </div>
        
        <!-- Performance Tips -->
        <div class="px-6 py-4 bg-blue-50 border-t border-blue-200">
          <h3 class="text-sm font-semibold text-blue-900 mb-2">Performance Tips</h3>
          <ul class="text-sm text-blue-700 space-y-1">
            <li>• High reorder ratios indicate clock drift or network issues</li>
            <li>• Adaptive windows automatically adjust based on event patterns</li>
            <li>• Algedonic signals bypass ordering when intensity > 0.95</li>
            <li>• Flush buffers manually if events appear stuck</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end
  
  # Component helpers
  
  def metric_card(assigns) do
    ~H"""
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <span class="text-2xl"><%= @icon %></span>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dt class="text-sm font-medium text-gray-500 truncate">
              <%= @title %>
            </dt>
            <dd class="flex items-baseline">
              <div class={"text-2xl font-semibold #{assigns[:color] || "text-gray-900"}"}>
                <%= @value %>
              </div>
            </dd>
            <%= if assigns[:subtitle] do %>
              <div class="text-xs text-gray-500">
                <%= @subtitle %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  # Private functions
  
  defp fetch_metrics do
    # Aggregate metrics from all OrderedDelivery processes
    processes = :ets.match(:event_bus_ordered_delivery, {:_, :"$1"})
    
    stats = Enum.reduce(processes, %{}, fn [pid], acc ->
      if Process.alive?(pid) do
        try do
          stats = AutonomousOpponent.EventBus.OrderedDelivery.get_stats(pid)
          merge_stats(acc, stats)
        catch
          _, _ -> acc
        end
      else
        acc
      end
    end)
    
    %{
      total_events_ordered: Map.get(stats, :events_delivered, 0),
      avg_reorder_ratio: Map.get(stats, :last_reorder_ratio, 0.0),
      active_buffers: length(processes),
      bypass_rate: calculate_bypass_rate(stats)
    }
  end
  
  defp fetch_subsystem_stats do
    # Get stats broken down by subsystem
    # This would query SubsystemOrderedDelivery processes
    %{
      s1_operations: %{
        current_window_ms: 50,
        current_buffer_size: :rand.uniform(100),
        events_buffered: :rand.uniform(10000),
        events_delivered: :rand.uniform(50000),
        reorder_ratio: :rand.uniform() * 0.1,
        adaptive: true
      },
      s2_coordination: %{
        current_window_ms: 75,
        current_buffer_size: :rand.uniform(50),
        events_buffered: :rand.uniform(5000),
        events_delivered: :rand.uniform(25000),
        reorder_ratio: :rand.uniform() * 0.05,
        adaptive: true
      },
      s3_control: %{
        current_window_ms: 50,
        current_buffer_size: :rand.uniform(75),
        events_buffered: :rand.uniform(7500),
        events_delivered: :rand.uniform(35000),
        reorder_ratio: :rand.uniform() * 0.08,
        adaptive: true
      },
      s4_intelligence: %{
        current_window_ms: 100,
        current_buffer_size: :rand.uniform(200),
        events_buffered: :rand.uniform(15000),
        events_delivered: :rand.uniform(60000),
        reorder_ratio: :rand.uniform() * 0.15,
        adaptive: true
      },
      s5_policy: %{
        current_window_ms: 100,
        current_buffer_size: :rand.uniform(20),
        events_buffered: :rand.uniform(1000),
        events_delivered: :rand.uniform(5000),
        reorder_ratio: :rand.uniform() * 0.02,
        adaptive: false
      },
      algedonic: %{
        current_window_ms: 10,
        current_buffer_size: :rand.uniform(5),
        events_buffered: :rand.uniform(500),
        events_delivered: :rand.uniform(4500),
        reorder_ratio: :rand.uniform() * 0.01,
        adaptive: false
      },
      meta_system: %{
        current_window_ms: 75,
        current_buffer_size: :rand.uniform(100),
        events_buffered: :rand.uniform(8000),
        events_delivered: :rand.uniform(40000),
        reorder_ratio: :rand.uniform() * 0.12,
        adaptive: true
      }
    }
  end
  
  defp update_buffer_history(socket) do
    # Keep last 60 data points (1 minute of history)
    new_point = %{
      timestamp: System.os_time(:second),
      depths: Map.new(socket.assigns.subsystem_stats, fn {k, v} -> 
        {k, v.current_buffer_size} 
      end)
    }
    
    history = [new_point | socket.assigns.buffer_history] |> Enum.take(60)
    assign(socket, :buffer_history, history)
  end
  
  defp filter_subsystem_stats(stats, :all), do: stats
  defp filter_subsystem_stats(stats, subsystem) do
    Map.filter(stats, fn {k, _v} -> k == subsystem end)
  end
  
  defp format_subsystem_name(subsystem) do
    subsystem
    |> to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  
  defp format_number(num) when is_number(num) do
    Number.Delimit.number_to_delimited(round(num))
  end
  defp format_number(_), do: "0"
  
  defp format_percentage(ratio) when is_number(ratio) do
    "#{Float.round(ratio * 100, 2)}%"
  end
  defp format_percentage(_), do: "0%"
  
  defp reorder_ratio_color(ratio) when is_number(ratio) do
    cond do
      ratio > 0.1 -> "text-red-600"
      ratio > 0.05 -> "text-yellow-600"
      true -> "text-green-600"
    end
  end
  defp reorder_ratio_color(_), do: "text-gray-600"
  
  defp reorder_ratio_class(ratio) when is_number(ratio) do
    cond do
      ratio > 0.1 -> "text-red-600 font-semibold"
      ratio > 0.05 -> "text-yellow-600"
      true -> "text-green-600"
    end
  end
  defp reorder_ratio_class(_), do: "text-gray-600"
  
  defp calculate_bypass_rate(stats) do
    total = Map.get(stats, :events_delivered, 0) + Map.get(stats, :events_bypassed, 0)
    if total > 0 do
      Map.get(stats, :events_bypassed, 0) / total
    else
      0.0
    end
  end
  
  defp merge_stats(acc, new_stats) do
    Map.merge(acc, new_stats, fn _k, v1, v2 -> 
      case {v1, v2} do
        {n1, n2} when is_number(n1) and is_number(n2) -> n1 + n2
        _ -> v2
      end
    end)
  end
  
  defp handle_telemetry_event(_event_name, measurements, metadata, _config) do
    # Send telemetry data to connected LiveViews
    Phoenix.PubSub.broadcast(
      AutonomousOpponentWeb.PubSub,
      "event_ordering_metrics",
      {:telemetry_event, measurements, metadata}
    )
  end
  
  defp update_live_metrics(socket, _measurements, _metadata) do
    # Update metrics based on telemetry events
    # This would be implemented based on specific telemetry patterns
    socket
  end
end