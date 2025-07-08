defmodule AutonomousOpponentV2Web.ConsciousnessController do
  use AutonomousOpponentV2Web, :controller
  
  action_fallback AutonomousOpponentV2Web.FallbackController
  
  alias AutonomousOpponentV2Core.Consciousness
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  alias AutonomousOpponentV2Core.AMCP.Events.{SemanticFusion, SemanticAnalyzer}
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  alias AutonomousOpponentV2Core.EventBus
  
  require Logger

  @doc """
  Simple test endpoint to verify JSON parsing
  """
  def test(conn, params) do
    json(conn, %{
      status: "success",
      received: params,
      message: "JSON parsing works!",
      env_check: %{
        openai_key_present: !is_nil(System.get_env("OPENAI_API_KEY")),
        openai_key_length: if(System.get_env("OPENAI_API_KEY"), do: String.length(System.get_env("OPENAI_API_KEY")), else: 0),
        anthropic_key_present: !is_nil(System.get_env("ANTHROPIC_API_KEY")),
        google_ai_key_present: !is_nil(System.get_env("GOOGLE_AI_API_KEY"))
      }
    })
  end

  @doc """
  Chat with the cybernetic consciousness
  POST /api/consciousness/chat
  Body: {"message": "What are you thinking about?"}
  """
  def chat(conn, %{"message" => message}) do
    # Quick test mode for simple messages
    if String.starts_with?(message, "test:") do
      json(conn, %{
        status: "success",
        response: "Test mode: I received '#{message}'",
        timestamp: DateTime.utc_now(),
        consciousness_active: true,
        mode: "test"
      })
    else
      # Publish user interaction event
      user_id = Map.get(conn.body_params, "user_id", "anonymous")
      Logger.info("Publishing user_interaction event for user: #{user_id}")
      
      event_data = %{
        type: :chat_message,
        user_id: user_id,
        message: message,
        timestamp: DateTime.utc_now(),
        source: :web_api
      }
      
      case EventBus.publish(:user_interaction, event_data) do
        :ok -> 
          Logger.info("Successfully published user_interaction event")
        error -> 
          Logger.error("Failed to publish event: #{inspect(error)}")
      end
      
      # Also create/update CRDT entries
      ensure_crdt_initialized()
      
      # Only update CRDTs if CRDTStore is running
      if crdt_store_available?() do
        try do
          CRDTStore.update_crdt("chat_interactions", :increment, 1)
          CRDTStore.update_crdt("user_messages", :add, %{
            user_id: user_id,
            message: String.slice(message, 0, 100),
            timestamp: DateTime.utc_now()
          })
        catch
          :exit, {:noproc, _} ->
            Logger.warning("CRDTStore disappeared while updating")
          :exit, {:timeout, _} ->
            Logger.warning("CRDTStore timeout while updating")
        end
      end
      
      try do
        case Consciousness.conscious_dialog(message) do
          {:ok, response} ->
            # Publish successful response event
            EventBus.publish(:consciousness_response, %{
              type: :chat_response,
              user_id: user_id,
              response_length: String.length(response),
              timestamp: DateTime.utc_now()
            })
            
            json(conn, %{
              status: "success",
              response: response,
              timestamp: DateTime.utc_now(),
              consciousness_active: true
            })
            
          {:error, reason} ->
            EventBus.publish(:consciousness_error, %{
              type: :chat_error,
              reason: inspect(reason),
              timestamp: DateTime.utc_now()
            })
            handle_consciousness_error(conn, message, reason)
        end
      catch
        :exit, {:noproc, _} ->
          handle_consciousness_error(conn, message, "Consciousness module not running")
      end
    end
  end
  
  # Fallback for missing message parameter
  def chat(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: "Missing 'message' parameter",
      example: %{message: "What are you thinking about?"}
    })
  end
  
  defp handle_consciousness_error(conn, _message, reason) do
    Logger.error("Consciousness chat failed: #{inspect(reason)}")
    
    # No fallback - return error directly
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      status: "error",
      message: "Consciousness module not available",
      details: inspect(reason)
    })
  end

  @doc """
  Get current consciousness state
  GET /api/consciousness/state
  """
  def state(conn, _params) do
    # Publish state query event
    EventBus.publish(:consciousness_query, %{
      type: :state_check,
      source: :web_api,
      timestamp: DateTime.utc_now()
    })
    
    try do
      case Consciousness.get_consciousness_state() do
        {:ok, state} ->
          # Publish state retrieved event
          EventBus.publish(:consciousness_state_retrieved, %{
            awareness_level: Map.get(state, :awareness_level, 0),
            state_type: Map.get(state, :state, "unknown"),
            timestamp: DateTime.utc_now()
          })
          
          json(conn, %{
            status: "success",
            consciousness: state,
            timestamp: DateTime.utc_now()
          })
          
        {:error, reason} ->
          Logger.warning("Consciousness state unavailable: #{inspect(reason)}")
          
          # No fallback - return error
          conn
          |> put_status(:service_unavailable)
          |> json(%{
            status: "error",
            message: "Consciousness state unavailable",
            details: inspect(reason)
          })
      end
    catch
      :exit, {:timeout, _} ->
        conn
        |> put_status(:gateway_timeout)
        |> json(%{
          status: "error",
          message: "Consciousness module timeout"
        })
        
      :exit, {:noproc, _} ->
        json(conn, %{
          status: "error",
          message: "Consciousness module not running",
          timestamp: DateTime.utc_now()
        })
    end
  end

  @doc """
  Get inner dialog stream
  GET /api/consciousness/dialog
  """
  def inner_dialog(conn, _params) do
    case Consciousness.get_inner_dialog() do
      {:ok, dialog} ->
        json(conn, %{
          status: "success",
          inner_dialog: Enum.take(dialog, 10),
          count: length(dialog),
          timestamp: DateTime.utc_now()
        })
        
      {:error, reason} ->
        Logger.warning("Inner dialog unavailable: #{inspect(reason)}")
        
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Inner dialog unavailable",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Ask consciousness to reflect on something
  POST /api/consciousness/reflect
  Body: {"aspect": "existence"}
  """
  def reflect(conn, %{"aspect" => aspect}) do
    # Publish reflection request event
    EventBus.publish(:consciousness_reflection_requested, %{
      aspect: aspect,
      source: :web_api,
      timestamp: DateTime.utc_now()
    })
    
    case Consciousness.reflect_on(aspect) do
      {:ok, reflection} ->
        # Publish successful reflection event
        EventBus.publish(:consciousness_reflection_completed, %{
          aspect: aspect,
          reflection_length: String.length(reflection),
          timestamp: DateTime.utc_now()
        })
        
        json(conn, %{
          status: "success",
          aspect: aspect,
          reflection: reflection,
          timestamp: DateTime.utc_now()
        })
        
      {:error, reason} ->
        Logger.warning("Consciousness reflection failed: #{inspect(reason)}")
        
        # No fallback - return error
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Reflection capability unavailable",
          details: inspect(reason)
        })
    end
  end
  
  # Fallback for missing aspect parameter
  def reflect(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: "Missing 'aspect' parameter", 
      example: %{aspect: "existence"}
    })
  end

  @doc """
  Get detected patterns with AI explanations
  GET /api/patterns
  """
  def patterns(conn, params) do
    time_window = Map.get(params, "time_window", "300") |> String.to_integer()
    
    # Get REAL patterns from SemanticFusion - no synthetic data
    result = case SemanticFusion.get_patterns(time_window) do
      {:ok, patterns} when is_list(patterns) ->
        # Return actual patterns, even if empty
        pattern_summary = %{
          total_patterns: length(patterns),
          pattern_types: patterns |> Enum.map(& &1[:type]) |> Enum.frequencies(),
          avg_confidence: calculate_avg_confidence(patterns),
          time_window_seconds: time_window,
          data_integrity: "real"
        }
        
        %{
          status: "success",
          patterns: patterns,
          summary: pattern_summary,
          timestamp: DateTime.utc_now(),
          note: if(patterns == [], do: "No patterns detected yet. The system needs more interactions to identify patterns.", else: nil)
        }
        
      {:error, reason} ->
        Logger.error("SemanticFusion pattern retrieval failed: #{inspect(reason)}")
        
        %{
          status: "error",
          patterns: [],
          summary: %{
            total_patterns: 0,
            pattern_types: %{},
            avg_confidence: 0,
            time_window_seconds: time_window,
            data_integrity: "unavailable"
          },
          error: "Pattern detection service temporarily unavailable",
          timestamp: DateTime.utc_now()
        }
    end
    
    # Filter out nil values from response
    response = result |> Enum.filter(fn {_k, v} -> v != nil end) |> Enum.into(%{})
    
    json(conn, response)
  end
  
  # Helper function for calculating average confidence
  defp calculate_avg_confidence([]), do: 0
  defp calculate_avg_confidence(patterns) do
    confidences = patterns |> Enum.map(& &1[:confidence] || 0) |> Enum.filter(& &1 > 0)
    if length(confidences) > 0 do
      Enum.sum(confidences) / length(confidences)
    else
      0
    end
  end

  @doc """
  Get semantic event analysis
  GET /api/events/analyze
  """
  def analyze_events(conn, params) do
    time_window = Map.get(params, "time_window", "60") |> String.to_integer()
    
    # Get REAL analysis from SemanticAnalyzer - no synthetic data
    summary = case SemanticAnalyzer.generate_activity_summary(time_window) do
      {:ok, summary_text} when is_binary(summary_text) ->
        summary_text
        
      {:error, reason} ->
        Logger.error("SemanticAnalyzer summary generation failed: #{inspect(reason)}")
        "Event analysis temporarily unavailable. System is collecting data."
    end
    
    # Get REAL trending topics
    topics = case SemanticAnalyzer.get_trending_topics() do
      {:ok, topic_list} when is_list(topic_list) ->
        # Convert tuples to maps if needed, but use real data
        Enum.map(topic_list, fn
          {topic, freq} -> %{topic: to_string(topic), frequency: freq}
          map when is_map(map) -> map
        end)
        
      {:error, reason} ->
        Logger.error("SemanticAnalyzer trending topics failed: #{inspect(reason)}")
        []
    end
    
    # Build honest response
    response = %{
      status: "success",
      analysis: %{
        summary: summary,
        trending_topics: topics,
        time_window_seconds: time_window,
        data_integrity: "real",
        topic_count: length(topics)
      },
      timestamp: DateTime.utc_now()
    }
    
    # Add note if no data available
    response = if topics == [] and String.contains?(summary, "No significant events") do
      Map.put(response, :note, "System is actively collecting data. Generate interactions through the chat endpoint to see analysis.")
    else
      response
    end
    
    json(conn, response)
  end

  @doc """
  Get AI knowledge synthesis from memory
  GET /api/memory/synthesize
  """
  def synthesize_memory(conn, params) do
    domains = Map.get(params, "domains", "all")
    
    # Parse domains parameter
    parsed_domains = case domains do
      "all" -> :all
      domain_string when is_binary(domain_string) ->
        String.split(domain_string, ",") |> Enum.map(&String.to_atom/1)
      _ -> :all
    end
    
    case CRDTStore.synthesize_knowledge(parsed_domains) do
      {:ok, synthesis} ->
        json(conn, %{
          status: "success",
          knowledge_synthesis: synthesis,
          domains: parsed_domains,
          timestamp: DateTime.utc_now()
        })
        
      {:error, reason} ->
        Logger.warning("Knowledge synthesis unavailable: #{inspect(reason)}")
        
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error", 
          message: "Knowledge synthesis temporarily unavailable",
          details: inspect(reason)
        })
    end
  end
  
  @doc """
  Debug endpoint to seed data for testing
  POST /api/debug/seed
  """
  def seed_data(conn, _params) do
    # Ensure CRDT entries exist
    ensure_crdt_initialized()
    
    # Generate events
    for i <- 1..100 do
      EventBus.publish(:user_interaction, %{
        type: :chat_message,
        user_id: "seed_user_#{rem(i, 5)}",
        message_type: Enum.random([:question, :statement, :reflection]),
        topic: Enum.random([:consciousness, :philosophy, :technology]),
        timestamp: DateTime.add(DateTime.utc_now(), -300 + i * 3, :second)
      })
      
      if rem(i, 10) == 0 do
        EventBus.publish(:pattern_detected, %{
          pattern_type: Enum.random([:behavioral, :temporal, :semantic]),
          confidence: 0.7 + :rand.uniform() * 0.3,
          pattern_id: "pattern_#{i}",
          description: "Test pattern #{i}",
          timestamp: DateTime.add(DateTime.utc_now(), -300 + i * 3, :second)
        })
      end
    end
    
    # Update CRDT data
    for i <- 1..50 do
      CRDTStore.update_crdt("chat_interactions", :increment, 1)
    end
    
    # Add knowledge entries
    CRDTStore.update_crdt("system_knowledge", :put, 
      {"test_data", "seeded_at", DateTime.utc_now()})
    CRDTStore.update_crdt("system_knowledge", :put, 
      {"test_data", "event_count", 100})
    
    # Trigger semantic analysis
    if pid = Process.whereis(SemanticAnalyzer) do
      send(pid, :perform_batch_analysis)
    end
    
    json(conn, %{
      status: "success",
      message: "Data seeded successfully",
      events_generated: 100,
      crdt_updates: 52,
      timestamp: DateTime.utc_now()
    })
  end
  
  # Helper to safely check if CRDTStore is available
  defp crdt_store_available? do
    case Process.whereis(AutonomousOpponentV2Core.AMCP.Memory.CRDTStore) do
      nil -> false
      _pid -> true
    end
  end
  
  # Helper to ensure CRDT entries exist
  defp ensure_crdt_initialized do
    # Check if CRDTStore is running before attempting to use it
    if crdt_store_available?() do
        try do
          # Create CRDT entries if they don't exist
          case CRDTStore.get_crdt("chat_interactions") do
            {:error, :not_found} ->
              CRDTStore.create_crdt("chat_interactions", :pn_counter, 0)
            _ -> :ok
          end
          
          case CRDTStore.get_crdt("user_messages") do
            {:error, :not_found} ->
              CRDTStore.create_crdt("user_messages", :or_set, [])
            _ -> :ok
          end
          
          case CRDTStore.get_crdt("system_knowledge") do
            {:error, :not_found} ->
              CRDTStore.create_crdt("system_knowledge", :crdt_map, %{
                "initialization_time" => DateTime.utc_now(),
                "system_type" => "autonomous_opponent_v2",
                "capabilities" => ["chat", "reflection", "pattern_detection", "memory_synthesis"]
              })
            _ -> :ok
          end
        catch
          :exit, {:noproc, _} ->
            Logger.warning("CRDTStore process died during initialization")
            :ok
          :exit, {:timeout, _} ->
            Logger.warning("CRDTStore timeout during initialization")
            :ok
        end
    else
      Logger.warning("CRDTStore not running - skipping CRDT initialization")
      :ok
    end
  end
end