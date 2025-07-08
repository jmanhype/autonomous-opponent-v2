defmodule AutonomousOpponentV2Core.SemanticFusion do
  @moduledoc """
  Semantic Fusion Engine - Bridge to the real AMCP.Events.SemanticFusion
  """
  
  use GenServer
  require Logger
  alias AutonomousOpponentV2Core.AMCP.Events.SemanticFusion, as: RealFusion
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get recent patterns detected by the semantic fusion engine
  BULLETPROOF - Always returns a list, never crashes
  """
  def get_recent_patterns(limit \\ 5) do
    # Get real patterns from AMCP.Events.SemanticFusion
    try do
      case Process.whereis(RealFusion) do
        nil -> 
          # Real fusion not running, try our cache
          get_cached_patterns_safe(limit)
        pid when is_pid(pid) ->
          case GenServer.call(RealFusion, :get_recent_patterns, 5000) do
            patterns when is_list(patterns) ->
              Enum.take(patterns, limit)
            _ ->
              # Invalid response, use cache
              get_cached_patterns_safe(limit)
          end
      end
    catch
      :exit, {:noproc, _} ->
        Logger.debug("RealFusion not available, using cache")
        get_cached_patterns_safe(limit)
      :exit, {:timeout, _} -> 
        Logger.debug("RealFusion timeout, using cache")
        get_cached_patterns_safe(limit)
      kind, reason ->
        Logger.error("SemanticFusion.get_recent_patterns caught #{kind}: #{inspect(reason)}")
        []  # Always return empty list on catastrophic failure
    end
  end
  
  defp get_cached_patterns_safe(limit) do
    try do
      case Process.whereis(__MODULE__) do
        nil -> []
        pid when is_pid(pid) ->
          case GenServer.call(__MODULE__, :get_cached_patterns, 1000) do
            patterns when is_list(patterns) -> Enum.take(patterns, limit)
            _ -> []
          end
      end
    catch
      _, _ -> []
    end
  end
  
  @doc """
  Forward event to real semantic fusion
  """
  def fuse_event(event) do
    case Process.whereis(RealFusion) do
      nil -> :ok
      pid when is_pid(pid) ->
        GenServer.cast(RealFusion, {:fuse_event, event})
    end
  end
  
  # GenServer callbacks
  def init(_opts) do
    # Subscribe to pattern detected events
    AutonomousOpponentV2Core.EventBus.subscribe(:pattern_detected)
    AutonomousOpponentV2Core.EventBus.subscribe(:semantic_analysis_complete)
    
    {:ok, %{cached_patterns: [], last_update: DateTime.utc_now()}}
  end
  
  def handle_call(:get_cached_patterns, _from, state) do
    {:reply, state.cached_patterns, state}
  end
  
  # Handle new HLC event format from EventBus
  def handle_info({:event_bus_hlc, event}, state) do
    # Extract event data and forward to existing handler
    handle_info({:event_bus, event.type, event.data}, state)
  end
  
  def handle_info({:event_bus, :pattern_detected, data}, state) do
    # Cache the pattern - BULLETPROOF
    try do
      pattern = %{
        type: Map.get(data, :pattern_type, :unknown),
        confidence: Map.get(data, :confidence, 0.5),
        timestamp: Map.get(data, :timestamp, DateTime.utc_now()),
        details: Map.get(data, :details, %{})
      }
      
      new_patterns = [pattern | state.cached_patterns] |> Enum.take(100)
      
      {:noreply, %{state | cached_patterns: new_patterns, last_update: DateTime.utc_now()}}
    catch
      kind, reason ->
        Logger.error("SemanticFusion pattern cache error #{kind}: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  def handle_info({:event_bus, :semantic_analysis_complete, data}, state) do
    # Extract patterns from semantic analysis - BULLETPROOF
    try do
      patterns = case Map.get(data, :patterns) do
        p when is_list(p) -> p
        _ -> []
      end
      new_patterns = patterns ++ state.cached_patterns |> Enum.take(100)
      
      {:noreply, %{state | cached_patterns: new_patterns, last_update: DateTime.utc_now()}}
    catch
      kind, reason ->
        Logger.error("SemanticFusion analysis cache error #{kind}: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end