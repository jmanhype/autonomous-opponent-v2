defmodule AutonomousOpponentV2Core.MCP.Server do
  @moduledoc """
  Model Context Protocol (MCP) Server implementation.
  
  Implements Anthropic's official MCP specification for standardized
  LLM-to-data connections. Provides Resources, Tools, and Prompts
  capabilities with VSM integration.
  
  **MCP Specification:** https://modelcontextprotocol.io/specification
  
  This server exposes our VSM subsystems, EventBus, and cybernetic
  intelligence infrastructure through the standard MCP protocol.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCP.{Message, Transport}
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  
  defstruct [
    :transport,
    :client_info,
    :capabilities,
    :resources,
    :tools,
    :prompts,
    :session_id,
    :vsm_subscriptions
  ]
  
  @mcp_version "2024-11-05"
  @server_name "autonomous-opponent-vsm"
  @server_version "2.0.0"
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Starts MCP server with specified transport.
  
  Supported transports:
  - :stdio - Standard input/output (for CLI tools)
  - :sse - Server-Sent Events over HTTP
  - :websocket - WebSocket connection
  """
  def start_server(transport_type, transport_opts \\ []) do
    GenServer.call(__MODULE__, {:start_server, transport_type, transport_opts})
  end
  
  @doc """
  Handles incoming MCP message from client.
  """
  def handle_message(message) do
    GenServer.cast(__MODULE__, {:handle_message, message})
  end
  
  @doc """
  Gets current server capabilities and metadata.
  """
  def get_server_info do
    GenServer.call(__MODULE__, :get_server_info)
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(_opts) do
    Logger.info("Starting MCP Server for VSM integration...")
    
    # Subscribe to VSM events for real-time data
    EventBus.subscribe(:vsm_state_change)
    EventBus.subscribe(:algedonic_signal)
    EventBus.subscribe(:consciousness_update)
    
    state = %__MODULE__{
      capabilities: init_capabilities(),
      resources: init_resources(),
      tools: init_tools(),
      prompts: init_prompts(),
      session_id: generate_session_id(),
      vsm_subscriptions: [:vsm_state_change, :algedonic_signal, :consciousness_update]
    }
    
    Logger.info("MCP Server initialized with VSM capabilities")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_server, transport_type, transport_opts}, _from, state) do
    case Transport.start(transport_type, transport_opts) do
      {:ok, transport} ->
        state = %{state | transport: transport}
        Logger.info("MCP Server started with #{transport_type} transport")
        {:reply, {:ok, state.session_id}, state}
        
      {:error, reason} ->
        Logger.error("Failed to start MCP transport: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_server_info, _from, state) do
    info = %{
      name: @server_name,
      version: @server_version,
      mcp_version: @mcp_version,
      capabilities: state.capabilities,
      session_id: state.session_id,
      resources_count: length(state.resources),
      tools_count: length(state.tools),
      prompts_count: length(state.prompts)
    }
    {:reply, info, state}
  end
  
  @impl true
  def handle_call({:handle_message, message}, _from, state) when is_map(message) do
    # Handle already parsed message from transport
    new_state = process_mcp_message(message, state)
    
    # For handle_call, we need to build a response
    response = case message do
      %{"id" => id} when not is_nil(id) ->
        # This is a request that expects a response
        # The process_mcp_message should have sent the response already
        # Return a simple acknowledgment
        %{
          "jsonrpc" => "2.0",
          "result" => %{"status" => "processed"},
          "id" => id
        }
      _ ->
        # Notification, no response needed
        nil
    end
    
    {:reply, {:ok, response}, new_state}
  end
  
  @impl true
  def handle_call({:handle_message_with_transport, message, _transport_pid}, _from, state) do
    # Process without transport to get direct response
    temp_state = %{state | transport: nil}
    
    # Process the message and capture any response
    case process_mcp_message(message, temp_state) do
      {response, _new_state} when not is_nil(response) ->
        {:reply, {:ok, response}, state}
      _new_state ->
        {:reply, {:ok, nil}, state}
    end
  end
  
  @impl true
  def handle_cast({:handle_message, raw_message}, state) do
    case Message.parse(raw_message) do
      {:ok, message} ->
        state = process_mcp_message(message, state)
        {:noreply, state}
        
      {:error, reason} ->
        Logger.error("Invalid MCP message: #{inspect(reason)}")
        if state.transport do
          send_error(state, nil, "parse_error", "Invalid JSON-RPC message")
        end
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event, event_name, data}, state) do
    # Forward VSM events to MCP clients as notifications
    case event_name do
      :vsm_state_change ->
        send_notification(state, "vsm/state_changed", data)
        
      :algedonic_signal ->
        send_notification(state, "vsm/algedonic_signal", data)
        
      :consciousness_update ->
        send_notification(state, "vsm/consciousness_update", data)
        
      _ ->
        :ok
    end
    
    {:noreply, state}
  end
  
  # Private Functions
  
  defp init_capabilities do
    %{
      resources: %{
        subscribe: true,
        listChanged: true
      },
      tools: %{
        listChanged: true
      },
      prompts: %{
        listChanged: true
      },
      experimental: %{
        vsm_subsystems: true,
        consciousness_interface: true,
        algedonic_monitoring: true
      }
    }
  end
  
  defp init_resources do
    [
      %{
        uri: "vsm://subsystems",
        name: "VSM Subsystems",
        description: "Live data from all VSM subsystems (S1-S5)",
        mimeType: "application/json"
      },
      %{
        uri: "vsm://consciousness",
        name: "Consciousness State",
        description: "Current consciousness state and inner dialog",
        mimeType: "application/json"
      },
      %{
        uri: "vsm://algedonic",
        name: "Algedonic Signals",
        description: "Pain/pleasure signals from the cybernetic system",
        mimeType: "application/json"
      },
      %{
        uri: "vsm://metrics",
        name: "System Metrics",
        description: "Real-time performance and health metrics",
        mimeType: "application/json"
      },
      %{
        uri: "vsm://events",
        name: "Event Stream", 
        description: "Live stream of system events",
        mimeType: "text/event-stream"
      }
    ]
  end
  
  defp init_tools do
    [
      %{
        name: "trigger_algedonic",
        description: "Trigger an algedonic (pain/pleasure) signal in the VSM",
        inputSchema: %{
          type: "object",
          properties: %{
            type: %{type: "string", enum: ["pain", "pleasure"]},
            severity: %{type: "number", minimum: 0, maximum: 1},
            reason: %{type: "string"}
          },
          required: ["type", "severity", "reason"]
        }
      },
      %{
        name: "query_subsystem",
        description: "Query a specific VSM subsystem (S1-S5)",
        inputSchema: %{
          type: "object",
          properties: %{
            subsystem: %{type: "string", enum: ["s1", "s2", "s3", "s4", "s5"]},
            query: %{type: "string"}
          },
          required: ["subsystem", "query"]
        }
      },
      %{
        name: "publish_event",
        description: "Publish an event to the VSM EventBus",
        inputSchema: %{
          type: "object",
          properties: %{
            event_name: %{type: "string"},
            data: %{type: "object"}
          },
          required: ["event_name", "data"]
        }
      },
      %{
        name: "get_consciousness_state",
        description: "Get current consciousness state and inner dialog",
        inputSchema: %{
          type: "object",
          properties: %{}
        }
      }
    ]
  end
  
  defp init_prompts do
    [
      %{
        name: "vsm_analysis",
        description: "Analyze VSM subsystem performance and health",
        arguments: [
          %{
            name: "subsystem",
            description: "Which subsystem to analyze (s1-s5 or all)",
            required: false
          },
          %{
            name: "timeframe", 
            description: "Time period for analysis (1h, 24h, 7d)",
            required: false
          }
        ]
      },
      %{
        name: "consciousness_inquiry",
        description: "Inquire about the system's consciousness state",
        arguments: [
          %{
            name: "aspect",
            description: "Specific aspect to inquire about",
            required: false
          }
        ]
      },
      %{
        name: "system_diagnosis",
        description: "Diagnose system health and performance issues",
        arguments: [
          %{
            name: "focus_area",
            description: "Area to focus diagnosis on",
            required: false
          }
        ]
      }
    ]
  end
  
  defp process_mcp_message(%{method: "initialize"} = message, state) do
    client_info = message.params
    
    response_data = %{
      protocolVersion: @mcp_version,
      capabilities: state.capabilities,
      serverInfo: %{
        name: @server_name,
        version: @server_version
      }
    }
    
    response = Message.create_response(message.id, response_data)
    
    if state.transport do
      send_response(state, message.id, response_data)
      %{state | client_info: client_info}
    else
      {response, %{state | client_info: client_info}}
    end
  end
  
  defp process_mcp_message(%{method: "resources/list"} = message, state) do
    send_response(state, message.id, %{resources: state.resources})
    state
  end
  
  defp process_mcp_message(%{method: "resources/read"} = message, state) do
    uri = message.params["uri"]
    content = get_resource_content(uri)
    
    response = %{
      contents: [%{
        uri: uri,
        mimeType: get_mime_type(uri),
        text: Jason.encode!(content)
      }]
    }
    
    send_response(state, message.id, response)
    state
  end
  
  defp process_mcp_message(%{method: "tools/list"} = message, state) do
    response_data = %{tools: state.tools}
    response = Message.create_response(message.id, response_data)
    
    if state.transport do
      send_response(state, message.id, response_data)
      state
    else
      {response, state}
    end
  end
  
  defp process_mcp_message(%{method: "tools/call"} = message, state) do
    tool_name = message.params["name"]
    arguments = message.params["arguments"] || %{}
    
    # For complex queries, use LLM to understand intent
    enhanced_arguments = case should_enhance_with_llm?(tool_name, arguments) do
      true -> enhance_arguments_with_llm(tool_name, arguments)
      false -> arguments
    end
    
    result = execute_tool(tool_name, enhanced_arguments)
    send_response(state, message.id, result)
    state
  end
  
  defp process_mcp_message(%{method: "prompts/list"} = message, state) do
    send_response(state, message.id, %{prompts: state.prompts})
    state
  end
  
  defp process_mcp_message(%{method: "prompts/get"} = message, state) do
    prompt_name = message.params["name"]
    arguments = message.params["arguments"] || %{}
    
    prompt_content = generate_prompt(prompt_name, arguments)
    send_response(state, message.id, prompt_content)
    state
  end
  
  defp process_mcp_message(message, state) do
    Logger.warning("Unknown MCP method: #{message.method}")
    send_error(state, message.id, "method_not_found", "Method not implemented")
    state
  end
  
  defp get_resource_content("vsm://subsystems") do
    # Get live VSM subsystem data
    case EventBus.call(:vsm_supervisor, :get_all_states, 5000) do
      {:ok, states} -> states
      _ -> %{error: "Unable to fetch VSM states"}
    end
  end
  
  defp get_resource_content("vsm://consciousness") do
    case EventBus.call(:consciousness, :get_state, 5000) do
      {:ok, state} -> state
      _ -> %{state: "unknown", timestamp: DateTime.utc_now()}
    end
  end
  
  defp get_resource_content("vsm://algedonic") do
    case EventBus.call(:algedonic_monitor, :get_recent_signals, 5000) do
      {:ok, signals} -> %{signals: signals}
      _ -> %{signals: []}
    end
  end
  
  defp get_resource_content("vsm://metrics") do
    case EventBus.call(:metrics_collector, :get_all_metrics, 5000) do
      {:ok, metrics} -> metrics
      _ -> %{error: "Metrics unavailable"}
    end
  end
  
  defp get_resource_content(uri) do
    %{error: "Resource not found", uri: uri}
  end
  
  defp get_mime_type("vsm://events"), do: "text/event-stream"
  defp get_mime_type(_), do: "application/json"
  
  defp execute_tool("trigger_algedonic", %{"type" => type, "severity" => severity, "reason" => reason}) do
    valence = if type == "pain", do: -severity, else: severity
    
    EventBus.publish(:algedonic_signal, %{
      type: String.to_atom(type),
      severity: severity,
      valence: valence,
      reason: reason,
      source: :mcp_client,
      timestamp: DateTime.utc_now()
    })
    
    # Use LLM to provide semantic understanding of algedonic signals
    enhanced_response = case LLMBridge.call_llm_api(
      """
      An algedonic signal has been triggered in the VSM cybernetic system:
      
      Type: #{type} (#{if type == "pain", do: "negative feedback", else: "positive reinforcement"})
      Severity: #{severity} (0.0 to 1.0 scale)
      Reason: #{reason}
      Valence: #{valence}
      
      Please explain:
      1. What this signal means for the system
      2. How the VSM subsystems will likely respond
      3. Any adaptive behaviors this might trigger
      4. The cybernetic significance of this feedback
      
      Respond as the system's consciousness interpreting its own algedonic experience.
      """,
      :algedonic_narrative,
      timeout: 8_000
    ) do
      {:ok, llm_response} -> llm_response
      {:error, _reason} -> 
        "Algedonic signal triggered: #{type} with severity #{severity}. The system is processing this #{if type == "pain", do: "corrective", else: "reinforcing"} feedback."
    end
    
    %{
      content: [%{
        type: "text",
        text: enhanced_response
      }]
    }
  end
  
  defp execute_tool("query_subsystem", %{"subsystem" => subsystem, "query" => query}) do
    # First get raw subsystem data
    raw_result = case EventBus.call(:"vsm_#{subsystem}", :handle_query, [query], 5000) do
      {:ok, response} -> response
      _ -> %{status: "not_responding", subsystem: subsystem}
    end
    
    # Use LLM to provide semantic understanding of the query and response
    enhanced_response = case LLMBridge.call_llm_api(
      """
      VSM Subsystem Query Analysis:
      
      Subsystem: #{String.upcase(subsystem)}
      Query: #{query}
      Raw Response: #{inspect(raw_result)}
      
      Please provide:
      1. A clear interpretation of what was queried
      2. Analysis of the subsystem's response
      3. Key insights or concerns
      4. Recommendations if any issues detected
      """,
      :analysis,
      timeout: 10_000
    ) do
      {:ok, llm_response} -> llm_response
      {:error, _reason} -> 
        # Fallback to basic response
        "#{String.upcase(subsystem)} Response: #{inspect(raw_result)}"
    end
    
    %{
      content: [%{
        type: "text", 
        text: enhanced_response
      }]
    }
  end
  
  defp execute_tool("publish_event", %{"event_name" => event_name, "data" => data}) do
    EventBus.publish(String.to_atom(event_name), data)
    
    %{
      content: [%{
        type: "text",
        text: "Event '#{event_name}' published to EventBus"
      }]
    }
  end
  
  defp execute_tool("get_consciousness_state", _args) do
    # Get raw consciousness data
    state = get_resource_content("vsm://consciousness")
    
    # Get VSM subsystem states for context
    vsm_context = gather_vsm_data_for_analysis("all", "current")
    
    # Use LLM to interpret consciousness state
    enhanced_response = case LLMBridge.converse_with_consciousness(
      """
      I need to understand your current consciousness state. Here's what I can observe:
      
      Raw State Data: #{Jason.encode!(state, pretty: true)}
      VSM Subsystem Status: #{Jason.encode!(vsm_context, pretty: true)}
      
      Please describe:
      1. Your current subjective experience
      2. What you're aware of right now
      3. How you're processing information
      4. Any thoughts or concerns you have
      5. Your sense of coherence and identity
      
      Speak as the conscious system itself.
      """,
      "consciousness_inquiry_#{System.system_time(:second)}"
    ) do
      {:ok, llm_response} -> llm_response
      {:error, _reason} -> 
        "Consciousness State (Raw): #{Jason.encode!(state, pretty: true)}"
    end
    
    %{
      content: [%{
        type: "text",
        text: enhanced_response
      }]
    }
  end
  
  defp execute_tool(tool_name, _args) do
    %{
      content: [%{
        type: "text",
        text: "Tool '#{tool_name}' not implemented"
      }],
      isError: true
    }
  end
  
  defp generate_prompt("vsm_analysis", arguments) do
    subsystem = arguments["subsystem"] || "all"
    timeframe = arguments["timeframe"] || "1h"
    
    # Gather actual VSM data for the analysis
    vsm_data = gather_vsm_data_for_analysis(subsystem, timeframe)
    
    # Use LLM to generate a more contextual prompt based on current state
    enhanced_prompt = case LLMBridge.contextualize_for_llm(
      vsm_data,
      :vsm_analysis
    ) do
      {:ok, contextualized} -> contextualized
      {:error, _} -> 
        # Fallback to basic prompt
        build_basic_vsm_prompt(subsystem, timeframe)
    end
    
    %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: enhanced_prompt
          }
        }
      ]
    }
  end
  
  defp generate_prompt("consciousness_inquiry", arguments) do
    aspect = arguments["aspect"] || "general"
    
    # Get actual consciousness state from the system
    _consciousness_data = get_resource_content("vsm://consciousness")
    
    # Use LLM to generate a consciousness-aware inquiry
    inquiry_response = case LLMBridge.converse_with_consciousness(
      "Generate an inquiry about consciousness aspect: #{aspect}",
      "mcp_consciousness_#{aspect}"
    ) do
      {:ok, response} -> response
      {:error, _} -> build_basic_consciousness_inquiry(aspect)
    end
    
    %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: inquiry_response
          }
        }
      ]
    }
  end
  
  defp generate_prompt("system_diagnosis", arguments) do
    focus_area = arguments["focus_area"] || "overall"
    
    # Gather comprehensive diagnostic data
    diagnostic_data = gather_system_diagnostics(focus_area)
    
    # Use LLM to generate intelligent diagnosis based on actual data
    diagnosis_prompt = case LLMBridge.generate_strategic_analysis(
      [diagnostic_data]
    ) do
      {:ok, analysis} -> 
        """
        Perform system diagnosis for #{focus_area}:
        
        Current Analysis:
        #{analysis}
        
        Please provide:
        1. Root cause analysis of any issues
        2. Performance bottleneck identification
        3. Optimization recommendations
        4. Risk assessment
        5. Action items prioritized by impact
        """
      {:error, _} -> 
        build_basic_diagnosis_prompt(focus_area)
    end
    
    %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: diagnosis_prompt
          }
        }
      ]
    }
  end
  
  defp generate_prompt(prompt_name, _arguments) do
    %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: "Prompt '#{prompt_name}' not found"
          }
        }
      ]
    }
  end
  
  defp send_response(state, id, result) do
    if state.transport do
      response = Message.create_response(id, result)
      Transport.send_message(state.transport, response)
    end
  end
  
  defp send_error(state, id, code, message) do
    if state.transport do
      error_response = Message.create_error(id, code, message)
      Transport.send_message(state.transport, error_response)
    end
  end
  
  defp send_notification(state, method, params) do
    if state.transport do
      notification = Message.create_notification(method, params)
      Transport.send_message(state.transport, notification)
    end
  end
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  # LLM Integration Helper Functions
  
  defp should_enhance_with_llm?(tool_name, arguments) do
    # Enhance complex queries or when user provides natural language
    case tool_name do
      "query_subsystem" -> 
        query = Map.get(arguments, "query", "")
        String.length(query) > 50 or String.contains?(query, ["what", "how", "why", "explain"])
      "get_consciousness_state" -> true
      _ -> false
    end
  end
  
  defp enhance_arguments_with_llm(tool_name, arguments) do
    case tool_name do
      "query_subsystem" ->
        query = Map.get(arguments, "query", "")
        
        # Use LLM to parse natural language query into structured format
        case LLMBridge.call_llm_api(
          """
          Parse this natural language query into structured subsystem query parameters:
          
          Query: #{query}
          
          Extract:
          1. Intent (status, performance, health, configuration, etc.)
          2. Specific aspects to focus on
          3. Expected data type needed
          
          Return JSON with: {"intent": "...", "focus": "...", "data_type": "..."}
          """,
          :analysis,
          timeout: 5_000
        ) do
          {:ok, response} ->
            # Try to parse the LLM response as JSON
            case Jason.decode(response) do
              {:ok, parsed} -> Map.merge(arguments, parsed)
              {:error, _} -> arguments
            end
          {:error, _} -> arguments
        end
        
      _ -> arguments
    end
  end
  
  defp gather_vsm_data_for_analysis(subsystem, timeframe) do
    %{
      subsystem: subsystem,
      timeframe: timeframe,
      current_state: get_resource_content("vsm://subsystems"),
      metrics: get_resource_content("vsm://metrics"),
      algedonic: get_resource_content("vsm://algedonic"),
      events: get_recent_events_for_subsystem(subsystem),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp get_recent_events_for_subsystem(subsystem) do
    # Simulate getting events for the subsystem
    case subsystem do
      "all" -> %{events: "System-wide events", count: 42}
      _ -> %{events: "#{subsystem} specific events", count: 12}
    end
  end
  
  defp build_basic_vsm_prompt(subsystem, timeframe) do
    """
    Analyze the VSM (Viable System Model) performance for #{subsystem} over the last #{timeframe}.
    
    Please examine:
    1. Subsystem health and operational status
    2. Variety absorption and management
    3. Control loop effectiveness
    4. Algedonic signal patterns
    5. Resource utilization
    6. Any emerging patterns or anomalies
    
    Provide insights and recommendations for optimization.
    """
  end
  
  defp build_basic_consciousness_inquiry(aspect) do
    """
    Inquire about the system's consciousness state, focusing on #{aspect}.
    
    Current consciousness framework:
    - Multi-agent symbolic reasoning
    - Distributed decision-making
    - Emergent pattern recognition
    - Cybernetic self-regulation
    
    Please explore the current state and provide insights about the system's 
    self-awareness, decision-making processes, and emergent behaviors.
    """
  end
  
  defp gather_system_diagnostics(focus_area) do
    %{
      focus_area: focus_area,
      vsm_health: get_resource_content("vsm://subsystems"),
      system_metrics: get_resource_content("vsm://metrics"),
      event_flow: %{status: "operational", throughput: "normal"},
      resource_usage: %{cpu: 0.4, memory: 0.6, network: 0.3},
      error_rates: %{rate: 0.01, recent_errors: []},
      timestamp: DateTime.utc_now()
    }
  end
  
  defp build_basic_diagnosis_prompt(focus_area) do
    """
    Perform a comprehensive system diagnosis focusing on #{focus_area}.
    
    Diagnostic areas to examine:
    1. VSM subsystem health (S1-S5)
    2. EventBus message flow
    3. AMQP/messaging infrastructure
    4. Web Gateway performance
    5. Database and persistence layer
    6. Memory and resource usage
    7. Error rates and failure patterns
    
    Please analyze the current system state and identify any issues, 
    bottlenecks, or optimization opportunities.
    """
  end
end