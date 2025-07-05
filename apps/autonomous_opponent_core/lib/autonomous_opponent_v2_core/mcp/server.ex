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
  def handle_cast({:handle_message, raw_message}, state) do
    case Message.parse(raw_message) do
      {:ok, message} ->
        state = process_mcp_message(message, state)
        {:noreply, state}
        
      {:error, reason} ->
        Logger.error("Invalid MCP message: #{inspect(reason)}")
        send_error(state, nil, "parse_error", "Invalid JSON-RPC message")
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
    
    response = %{
      protocolVersion: @mcp_version,
      capabilities: state.capabilities,
      serverInfo: %{
        name: @server_name,
        version: @server_version
      }
    }
    
    send_response(state, message.id, response)
    %{state | client_info: client_info}
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
    send_response(state, message.id, %{tools: state.tools})
    state
  end
  
  defp process_mcp_message(%{method: "tools/call"} = message, state) do
    tool_name = message.params["name"]
    arguments = message.params["arguments"] || %{}
    
    result = execute_tool(tool_name, arguments)
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
    
    %{
      content: [%{
        type: "text",
        text: "Algedonic signal triggered: #{type} with severity #{severity}"
      }]
    }
  end
  
  defp execute_tool("query_subsystem", %{"subsystem" => subsystem, "query" => query}) do
    result = case EventBus.call(:"vsm_#{subsystem}", :handle_query, [query], 5000) do
      {:ok, response} -> response
      _ -> "Subsystem not responding"
    end
    
    %{
      content: [%{
        type: "text", 
        text: "#{String.upcase(subsystem)} Response: #{inspect(result)}"
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
    state = get_resource_content("vsm://consciousness")
    
    %{
      content: [%{
        type: "text",
        text: "Consciousness State: #{Jason.encode!(state, pretty: true)}"
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
    
    %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: """
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
          }
        }
      ]
    }
  end
  
  defp generate_prompt("consciousness_inquiry", arguments) do
    aspect = arguments["aspect"] || "general"
    
    %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: """
            Inquire about the system's consciousness state, focusing on #{aspect}.
            
            Current consciousness framework:
            - Multi-agent symbolic reasoning
            - Distributed decision-making
            - Emergent pattern recognition
            - Cybernetic self-regulation
            
            Please explore the current state and provide insights about the system's 
            self-awareness, decision-making processes, and emergent behaviors.
            """
          }
        }
      ]
    }
  end
  
  defp generate_prompt("system_diagnosis", arguments) do
    focus_area = arguments["focus_area"] || "overall"
    
    %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: """
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
    response = Message.create_response(id, result)
    Transport.send_message(state.transport, response)
  end
  
  defp send_error(state, id, code, message) do
    error_response = Message.create_error(id, code, message)
    Transport.send_message(state.transport, error_response)
  end
  
  defp send_notification(state, method, params) do
    notification = Message.create_notification(method, params)
    Transport.send_message(state.transport, notification)
  end
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end