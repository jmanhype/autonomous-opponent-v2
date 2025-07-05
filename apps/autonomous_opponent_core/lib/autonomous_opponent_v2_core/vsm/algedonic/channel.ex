defmodule AutonomousOpponentV2Core.VSM.Algedonic.Channel do
  @moduledoc """
  The Algedonic Channel - Your system's ability to SCREAM.
  
  This is NOT optional. This is survival.
  
  When metrics exceed pain thresholds, this channel BYPASSES all hierarchy
  and goes straight to S5 (and human operators if needed).
  
  Beer's insight: Bureaucracy kills. When the building is on fire,
  you don't file a report - you pull the alarm.
  """
  
  use GenServer
  require Logger
  alias AutonomousOpponentV2Core.EventBus
  
  @pain_threshold 0.85      # System is struggling
  @agony_threshold 0.95     # System is dying
  @pleasure_threshold 0.90  # System is thriving
  
  defstruct [
    :monitors,
    :pain_signals,
    :pleasure_signals,
    :last_scream,
    :intervention_active
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def report_pain(source, metric, intensity) when intensity > @pain_threshold do
    GenServer.cast(__MODULE__, {:pain, source, metric, intensity})
  end
  
  def report_pleasure(source, metric, intensity) when intensity > @pleasure_threshold do
    GenServer.cast(__MODULE__, {:pleasure, source, metric, intensity})
  end
  
  def emergency_scream(source, reason) do
    # IMMEDIATE - No GenServer, direct EventBus
    Logger.error("🚨 ALGEDONIC SCREAM from #{source}: #{reason}")
    
    signal_id = :crypto.hash(:sha256, "emergency:#{source}:#{reason}:#{System.unique_integer()}") 
                |> Base.encode16(case: :lower)
    
    EventBus.publish(:emergency_algedonic, %{
      id: signal_id,
      source: source,
      reason: reason,
      timestamp: DateTime.utc_now(),
      bypass_all: true
    })
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to all subsystem health metrics
    EventBus.subscribe(:s1_health)
    EventBus.subscribe(:s2_health)
    EventBus.subscribe(:s3_health)
    EventBus.subscribe(:s4_health)
    EventBus.subscribe(:s5_health)
    
    # Start monitoring
    Process.send_after(self(), :check_vitals, 100)
    
    state = %__MODULE__{
      monitors: %{
        s1: %{health: 1.0, last_update: DateTime.utc_now()},
        s2: %{health: 1.0, last_update: DateTime.utc_now()},
        s3: %{health: 1.0, last_update: DateTime.utc_now()},
        s4: %{health: 1.0, last_update: DateTime.utc_now()},
        s5: %{health: 1.0, last_update: DateTime.utc_now()}
      },
      pain_signals: [],
      pleasure_signals: [],
      last_scream: nil,
      intervention_active: false
    }
    
    Logger.info("🔥 Algedonic Channel active - the system can now feel")
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:pain, source, metric, intensity}, state) do
    cond do
      intensity > @agony_threshold ->
        handle_agony(source, metric, intensity, state)
        
      intensity > @pain_threshold ->
        handle_pain(source, metric, intensity, state)
        
      true ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_cast({:pleasure, source, metric, intensity}, state) do
    handle_pleasure(source, metric, intensity, state)
  end
  
  @impl true
  def handle_info({:event_bus, source, data}, state) do
    # Handle various event types
    cond do
      # Health events
      Map.has_key?(data, :health) ->
        subsystem = source |> Atom.to_string() |> String.replace("_health", "") |> String.to_atom()
        
        new_monitors = Map.put(state.monitors, subsystem, %{
          health: data.health,
          last_update: DateTime.utc_now()
        })
        
        new_state = %{state | monitors: new_monitors}
        
        if data.health < (1.0 - @pain_threshold) do
          handle_cast({:pain, subsystem, :health, 1.0 - data.health}, new_state)
        else
          {:noreply, new_state}
        end
        
      # Other events - ignore
      true ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:check_vitals, state) do
    # Regular vital signs check
    Process.send_after(self(), :check_vitals, 100)
    
    # Check for dead subsystems (no update in 5 seconds)
    now = DateTime.utc_now()
    
    dead_subsystems = state.monitors
    |> Enum.filter(fn {_name, data} ->
      DateTime.diff(now, data.last_update) > 5
    end)
    |> Enum.map(&elem(&1, 0))
    
    if Enum.any?(dead_subsystems) do
      emergency_scream(:algedonic_monitor, "SUBSYSTEMS DEAD: #{inspect(dead_subsystems)}")
      {:noreply, %{state | intervention_active: true}}
    else
      {:noreply, state}
    end
  end
  
  # Private Functions
  
  defp handle_pain(source, metric, intensity, state) do
    Logger.warning("😣 PAIN SIGNAL from #{source}.#{metric}: #{intensity}")
    
    signal_id = :crypto.hash(:sha256, "pain:#{source}:#{metric}:#{System.unique_integer()}") 
                |> Base.encode16(case: :lower)
    
    pain_signal = %{
      id: signal_id,
      source: source,
      metric: metric,
      intensity: intensity,
      timestamp: DateTime.utc_now()
    }
    
    # Bypass to S5 for policy intervention
    EventBus.publish(:algedonic_pain, pain_signal)
    
    # Also alert S3 for immediate control response
    EventBus.publish(:s3_intervention_required, pain_signal)
    
    new_state = %{state | 
      pain_signals: [pain_signal | state.pain_signals] |> Enum.take(100)
    }
    
    {:noreply, new_state}
  end
  
  defp handle_agony(source, metric, intensity, state) do
    Logger.error("😱 AGONY SIGNAL from #{source}.#{metric}: #{intensity}")
    
    signal_id = :crypto.hash(:sha256, "agony:#{source}:#{metric}:#{System.unique_integer()}") 
                |> Base.encode16(case: :lower)
    
    agony_signal = %{
      id: signal_id,
      source: source,
      metric: metric,
      intensity: intensity,
      severity: :critical,
      timestamp: DateTime.utc_now()
    }
    
    # BYPASS EVERYTHING
    EventBus.publish(:emergency_algedonic, agony_signal)
    
    # Force S5 intervention
    EventBus.publish(:s5_emergency_override, agony_signal)
    
    # Alert all subsystems
    EventBus.publish(:all_subsystems, {:emergency_mode, agony_signal})
    
    # If we've screamed 3 times in 60 seconds, shut down
    recent_screams = [agony_signal.timestamp | get_recent_screams(state)]
    
    if length(recent_screams) >= 3 do
      Logger.error("💀 SYSTEM DEATH IMMINENT - Too many screams")
      EventBus.publish(:system_shutdown, :algedonic_overload)
    end
    
    new_state = %{state | 
      pain_signals: [agony_signal | state.pain_signals] |> Enum.take(100),
      last_scream: agony_signal.timestamp,
      intervention_active: true
    }
    
    {:noreply, new_state}
  end
  
  defp handle_pleasure(source, metric, intensity, state) do
    Logger.info("😊 PLEASURE SIGNAL from #{source}.#{metric}: #{intensity}")
    
    signal_id = :crypto.hash(:sha256, "pleasure:#{source}:#{metric}:#{System.unique_integer()}") 
                |> Base.encode16(case: :lower)
    
    pleasure_signal = %{
      id: signal_id,
      source: source,
      metric: metric,
      intensity: intensity,
      timestamp: DateTime.utc_now()
    }
    
    # Reinforce successful patterns
    EventBus.publish(:algedonic_pleasure, pleasure_signal)
    
    # Tell S4 to remember this pattern
    EventBus.publish(:s4_reinforce_pattern, pleasure_signal)
    
    # Tell S3 to maintain current resource allocation
    EventBus.publish(:s3_maintain_state, pleasure_signal)
    
    new_state = %{state | 
      pleasure_signals: [pleasure_signal | state.pleasure_signals] |> Enum.take(100),
      intervention_active: false  # Pleasure cancels intervention
    }
    
    {:noreply, new_state}
  end
  
  
  defp get_recent_screams(state) do
    cutoff = DateTime.add(DateTime.utc_now(), -60, :second)
    
    state.pain_signals
    |> Enum.filter(&(&1.timestamp > cutoff && &1.severity == :critical))
    |> Enum.map(&(&1.timestamp))
  end
end