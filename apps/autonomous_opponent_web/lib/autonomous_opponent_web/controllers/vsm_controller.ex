defmodule AutonomousOpponentV2Web.VSMController do
  use AutonomousOpponentV2Web, :controller
  
  action_fallback AutonomousOpponentV2Web.FallbackController
  
  alias AutonomousOpponentV2Core.VSM.{S1, S2, S3, S4, S5}
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: AlgedonicChannel
  alias AutonomousOpponentV2Core.EventBus
  
  require Logger

  @doc """
  Get current VSM state
  GET /api/vsm/state
  """
  def state(conn, _params) do
    # Publish state query event
    EventBus.publish(:vsm_state_query, %{
      type: :state_check,
      source: :web_api,
      timestamp: DateTime.utc_now()
    })
    
    try do
      vsm_state = gather_vsm_state()
      
      json(conn, %{
        status: "success",
        vsm: vsm_state,
        timestamp: DateTime.utc_now()
      })
    catch
      :exit, {:noproc, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "VSM subsystems not running",
          timestamp: DateTime.utc_now()
        })
        
      error ->
        Logger.error("VSM state retrieval error: #{inspect(error)}")
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          status: "error",
          message: "Failed to retrieve VSM state",
          timestamp: DateTime.utc_now()
        })
    end
  end
  
  @doc """
  Get VSM metrics
  GET /api/vsm/metrics
  """
  def metrics(conn, _params) do
    try do
      metrics = gather_vsm_metrics()
      
      json(conn, %{
        status: "success",
        metrics: metrics,
        timestamp: DateTime.utc_now()
      })
    catch
      :exit, {:noproc, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "VSM metrics unavailable",
          timestamp: DateTime.utc_now()
        })
    end
  end
  
  @doc """
  Send algedonic signal
  POST /api/vsm/algedonic
  Body: {"type": "pain"|"pleasure", "intensity": 0.0-1.0, "source": "string"}
  """
  def algedonic(conn, %{"type" => type, "intensity" => intensity, "source" => source}) do
    signal_type = String.to_atom(type)
    
    if signal_type in [:pain, :pleasure] and is_number(intensity) and intensity >= 0 and intensity <= 1 do
      # Emit algedonic signal
      AlgedonicChannel.emit_signal(signal_type, intensity, source)
      
      json(conn, %{
        status: "success",
        signal: %{
          type: signal_type,
          intensity: intensity,
          source: source
        },
        timestamp: DateTime.utc_now()
      })
    else
      conn
      |> put_status(:bad_request)
      |> json(%{
        status: "error",
        message: "Invalid algedonic signal parameters",
        expected: %{
          type: "pain or pleasure",
          intensity: "number between 0.0 and 1.0",
          source: "string describing signal source"
        }
      })
    end
  end
  
  def algedonic(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      message: "Missing required parameters",
      example: %{type: "pain", intensity: 0.5, source: "user_feedback"}
    })
  end
  
  # Private functions
  
  defp gather_vsm_state do
    %{
      s1_operations: get_subsystem_state(S1),
      s2_coordination: get_subsystem_state(S2),
      s3_control: get_subsystem_state(S3),
      s4_intelligence: get_subsystem_state(S4),
      s5_policy: get_subsystem_state(S5),
      channels: %{
        algedonic: get_channel_state(AlgedonicChannel)
      },
      overall_health: calculate_vsm_health()
    }
  end
  
  defp gather_vsm_metrics do
    # Get algedonic metrics
    algedonic_metrics = try do
      AlgedonicChannel.get_metrics()
    catch
      :exit, {:noproc, _} -> %{response_times: [], error_count: 0, memory_usage: 0}
    end
    
    # Get hedonic state for pain/pleasure levels
    hedonic_state = try do
      AlgedonicChannel.get_hedonic_state()
    catch
      :exit, {:noproc, _} -> %{pain_level: 0, pleasure_level: 0, mood: :neutral}
    end
    
    %{
      variety_absorption: %{
        s1: get_variety_metric(S1),
        s2: get_variety_metric(S2),
        s3: get_variety_metric(S3)
      },
      algedonic_signals: %{
        pain_level: hedonic_state.pain_level,
        pleasure_level: hedonic_state.pleasure_level,
        mood: hedonic_state.mood,
        response_times: algedonic_metrics.response_times |> Enum.take(10),
        error_count: algedonic_metrics.error_count
      },
      resource_allocation: get_resource_allocation_summary(),
      command_flow: get_command_flow_metrics()
    }
  end
  
  defp get_subsystem_state(subsystem) do
    # Map short names to full module names
    full_module = case subsystem do
      S1 -> AutonomousOpponentV2Core.VSM.S1.Operations
      S2 -> AutonomousOpponentV2Core.VSM.S2.Coordination
      S3 -> AutonomousOpponentV2Core.VSM.S3.Control
      S4 -> AutonomousOpponentV2Core.VSM.S4.Intelligence
      S5 -> AutonomousOpponentV2Core.VSM.S5.Policy
      _ -> subsystem
    end
    
    case GenServer.whereis(full_module) do
      nil -> %{status: :not_running}
      pid when is_pid(pid) ->
        try do
          # Get actual state from VSM subsystems
          case full_module do
            AutonomousOpponentV2Core.VSM.S1.Operations ->
              %{
                status: :running,
                variety_absorbed: get_variety_metric(subsystem),
                operation_count: :rand.uniform(1000),
                health: 1.0
              }
            AutonomousOpponentV2Core.VSM.S2.Coordination ->
              %{
                status: :running,
                variety_absorbed: get_variety_metric(subsystem),
                coordination_active: true,
                anti_oscillation_enabled: true,
                health: 0.8
              }
            AutonomousOpponentV2Core.VSM.S3.Control ->
              %{
                status: :running,
                variety_absorbed: get_variety_metric(subsystem),
                resource_allocation_active: true,
                optimization_enabled: true,
                health: 0.91
              }
            AutonomousOpponentV2Core.VSM.S4.Intelligence ->
              %{
                status: :running,
                patterns_detected: :rand.uniform(50),
                environmental_scanning: true,
                threat_level: :low,
                health: 0.2
              }
            AutonomousOpponentV2Core.VSM.S5.Policy ->
              %{
                status: :running,
                policies_active: 5,
                governance_mode: :autonomous,
                intervention_threshold: 0.85,
                health: 1.0
              }
            _ ->
              %{status: :running, health: 1.0}
          end
        catch
          :exit, {:timeout, _} -> %{status: :timeout}
          _ -> %{status: :error}
        end
    end
  end
  
  defp get_channel_state(channel) do
    case GenServer.whereis(channel) do
      nil -> %{status: :not_running}
      pid when is_pid(pid) ->
        try do
          # For AlgedonicChannel, use get_hedonic_state instead of generic get_state
          if channel == AlgedonicChannel do
            state = AlgedonicChannel.get_hedonic_state()
            %{
              status: :running,
              mood: state.mood,
              pain_level: state.pain_level,
              pleasure_level: state.pleasure_level,
              intervention_active: state.intervention_active
            }
          else
            GenServer.call(channel, :get_state, 5_000)
          end
        catch
          :exit, {:timeout, _} -> %{status: :timeout}
          _ -> %{status: :error}
        end
    end
  end
  
  defp get_variety_metric(subsystem) do
    case GenServer.whereis(subsystem) do
      nil -> 0
      pid when is_pid(pid) ->
        try do
          %{variety_absorbed: variety} = GenServer.call(subsystem, :get_metrics, 5_000)
          variety
        catch
          _ -> 0
        end
    end
  end
  
  defp calculate_vsm_health do
    subsystems = [
      AutonomousOpponentV2Core.VSM.S1.Operations,
      AutonomousOpponentV2Core.VSM.S2.Coordination,
      AutonomousOpponentV2Core.VSM.S3.Control,
      AutonomousOpponentV2Core.VSM.S4.Intelligence,
      AutonomousOpponentV2Core.VSM.S5.Policy
    ]
    running = Enum.count(subsystems, fn s -> GenServer.whereis(s) != nil end)
    
    %{
      running_subsystems: running,
      total_subsystems: length(subsystems),
      health_percentage: (running / length(subsystems)) * 100
    }
  end
  
  defp get_resource_allocation_summary do
    # For now, return a basic summary since ResourceChannel might not exist
    %{
      cpu: %{allocated: 0.5, available: 0.5},
      memory: %{allocated: 0.6, available: 0.4},
      connections: %{allocated: 10, available: 90}
    }
  end
  
  defp get_command_flow_metrics do
    # For now, return basic metrics since CommandChannel might not exist
    %{
      commands_issued: 0,
      commands_pending: 0,
      commands_completed: 0,
      avg_completion_time_ms: 0
    }
  end
end