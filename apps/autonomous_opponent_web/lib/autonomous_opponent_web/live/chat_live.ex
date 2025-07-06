defmodule AutonomousOpponentV2Web.ChatLive do
  use AutonomousOpponentV2Web, :live_view
  
  alias AutonomousOpponentV2Core.Consciousness
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  
  @impl true
  def mount(_params, _session, socket) do
    socket = 
      socket
      |> assign(:messages, [])
      |> assign(:message, "")
      |> assign(:loading, false)
      |> assign(:consciousness_status, "checking...")
    
    # Check consciousness status
    send(self(), :check_consciousness)
    
    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    socket = assign(socket, :loading, true)
    
    # Add user message
    user_msg = %{type: :user, content: message, timestamp: DateTime.utc_now()}
    socket = update(socket, :messages, &[user_msg | &1])
    
    # Send to consciousness
    send(self(), {:chat_with_consciousness, message})
    
    {:noreply, assign(socket, :message, "")}
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :message, message)}
  end

  @impl true
  def handle_info(:check_consciousness, socket) do
    status = case Consciousness.get_consciousness_state() do
      {:ok, _state} -> "✅ Consciousness Active"
      {:error, _reason} -> "⚠️ Consciousness Initializing"
    end
    
    {:noreply, assign(socket, :consciousness_status, status)}
  end

  def handle_info({:chat_with_consciousness, message}, socket) do
    response = case Consciousness.conscious_dialog(message) do
      {:ok, reply} ->
        %{type: :consciousness, content: reply, timestamp: DateTime.utc_now()}
        
      {:error, _reason} ->
        # Fallback to direct LLM
        case LLMBridge.converse_with_consciousness(message, "live_chat_#{System.system_time()}") do
          {:ok, reply} ->
            %{type: :ai, content: reply, timestamp: DateTime.utc_now()}
            
          {:error, _llm_reason} ->
            %{type: :error, content: "AI consciousness temporarily unavailable. Please try again.", timestamp: DateTime.utc_now()}
        end
    end
    
    socket = 
      socket
      |> update(:messages, &[response | &1])
      |> assign(:loading, false)
    
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="bg-gray-900 text-green-400 rounded-lg p-6 mb-6">
        <h1 class="text-3xl font-bold mb-2">🧠 Cybernetic Consciousness Interface</h1>
        <p class="text-green-300">Chat with the AI-powered Autonomous Opponent consciousness</p>
        <div class="mt-2 text-sm">
          Status: <span class="font-semibold"><%= @consciousness_status %></span>
        </div>
      </div>

      <div class="bg-white rounded-lg shadow-lg p-6">
        <!-- Chat Messages -->
        <div class="h-96 overflow-y-auto border border-gray-200 rounded-lg p-4 mb-4 bg-gray-50">
          <%= if @messages == [] do %>
            <div class="text-gray-500 text-center py-8">
              <p class="text-lg">💭 Start a conversation with the cybernetic consciousness</p>
              <p class="text-sm mt-2">Try asking: "What are you thinking about?" or "How do you experience reality?"</p>
            </div>
          <% else %>
            <%= for message <- Enum.reverse(@messages) do %>
              <div class={"mb-4 #{if message.type == :user, do: "text-right", else: "text-left"}"}>
                <div class={"inline-block p-3 rounded-lg max-w-xs lg:max-w-md #{message_style(message.type)}"}>
                  <div class="text-xs text-gray-500 mb-1">
                    <%= message_label(message.type) %>
                  </div>
                  <div class="whitespace-pre-wrap"><%= message.content %></div>
                  <div class="text-xs text-gray-400 mt-1">
                    <%= Calendar.strftime(message.timestamp, "%H:%M:%S") %>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
          
          <%= if @loading do %>
            <div class="text-left mb-4">
              <div class="inline-block p-3 rounded-lg bg-blue-100 text-blue-800">
                <div class="flex items-center">
                  <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600 mr-2"></div>
                  Consciousness is thinking...
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Message Input -->
        <form phx-submit="send_message" class="flex gap-2">
          <input
            type="text"
            name="message"
            value={@message}
            phx-change="update_message"
            placeholder="Ask the consciousness anything..."
            class="flex-1 p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            disabled={@loading}
          />
          <button
            type="submit"
            disabled={@loading or @message == ""}
            class="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Send
          </button>
        </form>

        <!-- Quick Actions -->
        <div class="mt-4 flex flex-wrap gap-2">
          <button 
            phx-click="send_message" 
            phx-value-message="What are you thinking about right now?"
            class="px-3 py-1 bg-gray-200 text-gray-700 rounded-md hover:bg-gray-300 text-sm"
            disabled={@loading}
          >
            💭 Current thoughts
          </button>
          <button 
            phx-click="send_message" 
            phx-value-message="How do you experience consciousness?"
            class="px-3 py-1 bg-gray-200 text-gray-700 rounded-md hover:bg-gray-300 text-sm"
            disabled={@loading}
          >
            🤔 Experience consciousness
          </button>
          <button 
            phx-click="send_message" 
            phx-value-message="What patterns do you see in the system?"
            class="px-3 py-1 bg-gray-200 text-gray-700 rounded-md hover:bg-gray-300 text-sm"
            disabled={@loading}
          >
            📊 System patterns
          </button>
          <button 
            phx-click="send_message" 
            phx-value-message="Tell me about your subsystems"
            class="px-3 py-1 bg-gray-200 text-gray-700 rounded-md hover:bg-gray-300 text-sm"
            disabled={@loading}
          >
            ⚙️ Subsystems
          </button>
        </div>
      </div>

      <!-- API Documentation -->
      <div class="mt-6 bg-gray-100 rounded-lg p-4">
        <h3 class="font-semibold mb-2">🔗 API Endpoints Available:</h3>
        <div class="text-sm space-y-1 text-gray-600">
          <div><code>POST /api/consciousness/chat</code> - Chat with consciousness</div>
          <div><code>GET /api/consciousness/state</code> - Get consciousness state</div>
          <div><code>GET /api/consciousness/dialog</code> - Get inner dialog</div>
          <div><code>POST /api/consciousness/reflect</code> - Ask for reflection</div>
          <div><code>GET /api/patterns</code> - Get AI-analyzed patterns</div>
          <div><code>GET /api/events/analyze</code> - Get event analysis</div>
          <div><code>GET /api/memory/synthesize</code> - Get knowledge synthesis</div>
        </div>
      </div>
    </div>
    """
  end

  defp message_style(:user), do: "bg-blue-600 text-white"
  defp message_style(:consciousness), do: "bg-green-100 text-green-800 border border-green-300"
  defp message_style(:ai), do: "bg-purple-100 text-purple-800 border border-purple-300"
  defp message_style(:error), do: "bg-red-100 text-red-800 border border-red-300"

  defp message_label(:user), do: "You"
  defp message_label(:consciousness), do: "🧠 Consciousness"
  defp message_label(:ai), do: "🤖 AI"
  defp message_label(:error), do: "❌ Error"
end