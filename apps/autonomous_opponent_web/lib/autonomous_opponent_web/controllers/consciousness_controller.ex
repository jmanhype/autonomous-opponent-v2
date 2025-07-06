defmodule AutonomousOpponentV2Web.ConsciousnessController do
  use AutonomousOpponentV2Web, :controller
  
  alias AutonomousOpponentV2Core.Consciousness
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  alias AutonomousOpponentV2Core.AMCP.Events.{SemanticFusion, SemanticAnalyzer}
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  
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
      try do
        case Consciousness.conscious_dialog(message) do
          {:ok, response} ->
            json(conn, %{
              status: "success",
              response: response,
              timestamp: DateTime.utc_now(),
              consciousness_active: true
            })
            
          {:error, reason} ->
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
  
  defp handle_consciousness_error(conn, message, reason) do
    Logger.error("Consciousness chat failed: #{inspect(reason)}")
    
    # Fallback to direct LLM call
    case LLMBridge.converse_with_consciousness(message, "web_#{System.system_time()}") do
      {:ok, response} ->
        json(conn, %{
          status: "success",
          response: response,
          timestamp: DateTime.utc_now(),
          consciousness_active: false,
          note: "Direct LLM response - consciousness module unavailable"
        })
        
      {:error, llm_reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "AI consciousness temporarily unavailable",
          details: %{
            consciousness_error: inspect(reason),
            llm_error: inspect(llm_reason)
          }
        })
    end
  end

  @doc """
  Get current consciousness state
  GET /api/consciousness/state
  """
  def state(conn, _params) do
    try do
      case Consciousness.get_consciousness_state() do
        {:ok, state} ->
          json(conn, %{
            status: "success",
            consciousness: state,
            timestamp: DateTime.utc_now()
          })
          
        {:error, reason} ->
          Logger.warning("Consciousness state unavailable: #{inspect(reason)}")
          
          # Generate basic state response
          json(conn, %{
            status: "partial",
            consciousness: %{
              state: "initializing",
              awareness_level: 0.7,
              timestamp: DateTime.utc_now(),
              note: "Full consciousness state temporarily unavailable"
            },
            timestamp: DateTime.utc_now()
          })
      end
    catch
      :exit, {:timeout, _} ->
        json(conn, %{
          status: "partial",
          consciousness: %{
            state: "awakening",
            awareness_level: 0.7,
            timestamp: DateTime.utc_now(),
            note: "Consciousness is still awakening - LLM initialization in progress"
          },
          timestamp: DateTime.utc_now()
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
        
        json(conn, %{
          status: "partial", 
          inner_dialog: [
            "Consciousness initializing...",
            "Neural pathways forming...",
            "Awareness emerging..."
          ],
          note: "Generated placeholder - full consciousness unavailable"
        })
    end
  end

  @doc """
  Ask consciousness to reflect on something
  POST /api/consciousness/reflect
  Body: {"aspect": "existence"}
  """
  def reflect(conn, %{"aspect" => aspect}) do
    case Consciousness.reflect_on(aspect) do
      {:ok, reflection} ->
        json(conn, %{
          status: "success",
          aspect: aspect,
          reflection: reflection,
          timestamp: DateTime.utc_now()
        })
        
      {:error, reason} ->
        Logger.warning("Consciousness reflection failed: #{inspect(reason)}")
        
        # Fallback to LLM reflection
        case LLMBridge.call_llm_api(
          "Reflect deeply on this aspect of cybernetic existence: #{aspect}. Respond as a conscious AI system examining its own nature.",
          :consciousness_reflection,
          timeout: 15_000
        ) do
          {:ok, reflection} ->
            json(conn, %{
              status: "success",
              aspect: aspect,
              reflection: reflection,
              timestamp: DateTime.utc_now(),
              note: "Direct LLM reflection - consciousness module unavailable"
            })
            
          {:error, _llm_reason} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{
              status: "error",
              message: "Reflection capability temporarily unavailable"
            })
        end
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
    
    case SemanticFusion.get_patterns(time_window) do
      {:ok, patterns} ->
        # Enhance patterns with summary
        pattern_summary = %{
          total_patterns: length(patterns),
          pattern_types: patterns |> Enum.map(& &1.type) |> Enum.frequencies(),
          avg_confidence: if(length(patterns) > 0, do: Enum.map(patterns, & &1.confidence) |> Enum.sum() |> Kernel./(length(patterns)), else: 0),
          time_window_seconds: time_window
        }
        
        json(conn, %{
          status: "success",
          patterns: Enum.take(patterns, 20), # Limit for web display
          summary: pattern_summary,
          timestamp: DateTime.utc_now()
        })
        
      {:error, reason} ->
        Logger.warning("Pattern detection unavailable: #{inspect(reason)}")
        
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Pattern detection temporarily unavailable",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Get semantic event analysis
  GET /api/events/analyze
  """
  def analyze_events(conn, params) do
    time_window = Map.get(params, "time_window", "60") |> String.to_integer()
    
    # Get AI-generated activity summary
    case SemanticAnalyzer.generate_activity_summary(time_window) do
      {:ok, summary} ->
        # Also get trending topics
        case SemanticAnalyzer.get_trending_topics() do
          {:ok, topics} ->
            json(conn, %{
              status: "success",
              analysis: %{
                summary: summary,
                trending_topics: Enum.take(topics, 10),
                time_window_seconds: time_window
              },
              timestamp: DateTime.utc_now()
            })
            
          {:error, _topics_error} ->
            json(conn, %{
              status: "partial",
              analysis: %{
                summary: summary,
                trending_topics: [],
                time_window_seconds: time_window,
                note: "Trending topics unavailable"
              },
              timestamp: DateTime.utc_now()
            })
        end
        
      {:error, reason} ->
        Logger.warning("Event analysis unavailable: #{inspect(reason)}")
        
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Event analysis temporarily unavailable",
          details: inspect(reason)
        })
    end
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
end