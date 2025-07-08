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
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.Telemetry.SystemTelemetry
  
  # Pain thresholds (0-1 scale, where 1 is maximum pain)
  @pain_threshold 0.85      # System is struggling
  @agony_threshold 0.95     # System is dying
  
  # Pleasure thresholds (0-1 scale, where 1 is maximum pleasure)
  @pleasure_threshold 0.90  # System is thriving
  
  # Specific metric thresholds
  @response_time_pain_ms 500      # Pain when response > 500ms
  @response_time_agony_ms 2000    # Agony when response > 2s
  @error_rate_pain 0.05           # Pain when error rate > 5%
  @error_rate_agony 0.20          # Agony when error rate > 20%
  @memory_pressure_pain 0.80      # Pain when memory > 80%
  @memory_pressure_agony 0.95     # Agony when memory > 95%
  @queue_depth_pain 1000          # Pain when queue > 1000 items
  @queue_depth_agony 5000         # Agony when queue > 5000 items
  
  # Hedonic adaptation parameters
  @adaptation_rate 0.1            # How quickly we adapt to stimuli
  @adaptation_recovery_ms 60_000  # Time to reset adaptation (1 minute)
  
  defstruct [
    :monitors,
    :pain_signals,
    :pleasure_signals,
    :last_scream,
    :intervention_active,
    :hedonic_baselines,     # Adaptation baselines for each metric
    :metric_history,        # Rolling history of metrics
    :telemetry_ref          # Reference to telemetry subscription
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def report_pain(source, metric, intensity) when intensity > @pain_threshold do
    GenServer.cast(__MODULE__, {:pain, source, metric, intensity})
  end
  
  def report_pain(source, metric, intensity) do
    # Ignore pain signals below threshold
    :ok
  end
  
  def report_pleasure(source, metric, intensity) when intensity > @pleasure_threshold do
    GenServer.cast(__MODULE__, {:pleasure, source, metric, intensity})
  end
  
  def report_pleasure(source, metric, intensity) do
    # Still process lower intensity pleasure signals for external API
    if intensity > 0.5 do
      GenServer.cast(__MODULE__, {:pleasure, source, metric, intensity})
    else
      :ok
    end
  end
  
  def emergency_scream(source, reason) do
    # IMMEDIATE - Generate causally-ordered emergency signal with HLC
    emergency_event = case safe_create_event(:algedonic, :emergency_algedonic, %{
      source: source,
      reason: reason,
      bypass_all: true,
      intensity: 1.0,  # Maximum pain intensity
      severity: :critical  # Emergency level severity
    }) do
      {:ok, event} -> event
      {:error, reason} ->
        # Fallback for emergency signals - we can't afford to fail
        Logger.error("Failed to create HLC emergency event: #{inspect(reason)}, using fallback")
        timestamp = System.system_time(:millisecond)
        %{
          id: "emergency_fallback_#{timestamp}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}",
          subsystem: :algedonic,
          type: :emergency_algedonic,
          data: %{
            source: source,
            reason: reason,
            bypass_all: true,
            intensity: 1.0,
            severity: :critical
          },
          timestamp: %{physical: timestamp, logical: 0, node_id: "emergency_fallback"},
          created_at: DateTime.to_iso8601(DateTime.from_unix!(timestamp, :millisecond))
        }
    end
    
    Logger.error("🚨 ALGEDONIC SCREAM from #{source}: #{reason}", 
      event_id: emergency_event.id, hlc: emergency_event.timestamp)
    
    # Direct EventBus publish with HLC ordering to prevent race conditions
    EventBus.publish(:emergency_algedonic, emergency_event.data)
  end
  
  @doc """
  Emit an algedonic signal - used by external API
  """
  def emit_signal(type, intensity, source) when type in [:pain, :pleasure] do
    case type do
      :pain -> report_pain(source, :external_api, intensity)
      :pleasure -> report_pleasure(source, :external_api, intensity)
    end
    :ok
  end
  
  @doc """
  Get the current hedonic state - how the system is feeling
  """
  def get_hedonic_state do
    GenServer.call(__MODULE__, :get_hedonic_state)
  end
  
  @doc """
  Get current pain/pleasure metrics with adaptation levels
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  @doc """
  Check if the system is currently in pain
  """
  def in_pain? do
    GenServer.call(__MODULE__, :in_pain?)
  end
  
  @doc """
  Force a metric check (useful for testing)
  """
  def check_metrics_now do
    send(__MODULE__, :calculate_pain_pleasure)
    :ok
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
    
    # Subscribe to system telemetry events
    EventBus.subscribe(:telemetry_update)
    EventBus.subscribe(:http_request_complete)
    EventBus.subscribe(:amqp_message_processed)
    EventBus.subscribe(:cache_operation)
    EventBus.subscribe(:pattern_detected)
    EventBus.subscribe(:optimization_applied)
    
    # Attach to Telemetry events for real-time metrics
    telemetry_ref = make_ref()
    :telemetry.attach_many(
      telemetry_ref,
      [
        [:vm, :memory],
        [:vm, :system_counts],
        [:phoenix, :endpoint, :stop],
        [:autonomous_opponent, :amqp, :message, :stop],
        [:autonomous_opponent, :cache, :hit],
        [:autonomous_opponent, :cache, :miss]
      ],
      &handle_telemetry_event/4,
      self()
    )
    
    # Start monitoring
    Process.send_after(self(), :check_vitals, 100)
    Process.send_after(self(), :calculate_pain_pleasure, 1000)
    Process.send_after(self(), :adapt_baselines, @adaptation_recovery_ms)
    
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
      intervention_active: false,
      hedonic_baselines: %{
        response_time: 100.0,    # Start with optimistic baselines
        error_rate: 0.0,
        memory_usage: 0.5,
        queue_depth: 0,
        throughput: 100.0,
        cache_hit_rate: 0.5
      },
      metric_history: %{
        response_times: [],
        error_counts: [],
        success_counts: [],
        memory_readings: [],
        queue_depths: [],
        cache_hits: [],
        cache_misses: []
      },
      telemetry_ref: telemetry_ref
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
  def handle_call(:get_hedonic_state, _from, state) do
    metrics = calculate_current_metrics(state)
    
    # Determine overall hedonic tone
    recent_pain = Enum.take(state.pain_signals, 10)
    recent_pleasure = Enum.take(state.pleasure_signals, 10)
    
    avg_pain = if Enum.empty?(recent_pain), 
      do: 0.0,
      else: Enum.sum(Enum.map(recent_pain, & &1.intensity)) / length(recent_pain)
      
    avg_pleasure = if Enum.empty?(recent_pleasure),
      do: 0.0, 
      else: Enum.sum(Enum.map(recent_pleasure, & &1.intensity)) / length(recent_pleasure)
    
    hedonic_tone = cond do
      state.intervention_active -> :agony
      avg_pain > @pain_threshold -> :pain
      avg_pleasure > @pleasure_threshold -> :pleasure
      true -> :neutral
    end
    
    reply = %{
      tone: hedonic_tone,
      mood: hedonic_tone,  # Add :mood key for backward compatibility
      pain_level: avg_pain,
      pleasure_level: avg_pleasure,
      intervention_active: state.intervention_active,
      recent_screams: length(get_recent_screams(state)),
      adaptation_levels: state.hedonic_baselines,
      current_metrics: metrics
    }
    
    {:reply, reply, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = calculate_current_metrics(state)
    
    reply = %{
      # Top-level metrics for backward compatibility
      response_times: state.metric_history.response_times,
      error_count: length(state.metric_history.error_counts),
      memory_usage: metrics.memory_usage,
      
      # Detailed metrics
      raw_metrics: metrics,
      baselines: state.hedonic_baselines,
      adapted_thresholds: %{
        response_time: %{
          pain: @response_time_pain_ms + (state.hedonic_baselines.response_time - 50.0) * 0.5,
          agony: @response_time_agony_ms + (state.hedonic_baselines.response_time - 50.0) * 0.5
        },
        memory: %{pain: @memory_pressure_pain, agony: @memory_pressure_agony},
        error_rate: %{pain: @error_rate_pain, agony: @error_rate_agony},
        queue_depth: %{pain: @queue_depth_pain, agony: @queue_depth_agony}
      },
      history_depth: %{
        response_times: length(state.metric_history.response_times),
        errors: length(state.metric_history.error_counts),
        successes: length(state.metric_history.success_counts)
      }
    }
    
    {:reply, reply, state}
  end
  
  @impl true
  def handle_call(:in_pain?, _from, state) do
    recent_pain = Enum.take(state.pain_signals, 5)
    in_pain = not Enum.empty?(recent_pain) or state.intervention_active
    {:reply, in_pain, state}
  end
  
  @impl true
  # Handle new HLC event format from EventBus
  def handle_info({:event_bus_hlc, event}, state) do
    # Extract event data and forward to existing handler
    handle_info({:event_bus, event.type, event.data}, state)
  end
  
  def handle_info({:event_bus, source, data}, state) do
    # Handle various event types
    state = cond do
      # Health events
      Map.has_key?(data, :health) ->
        subsystem = source |> Atom.to_string() |> String.replace("_health", "") |> String.to_atom()
        
        new_monitors = Map.put(state.monitors, subsystem, %{
          health: data.health,
          last_update: DateTime.utc_now()
        })
        
        new_state = %{state | monitors: new_monitors}
        
        if data.health < (1.0 - @pain_threshold) do
          elem(handle_cast({:pain, subsystem, :health, 1.0 - data.health}, new_state), 1)
        else
          new_state
        end
      
      # HTTP request complete
      source == :http_request_complete ->
        history = state.metric_history
        history = if data[:duration] do
          %{history | response_times: [data.duration | history.response_times] |> Enum.take(1000)}
        else
          history
        end
        
        history = if data[:status] >= 500 do
          %{history | error_counts: [1 | history.error_counts] |> Enum.take(1000)}
        else
          %{history | success_counts: [1 | history.success_counts] |> Enum.take(1000)}
        end
        
        %{state | metric_history: history}
      
      # AMQP message processed
      source == :amqp_message_processed ->
        history = state.metric_history
        history = %{history | 
          success_counts: [1 | history.success_counts] |> Enum.take(1000),
          queue_depths: [data[:queue_length] || 0 | history.queue_depths] |> Enum.take(100)
        }
        %{state | metric_history: history}
      
      # Cache operation
      source == :cache_operation ->
        history = state.metric_history
        history = if data[:hit] do
          %{history | cache_hits: [1 | history.cache_hits] |> Enum.take(1000)}
        else
          %{history | cache_misses: [1 | history.cache_misses] |> Enum.take(1000)}
        end
        %{state | metric_history: history}
      
      # Pattern detected - trigger pleasure
      source == :pattern_detected ->
        elem(handle_cast({:pleasure, :intelligence, :pattern_recognition, 
          @pleasure_threshold + 0.08}, state), 1)
      
      # Optimization applied - trigger pleasure  
      source == :optimization_applied ->
        improvement = data[:improvement] || 0.1
        intensity = @pleasure_threshold + (improvement * 0.1)
        elem(handle_cast({:pleasure, :optimization, :efficiency_gain,
          min(intensity, 1.0)}, state), 1)
      
      # Telemetry update with real metrics
      source == :telemetry_update ->
        history = state.metric_history
        
        # Extract various metrics
        history = if data[:memory] do
          pressure = data.memory.system / data.memory.total
          %{history | memory_readings: [pressure | history.memory_readings] |> Enum.take(100)}
        else
          history
        end
        
        %{state | metric_history: history}
        
      # Other events - ignore
      true ->
        state
    end
    
    {:noreply, state}
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
  
  @impl true
  def handle_info(:calculate_pain_pleasure, state) do
    # Calculate pain/pleasure from real metrics every second
    Process.send_after(self(), :calculate_pain_pleasure, 1000)
    
    # Calculate current metrics
    metrics = calculate_current_metrics(state)
    
    # Assess pain levels with hedonic adaptation
    pain_assessments = assess_pain_levels(metrics, state.hedonic_baselines)
    
    # Assess pleasure levels
    pleasure_assessments = assess_pleasure_levels(metrics, state.hedonic_baselines)
    
    # Process pain signals
    state = Enum.reduce(pain_assessments, state, fn {source, metric, intensity}, acc ->
      if intensity > 0 do
        elem(handle_cast({:pain, source, metric, intensity}, acc), 1)
      else
        acc
      end
    end)
    
    # Process pleasure signals
    state = Enum.reduce(pleasure_assessments, state, fn {source, metric, intensity}, acc ->
      if intensity > 0 do
        elem(handle_cast({:pleasure, source, metric, intensity}, acc), 1)
      else
        acc
      end
    end)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:adapt_baselines, state) do
    # Implement hedonic adaptation - baselines slowly move toward current levels
    Process.send_after(self(), :adapt_baselines, @adaptation_recovery_ms)
    
    current_metrics = calculate_current_metrics(state)
    
    new_baselines = state.hedonic_baselines
    |> Map.merge(current_metrics, fn _key, old_val, new_val ->
      # Slowly adapt baseline toward current value
      old_val + (@adaptation_rate * (new_val - old_val))
    end)
    
    {:noreply, %{state | hedonic_baselines: new_baselines}}
  end
  
  @impl true
  def handle_info({:telemetry_event, measurements, metadata}, state) do
    # Store telemetry measurements in our history
    state = update_metric_history(state, measurements, metadata)
    {:noreply, state}
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
      severity: :warning,  # Regular pain is a warning
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
      severity: :info,  # Pleasure is informational
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
    |> Enum.filter(&(&1.timestamp > cutoff && Map.get(&1, :severity) == :critical))
    |> Enum.map(&(&1.timestamp))
  end
  
  # Real metric calculation from system telemetry
  
  defp calculate_current_metrics(state) do
    %{
      response_time: calculate_avg_response_time(state),
      error_rate: calculate_error_rate(state),
      memory_usage: calculate_memory_pressure(state),
      queue_depth: calculate_queue_depth(state),
      throughput: calculate_throughput(state),
      cache_hit_rate: calculate_cache_hit_rate(state)
    }
  end
  
  defp calculate_avg_response_time(state) do
    recent = Enum.take(state.metric_history.response_times, 100)
    if Enum.empty?(recent) do
      50.0  # Optimistic default
    else
      Enum.sum(recent) / length(recent)
    end
  end
  
  defp calculate_error_rate(state) do
    errors = Enum.take(state.metric_history.error_counts, 100) |> Enum.sum()
    successes = Enum.take(state.metric_history.success_counts, 100) |> Enum.sum()
    total = errors + successes
    
    if total == 0 do
      0.0
    else
      errors / total
    end
  end
  
  defp calculate_memory_pressure(state) do
    recent = Enum.take(state.metric_history.memory_readings, 10)
    if Enum.empty?(recent) do
      # Get current memory from VM
      memory = :erlang.memory()
      total = memory[:total]
      system = memory[:system]
      system / total
    else
      Enum.sum(recent) / length(recent)
    end
  end
  
  defp calculate_queue_depth(state) do
    recent = Enum.take(state.metric_history.queue_depths, 10)
    if Enum.empty?(recent) do
      # Check actual AMQP queue depths if available
      case Process.whereis(AutonomousOpponentV2Core.AMQP.Connection) do
        nil -> 0
        _pid -> 
          # Would need to query actual queue depth from AMQP
          0
      end
    else
      Enum.max(recent)
    end
  end
  
  defp calculate_throughput(state) do
    # Messages processed per second
    successes = Enum.take(state.metric_history.success_counts, 60) |> Enum.sum()
    successes / 60.0  # per second
  end
  
  defp calculate_cache_hit_rate(state) do
    hits = Enum.take(state.metric_history.cache_hits, 100) |> Enum.sum()
    misses = Enum.take(state.metric_history.cache_misses, 100) |> Enum.sum()
    total = hits + misses
    
    if total == 0 do
      0.5  # Neutral default
    else
      hits / total
    end
  end
  
  # Pain assessment with hedonic adaptation
  
  defp assess_pain_levels(metrics, baselines) do
    pain_signals = []
    
    # Response time pain (adapted)
    response_pain = calculate_adapted_pain(
      metrics.response_time,
      baselines.response_time,
      @response_time_pain_ms,
      @response_time_agony_ms
    )
    pain_signals = if response_pain > 0, 
      do: [{:performance, :response_time, response_pain} | pain_signals],
      else: pain_signals
    
    # Error rate pain (less adaptation - errors are always bad)
    error_pain = if metrics.error_rate > @error_rate_agony,
      do: @agony_threshold,
      else: (if metrics.error_rate > @error_rate_pain,
        do: @pain_threshold + ((metrics.error_rate - @error_rate_pain) / (@error_rate_agony - @error_rate_pain) * 0.1),
        else: 0)
    pain_signals = if error_pain > 0,
      do: [{:reliability, :error_rate, error_pain} | pain_signals],
      else: pain_signals
    
    # Memory pressure pain
    memory_pain = if metrics.memory_usage > @memory_pressure_agony,
      do: @agony_threshold,
      else: (if metrics.memory_usage > @memory_pressure_pain,
        do: @pain_threshold + ((metrics.memory_usage - @memory_pressure_pain) / (@memory_pressure_agony - @memory_pressure_pain) * 0.1),
        else: 0)
    pain_signals = if memory_pain > 0,
      do: [{:resources, :memory_pressure, memory_pain} | pain_signals],
      else: pain_signals
    
    # Queue depth pain (variety overload)
    queue_pain = if metrics.queue_depth > @queue_depth_agony,
      do: @agony_threshold,
      else: (if metrics.queue_depth > @queue_depth_pain,
        do: @pain_threshold + ((metrics.queue_depth - @queue_depth_pain) / (@queue_depth_agony - @queue_depth_pain) * 0.1),
        else: 0)
    pain_signals = if queue_pain > 0,
      do: [{:variety, :queue_overload, queue_pain} | pain_signals],
      else: pain_signals
    
    pain_signals
  end
  
  defp calculate_adapted_pain(current, baseline, pain_threshold, agony_threshold) do
    # Adjust thresholds based on hedonic adaptation
    adapted_pain = pain_threshold + (baseline - 50.0) * 0.5
    adapted_agony = agony_threshold + (baseline - 50.0) * 0.5
    
    cond do
      current > adapted_agony -> @agony_threshold
      current > adapted_pain -> 
        @pain_threshold + ((current - adapted_pain) / (adapted_agony - adapted_pain) * 0.1)
      true -> 0
    end
  end
  
  # Pleasure assessment
  
  defp assess_pleasure_levels(metrics, baselines) do
    pleasure_signals = []
    
    # Fast response time pleasure (relative to baseline)
    if metrics.response_time < baselines.response_time * 0.8 do
      intensity = @pleasure_threshold + (1.0 - metrics.response_time / baselines.response_time) * 0.1
      pleasure_signals = [{:performance, :fast_response, min(intensity, 1.0)} | pleasure_signals]
    end
    
    # High throughput pleasure
    if metrics.throughput > baselines.throughput * 1.2 do
      intensity = @pleasure_threshold + (metrics.throughput / baselines.throughput - 1.0) * 0.1
      pleasure_signals = [{:performance, :high_throughput, min(intensity, 1.0)} | pleasure_signals]
    end
    
    # Excellent cache performance
    if metrics.cache_hit_rate > 0.95 do
      pleasure_signals = [{:optimization, :cache_excellence, @pleasure_threshold + 0.05} | pleasure_signals]
    end
    
    # Pattern detection success (from events)
    # This would be triggered by actual pattern detection events
    
    pleasure_signals
  end
  
  # Telemetry handling
  
  def handle_telemetry_event(event_name, measurements, metadata, pid) do
    send(pid, {:telemetry_event, measurements, metadata})
  end
  
  defp update_metric_history(state, measurements, metadata) do
    history = state.metric_history
    
    # Update based on measurement type
    history = case measurements do
      %{duration: duration} when is_number(duration) ->
        # Phoenix endpoint timing
        response_ms = System.convert_time_unit(duration, :native, :millisecond)
        %{history | response_times: [response_ms | history.response_times] |> Enum.take(1000)}
        
      %{total: total, system: system} ->
        # VM memory measurements
        pressure = system / total
        %{history | memory_readings: [pressure | history.memory_readings] |> Enum.take(100)}
        
      _ -> history
    end
    
    # Update based on metadata
    history = case metadata do
      %{status: status} when status >= 500 ->
        %{history | error_counts: [1 | history.error_counts] |> Enum.take(1000)}
        
      %{status: status} when status < 400 ->
        %{history | success_counts: [1 | history.success_counts] |> Enum.take(1000)}
        
      %{hit: true} ->
        %{history | cache_hits: [1 | history.cache_hits] |> Enum.take(1000)}
        
      %{hit: false} ->
        %{history | cache_misses: [1 | history.cache_misses] |> Enum.take(1000)}
        
      _ -> history
    end
    
    %{state | metric_history: history}
  end
  
  # Safe HLC helper with retry and exponential backoff
  defp safe_create_event(subsystem, event_type, data, retries \\ 3) do
    try do
      Clock.create_event(subsystem, event_type, data)
    catch
      :exit, {:noproc, _} when retries > 0 ->
        # HLC process not available yet, wait with exponential backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 50)
        Logger.debug("HLC not available for algedonic event, retrying in #{backoff_ms}ms (#{retries} retries left)")
        Process.sleep(backoff_ms)
        safe_create_event(subsystem, event_type, data, retries - 1)
      
      :exit, {:timeout, _} when retries > 0 ->
        # Timeout, retry with exponential backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 100)
        Logger.debug("HLC timeout for algedonic event, retrying in #{backoff_ms}ms (#{retries} retries left)")
        Process.sleep(backoff_ms)
        safe_create_event(subsystem, event_type, data, retries - 1)
      
      :exit, {:killed, _} when retries > 0 ->
        # Process was killed, retry with backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 75)
        Logger.debug("HLC process killed for algedonic event, retrying in #{backoff_ms}ms (#{retries} retries left)")
        Process.sleep(backoff_ms)
        safe_create_event(subsystem, event_type, data, retries - 1)
      
      :exit, reason ->
        Logger.warning("HLC unavailable for algedonic event after all retries: #{inspect(reason)}")
        {:error, {:hlc_unavailable, reason}}
      
      error ->
        Logger.error("Unexpected error calling HLC for algedonic event: #{inspect(error)}")
        {:error, {:hlc_error, error}}
    end
  end
end