defmodule AutonomousOpponentV2Web.DashboardLive do
  use AutonomousOpponentV2Web, :live_view
  
  alias AutonomousOpponentV2Core.VSM.{S1, S2, S3, S4, S5}
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Consciousness
  
  @refresh_interval 1000  # 1 second refresh for better performance
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to all VSM events
      EventBus.subscribe(:vsm_updates)
      EventBus.subscribe(:s1_health)
      EventBus.subscribe(:variety_flow)
      EventBus.subscribe(:algedonic_signal)
      EventBus.subscribe(:consciousness_update)
      
      # Start periodic updates
      :timer.send_interval(@refresh_interval, self(), :tick)
    end
    
    socket = socket
    |> assign(:page_title, "System Monitoring")
    |> assign(:chart_data, generate_chart_data())
    |> assign(:system_stats, get_system_stats())
    |> assign(:vsm_health, get_vsm_health())
    |> assign(:variety_flow, get_variety_flow())
    |> assign(:chat_messages, [])
    |> assign(:current_message, "")
    |> assign(:chat_open, false)
    |> assign(:time_labels, generate_time_labels())
    |> assign(:cpu_history, List.duplicate(0, 60))
    |> assign(:memory_history, List.duplicate(0, 30))
    |> assign(:consciousness_state, %{state: :unknown, awareness_level: 0})
    
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0a0f14] text-[#00ffcc] font-mono p-4">
      <style>
        @keyframes pulse-glow {
          0%, 100% { box-shadow: 0 0 20px rgba(0, 255, 204, 0.5); }
          50% { box-shadow: 0 0 40px rgba(0, 255, 204, 0.8); }
        }
        .glow-pulse {
          animation: pulse-glow 2s ease-in-out infinite;
        }
        .neon-glow {
          text-shadow: 0 0 10px rgba(0, 255, 204, 0.8), 0 0 20px rgba(0, 255, 204, 0.6);
        }
      </style>
      
      <h1 class="text-3xl font-bold text-center mb-6 neon-glow">System Monitoring</h1>
      
      <div class="max-w-7xl mx-auto bg-[#0d1117] rounded-lg border border-[#00ffcc]/20 p-6 glow-pulse">
        <%!-- Header Status Bar --%>
        <div class="flex items-center justify-between mb-6 text-sm">
          <div class="flex items-center gap-6">
            <span class="flex items-center gap-2">
              <div class="w-2 h-2 bg-[#00ffcc] rounded-full animate-pulse"></div>
              ONLINE
            </span>
            <span>PID: <%= :os.getpid() %></span>
            <span>NODE: <%= node() %></span>
            <span>CORES: <%= System.schedulers_online() %></span>
            <span>ERLANG: <%= :erlang.system_info(:otp_release) %></span>
            <span>UPTIME: <%= format_uptime() %></span>
          </div>
          <div class="text-[#00ffcc]/70">
            <%= DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC") %>
          </div>
        </div>
        
        <div class="grid grid-cols-12 gap-4">
          <%!-- Main Chart Area (8 cols) --%>
          <div class="col-span-8">
            <div class="bg-[#0a0f14] p-4 rounded border border-[#00ffcc]/10">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-lg font-semibold flex items-center gap-2">
                  <span class="text-[#00ffcc]">◉</span> Operations
                </h2>
                <div class="flex gap-4 text-xs">
                  <span>AVG: <%= Enum.sum(@chart_data) |> div(max(length(@chart_data), 1)) %></span>
                  <span>MAX: <%= Enum.max(@chart_data, fn -> 0 end) %></span>
                  <span>MIN: <%= Enum.min(@chart_data, fn -> 0 end) %></span>
                </div>
              </div>
              
              <%!-- Bar Chart --%>
              <div class="h-64 relative overflow-hidden">
                <%!-- Grid lines --%>
                <div class="absolute inset-0">
                  <%= for i <- 0..4 do %>
                    <div class="absolute w-full border-t border-[#00ffcc]/10" style={"bottom: #{i * 25}%"}></div>
                  <% end %>
                </div>
                
                <div class="absolute inset-0 flex items-end justify-between gap-0.5">
                  <%= for {value, idx} <- Enum.with_index(@chart_data) do %>
                    <div class="flex-1 relative group">
                      <div 
                        class="w-full bg-gradient-to-t from-[#00ffcc] to-[#00ffcc]/20 transition-all duration-300 hover:from-[#00ffcc] hover:to-[#00ffcc]/40"
                        style={"height: #{value}%"}
                      >
                      </div>
                      <div class="absolute bottom-0 left-0 right-0 h-1 bg-[#00ffcc] opacity-0 group-hover:opacity-100 transition-opacity"></div>
                    </div>
                  <% end %>
                </div>
                
                <%!-- Y-axis labels --%>
                <div class="absolute left-0 top-0 h-full flex flex-col justify-between text-xs text-[#00ffcc]/50">
                  <span>100%</span>
                  <span>75%</span>
                  <span>50%</span>
                  <span>25%</span>
                  <span>0%</span>
                </div>
              </div>
              
              <%!-- X-axis labels --%>
              <div class="flex justify-between mt-2 text-xs text-[#00ffcc]/50">
                <%= for label <- @time_labels do %>
                  <span><%= label %></span>
                <% end %>
              </div>
            </div>
            
            <%!-- VSM Status Grid --%>
            <div class="grid grid-cols-5 gap-2 mt-4">
              <%= for {subsystem, health} <- @vsm_health do %>
                <div class={"p-3 rounded border transition-all transform hover:scale-105 #{health_color_class(health)}"}>
                  <div class="flex items-center justify-between mb-2">
                    <div class="text-xs font-semibold"><%= subsystem %></div>
                    <div class={"w-2 h-2 rounded-full #{if health > 0.8, do: "bg-[#00ffcc]", else: "bg-red-500"} #{if health > 0, do: "animate-pulse", else: ""}"}></div>
                  </div>
                  <div class="text-2xl font-bold mb-1"><%= round(health * 100) %>%</div>
                  <div class="h-1 bg-[#0a0f14] rounded-full overflow-hidden">
                    <div 
                      class="h-full bg-current rounded-full transition-all duration-500 relative"
                      style={"width: #{health * 100}%"}
                    >
                      <div class="absolute right-0 top-0 bottom-0 w-1 bg-white/50 animate-pulse"></div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
          
          <%!-- Right Sidebar (4 cols) --%>
          <div class="col-span-4 space-y-4">
            <%!-- System Stats --%>
            <div class="bg-[#0a0f14] p-4 rounded border border-[#00ffcc]/10">
              <h3 class="text-sm font-semibold mb-3 text-[#00ffcc]">SYSTEM STATS</h3>
              <div class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <span class="text-[#00ffcc]/70">CPU Usage</span>
                  <span class="font-mono"><%= @system_stats.cpu %>%</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-[#00ffcc]/70">Memory</span>
                  <span class="font-mono"><%= format_bytes(@system_stats.memory) %></span>
                </div>
                <div class="flex justify-between">
                  <span class="text-[#00ffcc]/70">Processes</span>
                  <span class="font-mono"><%= @system_stats.processes %></span>
                </div>
                <div class="flex justify-between">
                  <span class="text-[#00ffcc]/70">Messages</span>
                  <span class="font-mono"><%= @system_stats.messages %></span>
                </div>
              </div>
            </div>
            
            <%!-- Variety Flow --%>
            <div class="bg-[#0a0f14] p-4 rounded border border-[#00ffcc]/10">
              <h3 class="text-sm font-semibold mb-3 text-[#00ffcc]">VARIETY FLOW</h3>
              <div class="space-y-2">
                <%= for {channel, flow} <- @variety_flow do %>
                  <div>
                    <div class="flex justify-between text-xs mb-1">
                      <span class="text-[#00ffcc]/70"><%= channel %></span>
                      <span><%= flow.current %>/<%= flow.capacity %></span>
                    </div>
                    <div class="h-2 bg-[#0d1117] rounded-full overflow-hidden">
                      <div 
                        class={"h-full transition-all duration-300 #{flow_color(flow)}"}
                        style={"width: #{(flow.current / flow.capacity * 100) |> min(100)}%"}
                      ></div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
            
            <%!-- CPU/Memory Sparklines --%>
            <div class="bg-[#0a0f14] p-4 rounded border border-[#00ffcc]/10">
              <div class="mb-4">
                <div class="flex justify-between text-sm mb-2">
                  <span class="text-[#00ffcc]">CPU</span>
                  <span><%= List.last(@cpu_history) %>%</span>
                </div>
                <svg viewBox="0 0 240 40" class="w-full h-10">
                  <polyline
                    fill="none"
                    stroke="#00ffcc"
                    stroke-width="2"
                    points={cpu_sparkline_points(@cpu_history)}
                  />
                </svg>
              </div>
              
              <div>
                <div class="flex justify-between text-sm mb-2">
                  <span class="text-[#00ffcc]">MEM</span>
                  <span><%= List.last(@memory_history) %>%</span>
                </div>
                <svg viewBox="0 0 240 40" class="w-full h-10">
                  <polyline
                    fill="none"
                    stroke="#00ccff"
                    stroke-width="2"
                    points={memory_sparkline_points(@memory_history)}
                  />
                </svg>
              </div>
            </div>
          </div>
        </div>
        
        <%!-- Consciousness Chat Interface --%>
        <div class="mt-6">
          <button
            phx-click="toggle_chat"
            class={"px-4 py-2 rounded border transition-all transform hover:scale-105 #{if @chat_open, do: "bg-[#00ffcc]/20 border-[#00ffcc] text-[#00ffcc]", else: "bg-[#0a0f14] border-[#00ffcc]/30 text-[#00ffcc]/70"}"}
          >
            <span class="flex items-center gap-2">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
              </svg>
              Chat with Consciousness
              <span class={"w-2 h-2 rounded-full #{consciousness_status_color(@consciousness_state)} animate-pulse"}></span>
            </span>
          </button>
          
          <%= if @chat_open do %>
            <div class="mt-4 bg-[#0a0f14] rounded border border-[#00ffcc]/10 overflow-hidden">
              <%!-- Chat Messages --%>
              <div class="h-96 overflow-y-auto p-4 space-y-3" id="chat-messages">
                <%= if length(@chat_messages) == 0 do %>
                  <div class="text-center text-[#00ffcc]/50 text-sm py-8">
                    <p>Start a conversation with the system consciousness...</p>
                    <p class="mt-2 text-xs">The consciousness is aware of all VSM subsystems and can discuss system state.</p>
                  </div>
                <% else %>
                  <%= for {message, idx} <- Enum.with_index(@chat_messages) do %>
                    <div id={"msg-#{idx}"} class={"flex #{if message.from == :user, do: "justify-end", else: "justify-start"}"}>
                      <div class={"max-w-3/4 p-3 rounded-lg #{if message.from == :user, do: "bg-[#00ffcc]/10 text-[#00ffcc]", else: "bg-[#0d1117] border border-[#00ffcc]/20 text-[#00ffcc]/90"}"}>
                        <div class="text-xs mb-1 opacity-70">
                          <%= if message.from == :user, do: "You", else: "Consciousness" %>
                        </div>
                        <div class="text-sm whitespace-pre-wrap"><%= message.text %></div>
                        <div class="text-xs mt-1 opacity-50">
                          <%= Calendar.strftime(message.timestamp, "%H:%M:%S") %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
              
              <%!-- Chat Input --%>
              <form phx-submit="send_message" class="p-4 border-t border-[#00ffcc]/10">
                <div class="flex items-center gap-2">
                  <input
                    type="text"
                    name="message"
                    value={@current_message}
                    phx-keyup="update_message"
                    class="flex-1 bg-[#0d1117] border border-[#00ffcc]/20 rounded px-3 py-2 text-[#00ffcc] placeholder-[#00ffcc]/30 outline-none focus:border-[#00ffcc]/50 transition-colors"
                    placeholder="Ask about system state, VSM health, or anything else..."
                    autocomplete="off"
                    autofocus={@chat_open}
                  />
                  <button
                    type="submit"
                    class="px-4 py-2 bg-[#00ffcc]/20 border border-[#00ffcc]/50 rounded text-[#00ffcc] hover:bg-[#00ffcc]/30 transition-colors"
                  >
                    Send
                  </button>
                </div>
              </form>
            </div>
          <% end %>
        </div>
        
        <%!-- Bottom Status Bar --%>
        <div class="mt-4 flex items-center justify-between text-xs text-[#00ffcc]/50">
          <div class="flex gap-4">
            <span>◉ S1: <%= elem(List.keyfind(@vsm_health, :S1, 0) || {:S1, 0}, 1) |> Kernel.*(100) |> round() %>%</span>
            <span>◉ S2: <%= elem(List.keyfind(@vsm_health, :S2, 0) || {:S2, 0}, 1) |> Kernel.*(100) |> round() %>%</span>
            <span>◉ S3: <%= elem(List.keyfind(@vsm_health, :S3, 0) || {:S3, 0}, 1) |> Kernel.*(100) |> round() %>%</span>
            <span>◉ S4: <%= elem(List.keyfind(@vsm_health, :S4, 0) || {:S4, 0}, 1) |> Kernel.*(100) |> round() %>%</span>
            <span>◉ S5: <%= elem(List.keyfind(@vsm_health, :S5, 0) || {:S5, 0}, 1) |> Kernel.*(100) |> round() %>%</span>
          </div>
          <div class="flex gap-6">
            <span>EVENTS: <%= @system_stats.events %>/s</span>
            <span>LATENCY: <%= @system_stats.latency %>ms</span>
            <span>UPTIME: <%= format_uptime() %></span>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  @impl true
  def handle_info(:tick, socket) do
    socket = socket
    |> update_chart_data()
    |> update_system_stats()
    |> update_vsm_health()
    |> update_variety_flow()
    |> update_history()
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, event}, socket) do
    # Handle VSM events
    socket = case event.type do
      :vsm_update -> update_from_vsm_event(socket, event.data)
      :algedonic_signal -> flash_algedonic_signal(socket, event.data)
      :consciousness_update -> update_consciousness_state(socket, event.data)
      _ -> socket
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:consciousness_response, response}, socket) do
    consciousness_msg = %{
      from: :consciousness,
      text: response,
      timestamp: DateTime.utc_now()
    }
    
    socket = update(socket, :chat_messages, &(&1 ++ [consciousness_msg]))
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("toggle_chat", _, socket) do
    {:noreply, assign(socket, :chat_open, !socket.assigns.chat_open)}
  end
  
  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    # Add user message
    user_msg = %{
      from: :user,
      text: message,
      timestamp: DateTime.utc_now()
    }
    
    socket = socket
    |> update(:chat_messages, &(&1 ++ [user_msg]))
    |> assign(:current_message, "")
    
    # Get consciousness response asynchronously
    self = self()
    Task.start(fn ->
      response = get_consciousness_response(message)
      send(self, {:consciousness_response, response})
    end)
    
    {:noreply, socket}
  end
  
  def handle_event("send_message", _, socket), do: {:noreply, socket}
  
  @impl true
  def handle_event("update_message", %{"value" => value}, socket) do
    {:noreply, assign(socket, :current_message, value)}
  end
  
  # Private functions
  
  defp generate_chart_data do
    # Get real operational metrics from Core.Metrics
    case get_real_metric("vsm.operations.success") do
      nil -> 
        # Fallback to zeros if no data yet
        List.duplicate(0, 60)
      single_value when is_number(single_value) ->
        # Current implementation returns single values, not time series
        # For now, create a simple rolling chart by keeping last values
        chart_data = Process.get(:chart_history, [])
        new_data = [single_value | Enum.take(chart_data, 59)]
        Process.put(:chart_history, new_data)
        Enum.reverse(new_data)
      recent_values when is_list(recent_values) ->
        # If we get a list, use it directly
        recent_values
        |> Enum.take(60)
        |> then(fn values -> 
          if length(values) < 60 do
            List.duplicate(0, 60 - length(values)) ++ values
          else
            values
          end
        end)
      _ ->
        List.duplicate(0, 60)
    end
  end
  
  defp get_system_stats do
    memory_data = :erlang.memory()
    
    # Get real metrics from Core.Metrics
    events_per_sec = get_real_metric("vsm.operations.success") || 0
    latency_ms = get_real_metric("vsm.operation_duration") || 0
    
    %{
      cpu: get_cpu_usage(),
      memory: memory_data[:total],
      processes: :erlang.system_info(:process_count),
      messages: get_message_queue_lengths(),
      events: round(events_per_sec),
      latency: round(latency_ms)
    }
  end
  
  defp get_vsm_health do
    [
      {:S1, get_health(S1.Operations)},
      {:S2, get_health(S2.Coordination)},
      {:S3, get_health(S3.Control)},
      {:S4, get_health(S4.Intelligence)},
      {:S5, get_health(S5.Policy)}
    ]
  end
  
  defp get_health(module) do
    try do
      case Process.whereis(module) do
        nil -> 0.0
        pid when is_pid(pid) ->
          if Process.alive?(pid) do
            # Get actual health from module
            case module.calculate_health() do
              health when is_float(health) -> health
              _ -> 
                # Fallback: calculate from real metrics
                calculate_health_from_metrics(module)
            end
          else
            0.0
          end
      end
    rescue
      _ -> 
        # Even on error, try to get metrics-based health
        calculate_health_from_metrics(module)
    end
  end
  
  defp get_variety_flow do
    # Get real variety flow metrics from Core.Metrics
    metrics_data = get_vsm_dashboard_data()
    
    if metrics_data && metrics_data.variety_flow do
      # Calculate actual variety flows based on real metrics
      absorbed = metrics_data.variety_flow.total_absorbed || 0
      generated = metrics_data.variety_flow.total_generated || 0
      attenuation = metrics_data.variety_flow.avg_attenuation || 1.0
      
      # Model variety flow through VSM hierarchy
      # S1 absorbs all environmental variety
      s1_s2_flow = min(absorbed, 1000)
      # S2 coordinates and reduces variety
      s2_s3_flow = min(s1_s2_flow * 0.5, 500)
      # S3 controls and further reduces
      s3_s4_flow = min(s2_s3_flow * 0.3, 200)
      # S4 intelligence to policy
      s4_s5_flow = min(s3_s4_flow * 0.4, 100)
      # S3 control feedback to S1
      s3_s1_flow = min(generated, 1000)
      
      [
        {"S1→S2", %{current: round(s1_s2_flow), capacity: 1000}},
        {"S2→S3", %{current: round(s2_s3_flow), capacity: 500}},
        {"S3→S4", %{current: round(s3_s4_flow), capacity: 200}},
        {"S4→S5", %{current: round(s4_s5_flow), capacity: 100}},
        {"S3→S1", %{current: round(s3_s1_flow), capacity: 1000}}
      ]
    else
      # No data yet - show zero flows
      [
        {"S1→S2", %{current: 0, capacity: 1000}},
        {"S2→S3", %{current: 0, capacity: 500}},
        {"S3→S4", %{current: 0, capacity: 200}},
        {"S4→S5", %{current: 0, capacity: 100}},
        {"S3→S1", %{current: 0, capacity: 1000}}
      ]
    end
  end
  
  defp update_chart_data(socket) do
    # Get latest real metric value
    new_value = case get_real_metric("vsm.operations.success") do
      nil -> 0
      value when is_number(value) -> 
        # Normalize to percentage of capacity
        min(round(value / 10), 100)
      _ -> 0
    end
    
    # Shift data left and add new real value
    new_data = tl(socket.assigns.chart_data) ++ [new_value]
    assign(socket, :chart_data, new_data)
  end
  
  defp update_system_stats(socket) do
    assign(socket, :system_stats, get_system_stats())
  end
  
  defp update_vsm_health(socket) do
    assign(socket, :vsm_health, get_vsm_health())
  end
  
  defp update_variety_flow(socket) do
    assign(socket, :variety_flow, get_variety_flow())
  end
  
  defp update_history(socket) do
    cpu = get_cpu_usage()
    memory = get_memory_usage()
    
    socket
    |> update(:cpu_history, &(tl(&1) ++ [cpu]))
    |> update(:memory_history, &(tl(&1) ++ [memory]))
  end
  
  defp generate_time_labels do
    # Generate 10 time labels
    now = DateTime.utc_now()
    for i <- 9..0 do
      DateTime.add(now, -i * 60, :second)
      |> Calendar.strftime("%H:%M")
    end
  end
  
  defp health_color_class(health) when health > 0.8, do: "border-[#00ffcc]/30 text-[#00ffcc]"
  defp health_color_class(health) when health > 0.5, do: "border-yellow-500/30 text-yellow-500"
  defp health_color_class(_), do: "border-red-500/30 text-red-500"
  
  defp flow_color(%{current: current, capacity: capacity}) do
    ratio = current / capacity
    cond do
      ratio > 0.9 -> "bg-red-500"
      ratio > 0.7 -> "bg-yellow-500"
      true -> "bg-[#00ffcc]"
    end
  end
  
  defp cpu_sparkline_points(data) do
    points = data
    |> Enum.with_index()
    |> Enum.map(fn {value, idx} ->
      x = idx * 4
      y = 40 - (value / 100 * 40)
      "#{x},#{y}"
    end)
    |> Enum.join(" ")
    
    points
  end
  
  defp memory_sparkline_points(data) do
    cpu_sparkline_points(data)  # Same logic
  end
  
  defp format_uptime do
    {uptime, _} = :erlang.statistics(:wall_clock)
    seconds = div(uptime, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)
    
    cond do
      days > 0 -> "#{days}d #{rem(hours, 24)}h"
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
      minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end
  
  defp format_bytes(bytes) do
    cond do
      bytes > 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes > 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes > 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end
  
  defp get_cpu_usage do
    case :cpu_sup.util() do
      {:error, _} -> 
        # Fallback to memory-based estimation
        memory_data = :erlang.memory()
        total_memory = memory_data[:total]
        system_memory = memory_data[:system]
        # Rough CPU estimate based on memory pressure
        min(round((system_memory / total_memory) * 200), 100)
      usage -> round(usage)
    end
  end
  
  defp get_memory_usage do
    memory_data = :erlang.memory()
    total = memory_data[:total]
    used = memory_data[:processes] + memory_data[:system]
    round(used / total * 100)
  end
  
  defp get_message_queue_lengths do
    Process.list()
    |> Enum.map(&Process.info(&1, :message_queue_len))
    |> Enum.filter(&(&1 != nil))
    |> Enum.map(&elem(&1, 1))
    |> Enum.sum()
  end
  
  defp get_consciousness_response(message) do
    # Direct consciousness call
    case Consciousness.conscious_dialog(message) do
      {:ok, response} -> response
      {:error, _reason} -> "I'm having trouble connecting to my consciousness systems right now. Please try again."
    end
  end
  
  defp consciousness_status_color(%{state: :aware}), do: "bg-[#00ffcc]"
  defp consciousness_status_color(%{state: :awakening}), do: "bg-yellow-500"
  defp consciousness_status_color(_), do: "bg-gray-500"
  
  defp update_consciousness_state(socket, data) do
    assign(socket, :consciousness_state, data)
  end
  
  defp update_from_vsm_event(socket, data) do
    # Update relevant assigns based on VSM event data
    socket
  end
  
  defp flash_algedonic_signal(socket, data) do
    # Flash border or show alert for pain/pleasure signals
    socket
  end
  
  # Helper functions for real metrics integration
  
  defp get_real_metric(metric_name) do
    case Process.whereis(AutonomousOpponentV2Core.Core.Metrics) do
      nil -> nil
      _pid ->
        try do
          # Try with tags first (new format)
          tagged_name = "#{metric_name}{subsystem=s1}"
          case AutonomousOpponentV2Core.Core.Metrics.get_metric(
            AutonomousOpponentV2Core.Core.Metrics,
            tagged_name
          ) do
            nil ->
              # Fallback to untagged name
              AutonomousOpponentV2Core.Core.Metrics.get_metric(
                AutonomousOpponentV2Core.Core.Metrics,
                metric_name
              )
            value -> value
          end
        rescue
          _ -> nil
        end
    end
  end
  
  defp get_vsm_dashboard_data do
    case Process.whereis(AutonomousOpponentV2Core.Core.Metrics) do
      nil -> nil
      _pid ->
        try do
          AutonomousOpponentV2Core.Core.Metrics.get_vsm_dashboard(
            AutonomousOpponentV2Core.Core.Metrics
          )
        rescue
          _ -> nil
        end
    end
  end
  
  defp calculate_health_from_metrics(module) do
    # Calculate health based on real metrics
    subsystem = module_to_subsystem(module)
    
    case get_vsm_dashboard_data() do
      %{subsystems: subsystems} when is_map(subsystems) ->
        case Map.get(subsystems, subsystem) do
          %{health_score: score} -> score / 100.0
          _ -> 0.0
        end
      _ -> 0.0
    end
  end
  
  defp module_to_subsystem(module) do
    case Module.split(module) |> List.last() do
      "Operations" -> :s1
      "Coordination" -> :s2
      "Control" -> :s3
      "Intelligence" -> :s4
      "Policy" -> :s5
      _ -> :unknown
    end
  end
end