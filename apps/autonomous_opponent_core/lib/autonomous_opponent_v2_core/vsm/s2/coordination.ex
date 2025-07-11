defmodule AutonomousOpponentV2Core.VSM.S2.Coordination do
  @moduledoc """
  System 2: Coordination - The anti-oscillation system.
  
  S2's job is to prevent S1 units from fighting each other.
  When multiple S1 operations compete for resources or work at
  cross-purposes, S2 dampens the oscillations and finds harmony.
  
  Think of it as the conductor of an orchestra - ensuring all
  instruments play in harmony rather than cacophony.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: Algedonic
  
  defstruct [
    :s1_units,
    :oscillation_detector,
    :damping_controller,
    :resource_pools,
    :coordination_rules,
    :conflict_history,
    :health_metrics,
    :resource_allocations,
    :phase_controller,
    :serialization_queue
  ]
  
  # Oscillation detection parameters
  @oscillation_window 5_000  # 5 seconds
  @oscillation_threshold 3   # 3 conflicts = oscillation
  @damping_factor 0.7       # Reduce by 30% when dampening
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def coordinate_request(s1_unit, request) do
    GenServer.call(__MODULE__, {:coordinate, s1_unit, request})
  end
  
  def report_conflict(unit1, unit2, resource) do
    GenServer.cast(__MODULE__, {:conflict, unit1, unit2, resource})
  end
  
  def get_coordination_state do
    GenServer.call(__MODULE__, :get_state)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to S1 variety reports via variety channel
    EventBus.subscribe(:s2_coordination)  # Changed from :s1_operations - now receives from variety channel
    EventBus.subscribe(:s5_policy)  # Policy constraints shape coordination
    
    # Start monitoring
    Process.send_after(self(), :detect_oscillations, 1000)
    Process.send_after(self(), :report_health, 1000)
    
    state = %__MODULE__{
      s1_units: %{},  # Track all S1 units and their states
      oscillation_detector: init_oscillation_detector(),
      damping_controller: init_damping_controller(),
      resource_pools: init_resource_pools(),
      coordination_rules: %{
        max_concurrent: 10,
        resource_sharing: :cooperative,
        conflict_resolution: :priority_based
      },
      conflict_history: [],
      health_metrics: %{
        conflicts_resolved: 0,
        oscillations_dampened: 0,
        coordination_efficiency: 1.0,
        last_efficiency_calc: System.monotonic_time(:millisecond)
      },
      resource_allocations: %{},  # Track actual allocations per unit
      phase_controller: init_phase_controller(),
      serialization_queue: :queue.new()
    }
    
    Logger.info("S2 Coordination online - maintaining harmony")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:coordinate, s1_unit, request}, _from, state) do
    # Check if this request would cause conflict
    case detect_potential_conflict(s1_unit, request, state) do
      {:conflict, conflicting_unit, resource} ->
        # Resolve conflict before it happens
        resolution = resolve_conflict(s1_unit, conflicting_unit, resource, state)
        
        case resolution do
          {:proceed, allocation} ->
            new_state = update_s1_allocation(state, s1_unit, allocation)
            {:reply, {:ok, allocation}, new_state}
            
          {:wait, delay} ->
            # Tell S1 to wait (dampening)
            {:reply, {:wait, delay}, state}
        end
        
      :no_conflict ->
        # Clear to proceed
        allocation = allocate_resources(request, state)
        new_state = update_s1_allocation(state, s1_unit, allocation)
        
        # Report coordination success to S3
        report_to_s3(s1_unit, allocation)
        
        {:reply, {:ok, allocation}, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_state, _from, state) do
    coordination_state = %{
      active_units: map_size(state.s1_units),
      resource_utilization: calculate_resource_utilization(state),
      oscillation_risk: calculate_oscillation_risk(state),
      health: calculate_health_score(state)
    }
    
    {:reply, coordination_state, state}
  end
  
  @impl true
  def handle_cast({:conflict, unit1, unit2, resource}, state) do
    # Record conflict for pattern detection
    conflict = %{
      units: [unit1, unit2],
      resource: resource,
      timestamp: System.monotonic_time(:millisecond)
    }
    
    new_history = [conflict | state.conflict_history]
    |> Enum.take(100)  # Keep last 100 conflicts
    
    # Check if this indicates oscillation
    new_state = %{state | conflict_history: new_history}
    
    if detecting_oscillation?(new_history) do
      Logger.warning("S2 detected oscillation between #{unit1} and #{unit2}")
      handle_oscillation(unit1, unit2, resource, new_state)
    else
      {:noreply, new_state}
    end
  end
  
  @impl true
  # Handle new HLC event format from EventBus
  def handle_info({:event_bus_hlc, event}, state) do
    # Extract event data and forward to existing handler
    handle_info({:event, event.type, event.data}, state)
  end

  @impl true
  def handle_info({:event, :s1_operations, s1_report}, state) do
    # Update S1 unit state - handle missing unit_id gracefully
    unit_id = Map.get(s1_report, :unit_id, :default_unit)
    
    new_s1_units = Map.put(state.s1_units, unit_id, %{
      load: s1_report.current_load,
      resources: s1_report.resources_held,
      last_update: DateTime.utc_now()
    })
    
    # Check for emerging patterns
    if coordination_degrading?(new_s1_units) do
      apply_preventive_dampening(state)
    end
    
    # Forward aggregated view to S3
    VarietyChannel.transmit(:s2_to_s3, %{
      coordination_state: summarize_coordination(new_s1_units),
      resource_pressure: calculate_resource_pressure(state),
      intervention_recommended: needs_intervention?(state)
    })
    
    {:noreply, %{state | s1_units: new_s1_units}}
  end
  
  @impl true
  def handle_info({:event, :s5_policy, _policy_update}, state) do
    # Handle policy updates from S5
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :all_subsystems, _broadcast}, state) do
    # Handle system-wide broadcasts
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :s2_coordination, variety_data}, state) do
    # Handle variety from S1 via variety channel
    Logger.debug("S2 received variety data: #{inspect(variety_data.variety_type)}")
    
    case variety_data.variety_type do
      :operational ->
        # Process operational variety from S1
        new_state = process_operational_variety(variety_data, state)
        
        # Forward coordinated view to S3
        VarietyChannel.transmit(:s2_to_s3, %{
          patterns: variety_data.patterns,
          resource_requirements: analyze_resource_needs(variety_data),
          intervention_needed: variety_data.volume > 1000,
          timestamp: DateTime.utc_now()
        })
        
        {:noreply, new_state}
        
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:detect_oscillations, state) do
    Process.send_after(self(), :detect_oscillations, 1000)
    
    # Analyze recent conflicts for oscillation patterns
    oscillations = detect_oscillation_patterns(state.conflict_history)
    
    if Enum.any?(oscillations) do
      Enum.each(oscillations, fn pattern ->
        dampen_oscillation(pattern, state)
      end)
      
      new_metrics = update_metrics(state.health_metrics, :oscillations_dampened, length(oscillations))
      {:noreply, %{state | health_metrics: new_metrics}}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:report_health, state) do
    Process.send_after(self(), :report_health, 1000)
    
    health = calculate_health_score(state)
    EventBus.publish(:s2_health, %{
      health: health,
      resource_utilization: calculate_resource_utilization(state),
      active_conflicts: length(state.conflict_history),
      dampening_active: MapSet.size(state.damping_controller.affected_units) > 0,
      coordination_efficiency: state.health_metrics.coordination_efficiency
    })
    
    # Check pain thresholds
    cond do
      health < 0.3 ->
        Algedonic.report_pain(:s2_coordination, :health, 1.0 - health)
        
      state.health_metrics.coordination_efficiency < 0.5 ->
        Algedonic.report_pain(:s2_coordination, :efficiency, 
          1.0 - state.health_metrics.coordination_efficiency)
        
      health > 0.9 ->
        Algedonic.report_pleasure(:s2_coordination, :harmony, health)
        
      true ->
        :ok
    end
    
    # Publish VSM pattern events for HNSW streaming
    publish_pattern_events(state)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:update_efficiency, new_efficiency}, state) do
    {:noreply, put_in(state.health_metrics.coordination_efficiency, new_efficiency)}
  end
  
  # Private Functions
  
  defp init_oscillation_detector do
    %{
      patterns: %{},  # unit_pair => [timestamps]
      detection_window: @oscillation_window,
      threshold: @oscillation_threshold,
      active_oscillations: %{},  # unit_pair => %{frequency, amplitude, phase}
      pattern_history: []  # Historical patterns for learning
    }
  end
  
  defp init_damping_controller do
    %{
      damping_active: %{},  # unit => damping_info
      damping_factor: @damping_factor,
      affected_units: MapSet.new(),
      time_division_slots: %{},  # unit => assigned_slot
      phase_shifts: %{}  # unit => phase_offset
    }
  end
  
  defp init_resource_pools do
    # Get actual system resources
    memory_info = :erlang.memory()
    schedulers = :erlang.system_info(:schedulers_online)
    
    %{
      cpu: %{
        total: schedulers * 100,  # 100% per scheduler
        allocated: 0,
        reservations: %{}  # unit => amount
      },
      memory: %{
        total: memory_info[:total],
        allocated: 0,
        reservations: %{}
      },
      io: %{
        total: 1000,  # IO operations per second
        allocated: 0,
        reservations: %{}
      },
      network: %{
        total: 10_000,  # Network operations per second  
        allocated: 0,
        reservations: %{}
      }
    }
  end
  
  defp init_phase_controller do
    %{
      phases: %{},  # unit => current_phase (0.0 to 1.0)
      phase_velocity: %{},  # unit => radians/sec
      synchronization_groups: [],  # Groups of units that should be in phase
      desync_groups: []  # Groups that should be out of phase
    }
  end
  
  defp detect_potential_conflict(s1_unit, request, state) do
    # Check if request would conflict with existing allocations
    requested_resources = extract_resource_requirements(request)
    
    Enum.find_value(state.s1_units, :no_conflict, fn {unit_id, unit_state} ->
      if unit_id != s1_unit && resources_conflict?(requested_resources, unit_state.resources) do
        {:conflict, unit_id, find_conflicting_resource(requested_resources, unit_state.resources)}
      else
        nil
      end
    end)
  end
  
  defp resolve_conflict(unit1, unit2, resource, state) do
    # Apply coordination rules
    case state.coordination_rules.conflict_resolution do
      :priority_based ->
        if has_priority?(unit1, unit2, state) do
          {:proceed, allocate_resources(resource, state)}
        else
          {:wait, calculate_wait_time(state)}
        end
        
      :cooperative ->
        # Share resources
        shared_allocation = divide_resource(resource, 2)
        {:proceed, shared_allocation}
        
      :round_robin ->
        # Take turns
        if is_units_turn?(unit1, state) do
          {:proceed, allocate_resources(resource, state)}
        else
          {:wait, 100}
        end
    end
  end
  
  defp detecting_oscillation?(conflict_history) do
    recent_conflicts = Enum.take(conflict_history, 20)
    
    # Count conflicts in window
    window_start = System.monotonic_time(:millisecond) - @oscillation_window
    
    # Group by unit pairs to detect repeated conflicts
    conflict_pairs = recent_conflicts
    |> Enum.filter(&(&1.timestamp > window_start))
    |> Enum.group_by(fn conflict -> 
      conflict.units |> Enum.sort() |> Enum.join("-")
    end)
    
    # Check if any pair has threshold conflicts
    Enum.any?(conflict_pairs, fn {_pair, conflicts} ->
      length(conflicts) >= @oscillation_threshold &&
      has_oscillation_pattern?(conflicts)
    end)
  end
  
  defp has_oscillation_pattern?(conflicts) do
    # Check if conflicts show a regular pattern (oscillation)
    timestamps = Enum.map(conflicts, & &1.timestamp)
    
    case timestamps do
      [_] -> false
      [t1, t2] -> true  # Two conflicts could be start of oscillation
      timestamps ->
        # Calculate intervals between conflicts
        intervals = timestamps
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [t1, t2] -> t2 - t1 end)
        
        # Check if intervals are regular (within 20% variance)
        avg_interval = Enum.sum(intervals) / length(intervals)
        variance = Enum.map(intervals, fn i -> abs(i - avg_interval) / avg_interval end)
        |> Enum.max()
        
        variance < 0.2  # Regular pattern detected
    end
  end
  
  defp handle_oscillation(unit1, unit2, _resource, state) do
    Logger.warning("S2 dampening oscillation between #{unit1} and #{unit2}")
    
    # Apply dampening
    damping_command = %{
      type: :dampen,
      units: [unit1, unit2],
      factor: @damping_factor,
      duration: 5000
    }
    
    # Tell S3 to enforce dampening
    EventBus.publish(:s3_control, {:dampening_required, damping_command})
    
    # Update metrics
    new_metrics = update_metrics(state.health_metrics, :oscillations_dampened, 1)
    
    {:noreply, %{state | 
      health_metrics: new_metrics,
      damping_controller: %{state.damping_controller | 
        damping_active: true,
        affected_units: [unit1, unit2]
      }
    }}
  end
  
  defp detect_oscillation_patterns(conflict_history) do
    # Group conflicts by participating units
    now = System.monotonic_time(:millisecond)
    window_start = now - @oscillation_window
    
    conflict_history
    |> Enum.filter(&(&1.timestamp > window_start))
    |> Enum.group_by(fn conflict -> 
      conflict.units |> Enum.sort() |> Enum.join("-")
    end)
    |> Enum.filter(fn {_key, conflicts} ->
      length(conflicts) >= @oscillation_threshold
    end)
    |> Enum.map(fn {units_key, conflicts} ->
      units = String.split(units_key, "-")
      timestamps = Enum.map(conflicts, & &1.timestamp) |> Enum.sort()
      
      # Calculate oscillation characteristics
      {frequency, amplitude, phase} = analyze_oscillation(timestamps, conflicts)
      
      %{
        units: units,
        frequency: frequency,  # Conflicts per second
        amplitude: amplitude,  # Resource consumption variance
        phase: phase,         # Current phase in cycle
        resources: Enum.map(conflicts, & &1.resource) |> Enum.uniq(),
        pattern_type: classify_pattern(frequency, amplitude),
        severity: calculate_severity(frequency, amplitude, length(conflicts))
      }
    end)
    |> Enum.filter(&(&1.severity > 0.3))  # Only significant oscillations
  end
  
  defp analyze_oscillation(timestamps, conflicts) do
    # Calculate frequency from intervals
    intervals = timestamps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [t1, t2] -> t2 - t1 end)
    
    avg_interval = if Enum.empty?(intervals), do: 1000, else: Enum.sum(intervals) / length(intervals)
    frequency = 1000.0 / avg_interval  # Convert to Hz
    
    # Calculate amplitude from resource usage variance
    resource_values = conflicts
    |> Enum.map(fn c -> 
      req = extract_resource_requirements(c[:request] || %{})
      req.cpu + req.memory / 1000 + req.io + req.network
    end)
    
    amplitude = if Enum.empty?(resource_values) do
      0.0
    else
      mean = Enum.sum(resource_values) / length(resource_values)
      variance = Enum.map(resource_values, fn v -> :math.pow(v - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(resource_values))
      :math.sqrt(variance)
    end
    
    # Calculate phase (where in cycle we are)
    phase = if length(timestamps) > 0 do
      last_timestamp = List.last(timestamps)
      time_since_last = System.monotonic_time(:millisecond) - last_timestamp
      rem(round(time_since_last / avg_interval * 2 * :math.pi()), round(2 * :math.pi())) / (2 * :math.pi())
    else
      0.0
    end
    
    {frequency, amplitude, phase}
  end
  
  defp classify_pattern(frequency, amplitude) do
    cond do
      frequency > 2.0 && amplitude > 50 -> :high_frequency_oscillation
      frequency > 1.0 && amplitude > 30 -> :resonance
      frequency > 0.5 -> :periodic_conflict
      frequency > 0.1 -> :slow_oscillation
      true -> :sporadic
    end
  end
  
  defp calculate_severity(frequency, amplitude, conflict_count) do
    # Severity based on frequency, amplitude, and persistence
    base_severity = frequency * amplitude / 100
    persistence_factor = min(conflict_count / 10, 2.0)
    
    min(base_severity * persistence_factor, 1.0)
  end
  
  defp dampen_oscillation(pattern, state) do
    # Apply appropriate damping based on pattern type
    damping_strategy = case pattern.pattern_type do
      :high_frequency_oscillation -> 
        apply_time_division_multiplexing(pattern, state)
      :resonance -> 
        apply_phase_shifting(pattern, state)
      :periodic_conflict -> 
        apply_serialization(pattern, state)
      :slow_oscillation -> 
        apply_rate_limiting(pattern, state)
      _ -> 
        apply_basic_dampening(pattern, state)
    end
    
    # Send specific dampening commands to affected units
    Enum.each(pattern.units, fn unit ->
      unit_command = Map.get(damping_strategy, unit, %{type: :basic, factor: @damping_factor})
      
      # Publish to specific S1 unit event channel
      EventBus.publish(String.to_atom("s1_#{unit}"), {:apply_dampening, unit_command})
    end)
    
    # Report pattern and solution to S4 for learning
    VarietyChannel.transmit(:s2_to_s4, %{
      oscillation_pattern: pattern,
      damping_applied: damping_strategy,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp apply_time_division_multiplexing(pattern, state) do
    # Assign time slots to conflicting units
    units = pattern.units
    slot_duration = 100  # milliseconds
    
    units
    |> Enum.with_index()
    |> Enum.map(fn {unit, index} ->
      {unit, %{
        type: :time_division,
        slot: index,
        slot_duration: slot_duration,
        total_slots: length(units),
        start_offset: index * slot_duration
      }}
    end)
    |> Map.new()
  end
  
  defp apply_phase_shifting(pattern, state) do
    # Shift phases to prevent synchronous conflicts
    units = pattern.units
    phase_shift = 2 * :math.pi() / length(units)
    
    units
    |> Enum.with_index()
    |> Enum.map(fn {unit, index} ->
      {unit, %{
        type: :phase_shift,
        phase_offset: index * phase_shift,
        frequency_adjustment: 0.95 + (index * 0.02),  # Slight frequency detuning
        damping_factor: @damping_factor
      }}
    end)
    |> Map.new()
  end
  
  defp apply_serialization(pattern, state) do
    # Force sequential access to contested resources
    units = pattern.units
    
    # Create serialization queue
    queue_id = :erlang.unique_integer([:positive])
    
    units
    |> Enum.map(fn unit ->
      {unit, %{
        type: :serialization,
        queue_id: queue_id,
        resources: pattern.resources,
        max_hold_time: 50,  # milliseconds
        priority: calculate_unit_priority(unit, state)
      }}
    end)
    |> Map.new()
  end
  
  defp apply_rate_limiting(pattern, _state) do
    # Limit request rate for oscillating units
    units = pattern.units
    
    # Calculate appropriate rate limit based on frequency
    rate_limit = max(1, round(1000 / (pattern.frequency * 2)))  # Half the oscillation rate
    
    units
    |> Enum.map(fn unit ->
      {unit, %{
        type: :rate_limit,
        requests_per_second: rate_limit,
        burst_size: rate_limit * 2,
        cooldown_ms: 100
      }}
    end)
    |> Map.new()
  end
  
  defp apply_basic_dampening(pattern, _state) do
    # Fallback to basic damping factor
    pattern.units
    |> Enum.map(fn unit ->
      {unit, %{
        type: :basic,
        factor: @damping_factor,
        duration: 1000
      }}
    end)
    |> Map.new()
  end
  
  defp calculate_unit_priority(unit, state) do
    # Calculate priority based on current allocation and history
    unit_state = Map.get(state.s1_units, unit, %{})
    allocation_history = get_in(state.resource_allocations, [unit, :history]) || []
    
    # Higher priority for units with lower recent usage
    recent_usage = allocation_history
    |> Enum.take(5)
    |> Enum.map(fn alloc -> 
      Map.get(alloc, :cpu, 0) + Map.get(alloc, :memory, 0) / 1000
    end)
    |> Enum.sum()
    
    # Invert usage for priority (lower usage = higher priority)
    100 - min(recent_usage, 100)
  end
  
  defp calculate_health_score(state) do
    # Real health calculation based on actual metrics
    
    # 1. Resource utilization efficiency (0-1)
    utilization = calculate_resource_utilization(state)
    utilization_score = if utilization > 0.9 do
      0.5 - (utilization - 0.9) * 5  # Penalty for over-utilization
    else
      utilization  # Good up to 90%
    end
    
    # 2. Conflict resolution effectiveness (0-1)
    recent_conflicts = Enum.filter(state.conflict_history, fn c ->
      c.timestamp > System.monotonic_time(:millisecond) - 60_000  # Last minute
    end)
    conflict_score = max(0, 1.0 - (length(recent_conflicts) / 20))
    
    # 3. Oscillation control (0-1)
    oscillation_patterns = detect_oscillation_patterns(state.conflict_history)
    oscillation_score = max(0, 1.0 - (length(oscillation_patterns) / 5))
    
    # 4. Response time (based on coordination efficiency)
    efficiency_score = state.health_metrics.coordination_efficiency
    
    # 5. Active dampening penalty
    active_dampening = MapSet.size(state.damping_controller.affected_units)
    dampening_score = max(0, 1.0 - (active_dampening / 10))
    
    # Weighted average
    health = (utilization_score * 0.2 + 
              conflict_score * 0.25 + 
              oscillation_score * 0.25 + 
              efficiency_score * 0.2 + 
              dampening_score * 0.1)
    
    # Update efficiency metric based on actual coordination performance
    if System.monotonic_time(:millisecond) - state.health_metrics.last_efficiency_calc > 5000 do
      new_efficiency = calculate_coordination_efficiency(state)
      Process.send(self(), {:update_efficiency, new_efficiency}, [])
    end
    
    health
  end
  
  defp calculate_coordination_efficiency(state) do
    # Measure how efficiently we're coordinating resources
    
    # 1. Resource allocation efficiency
    pools = state.resource_pools
    total_capacity = pools.cpu.total + pools.memory.total / 1_000_000 + 
                     pools.io.total + pools.network.total
    total_allocated = pools.cpu.allocated + pools.memory.allocated / 1_000_000 + 
                      pools.io.allocated + pools.network.allocated
    
    allocation_efficiency = if total_capacity > 0 do
      min(total_allocated / total_capacity, 1.0)
    else
      0.0
    end
    
    # 2. Conflict prevention rate
    prevented_conflicts = state.health_metrics.conflicts_resolved
    total_attempts = prevented_conflicts + length(state.conflict_history)
    prevention_rate = if total_attempts > 0 do
      prevented_conflicts / total_attempts
    else
      1.0
    end
    
    # 3. Time to resolve conflicts (based on queue length)
    queue_efficiency = case :queue.len(state.serialization_queue) do
      0 -> 1.0
      n when n < 5 -> 0.8
      n when n < 10 -> 0.6
      _ -> 0.4
    end
    
    # Combined efficiency
    (allocation_efficiency * 0.4 + prevention_rate * 0.4 + queue_efficiency * 0.2)
  end
  
  defp coordination_degrading?(s1_units) do
    # Check if coordination efficiency is dropping
    active_units = Enum.count(s1_units, fn {_id, unit} ->
      unit.load > 0.5
    end)
    
    active_units > 5  # Too many active units risks chaos
  end
  
  defp apply_preventive_dampening(_state) do
    Logger.info("S2 applying preventive dampening")
    
    # Reduce all S1 activity by damping factor
    EventBus.publish(:all_s1_units, {:preventive_damping, @damping_factor})
    
    # Also notify S3 for control adjustment
    EventBus.publish(:s3_control, {:dampening_applied, @damping_factor})
  end
  
  defp report_to_s3(s1_unit, allocation) do
    VarietyChannel.transmit(:s2_to_s3, %{
      unit: s1_unit,
      allocation: allocation,
      timestamp: DateTime.utc_now()
    })
  end
  
  # Utility functions
  
  defp extract_resource_requirements(request) do
    # Extract what resources this request needs
    %{
      cpu: Map.get(request, :cpu_required, 10),
      memory: Map.get(request, :memory_required, 20),
      io: Map.get(request, :io_required, 5),
      network: Map.get(request, :network_required, 2),
      exclusive: Map.get(request, :exclusive_lock, false)
    }
  end
  
  defp resources_conflict?(req1, req2) do
    # Check if resources would conflict
    cond do
      # Exclusive locks always conflict
      req1[:exclusive] || req2[:exclusive] -> true
      
      # Check if combined usage exceeds limits
      (req1[:cpu] || 0) + (req2[:cpu] || 0) > 80 -> true
      (req1[:memory] || 0) + (req2[:memory] || 0) > 80 -> true
      (req1[:io] || 0) + (req2[:io] || 0) > 50 -> true
      
      true -> false
    end
  end
  
  defp find_conflicting_resource(req1, req2) do
    cond do
      req1[:exclusive] || req2[:exclusive] -> :exclusive_lock
      (req1[:cpu] || 0) + (req2[:cpu] || 0) > 80 -> :cpu
      (req1[:memory] || 0) + (req2[:memory] || 0) > 80 -> :memory
      (req1[:io] || 0) + (req2[:io] || 0) > 50 -> :io
      true -> :unknown
    end
  end
  
  defp allocate_resources(request, state) do
    pools = state.resource_pools
    requirements = extract_resource_requirements(request)
    
    # Calculate real available resources
    available = %{
      cpu: pools.cpu.total - pools.cpu.allocated,
      memory: pools.memory.total - pools.memory.allocated,
      io: pools.io.total - pools.io.allocated,
      network: pools.network.total - pools.network.allocated
    }
    
    # Allocate what's requested or what's available
    allocation = %{
      cpu: min(requirements.cpu, available.cpu),
      memory: min(requirements.memory, available.memory),
      io: min(requirements.io, available.io),
      network: min(requirements.network, available.network),
      allocated_at: System.monotonic_time(:millisecond)
    }
    
    allocation
  end
  
  defp update_s1_allocation(state, unit, allocation) do
    # Update unit state
    updated_units = Map.update(state.s1_units, unit, 
      %{resources_held: allocation, last_update: DateTime.utc_now()},
      fn existing -> 
        %{existing | resources_held: allocation, last_update: DateTime.utc_now()}
      end
    )
    
    # Update resource pools with actual allocation
    updated_pools = update_resource_pools(state.resource_pools, unit, allocation)
    
    # Track allocation history
    updated_allocations = Map.put(state.resource_allocations, unit, %{
      current: allocation,
      history: [allocation | Map.get(state.resource_allocations[unit] || %{}, :history, [])] |> Enum.take(10)
    })
    
    %{state | 
      s1_units: updated_units,
      resource_pools: updated_pools,
      resource_allocations: updated_allocations
    }
  end
  
  defp update_resource_pools(pools, unit, allocation) do
    # Update each pool with the new allocation
    pools
    |> update_pool(:cpu, unit, allocation.cpu)
    |> update_pool(:memory, unit, allocation.memory)
    |> update_pool(:io, unit, allocation.io)
    |> update_pool(:network, unit, allocation.network)
  end
  
  defp update_pool(pools, resource_type, unit, amount) do
    pool = pools[resource_type]
    
    # Remove previous reservation if exists
    old_amount = pool.reservations[unit] || 0
    new_reservations = Map.put(pool.reservations, unit, amount)
    new_allocated = pool.allocated - old_amount + amount
    
    put_in(pools[resource_type], %{pool | 
      allocated: new_allocated,
      reservations: new_reservations
    })
  end
  
  defp calculate_resource_utilization(state) do
    # Calculate real resource usage from pools
    pools = state.resource_pools
    
    # Safely calculate utilization for each resource type
    cpu_util = if pools.cpu.total > 0, do: pools.cpu.allocated / pools.cpu.total, else: 0.0
    memory_util = if pools.memory.total > 0, do: pools.memory.allocated / pools.memory.total, else: 0.0
    io_util = if pools.io.total > 0, do: pools.io.allocated / pools.io.total, else: 0.0
    network_util = if pools.network.total > 0, do: pools.network.allocated / pools.network.total, else: 0.0
    
    utilizations = [cpu_util, memory_util, io_util, network_util]
    
    # Calculate weighted average (CPU and memory are more important)
    weighted_avg = (cpu_util * 0.35 + memory_util * 0.35 + io_util * 0.15 + network_util * 0.15)
    
    # Also track peak utilization
    peak_util = Enum.max(utilizations)
    
    # Return average with peak penalty if any resource is overutilized
    if peak_util > 0.95 do
      min(weighted_avg * 1.2, 1.0)  # Penalty for hitting limits
    else
      weighted_avg
    end
  end
  
  defp calculate_oscillation_risk(state) do
    # Calculate real oscillation risk based on patterns
    patterns = detect_oscillation_patterns(state.conflict_history)
    
    if Enum.empty?(patterns) do
      # No active oscillations, but check for precursors
      recent_conflicts = Enum.filter(state.conflict_history, fn c ->
        c.timestamp > System.monotonic_time(:millisecond) - 10_000
      end)
      
      # Base risk on conflict rate
      base_risk = min(length(recent_conflicts) / 20, 0.3)
      
      # Check for repeating unit pairs (early warning)
      unit_pairs = recent_conflicts
      |> Enum.map(fn c -> c.units |> Enum.sort() |> Enum.join("-") end)
      |> Enum.frequencies()
      
      repeat_risk = unit_pairs
      |> Map.values()
      |> Enum.filter(&(&1 > 1))
      |> length()
      |> Kernel.*(0.1)
      
      min(base_risk + repeat_risk, 0.5)
    else
      # Active oscillations detected
      max_severity = patterns
      |> Enum.map(& &1.severity)
      |> Enum.max()
      
      # Risk based on most severe pattern
      min(0.5 + max_severity * 0.5, 1.0)
    end
  end
  
  defp summarize_coordination(s1_units) do
    %{
      active_units: map_size(s1_units),
      total_load: Enum.sum(Enum.map(s1_units, fn {_id, u} -> u[:load] || 0 end))
    }
  end
  
  defp calculate_resource_pressure(state) do
    # How close to resource limits - max of all resources
    pools = state.resource_pools
    
    pressures = [
      pools.cpu.allocated / pools.cpu.total,
      pools.memory.allocated / pools.memory.total,
      pools.io.allocated / pools.io.total,
      pools.network.allocated / pools.network.total
    ]
    
    Enum.max(pressures)
  end
  
  defp needs_intervention?(state) do
    length(state.conflict_history) > 10
  end
  
  defp update_metrics(metrics, key, increment) do
    Map.update(metrics, key, increment, &(&1 + increment))
  end
  
  defp has_priority?(unit1, unit2, _state) do
    # Priority based on unit ID for now (could be more sophisticated)
    # Use atom ordering if no numbers present
    unit1_str = Atom.to_string(unit1)
    unit2_str = Atom.to_string(unit2)
    
    # Try to extract numbers
    unit1_nums = Regex.scan(~r/\d+/, unit1_str)
    unit2_nums = Regex.scan(~r/\d+/, unit2_str)
    
    case {unit1_nums, unit2_nums} do
      {[[n1] | _], [[n2] | _]} ->
        String.to_integer(n1) <= String.to_integer(n2)
      _ ->
        # Fallback to alphabetical ordering
        unit1_str <= unit2_str
    end
  end
  
  defp calculate_wait_time(state) do
    # Wait time based on resource pressure
    base_wait = 100
    pressure = calculate_resource_pressure(state)
    
    # Higher pressure = longer wait
    round(base_wait * (1 + pressure * 2))
  end
  
  defp divide_resource(resource, divisor) when is_map(resource) do
    # Divide all resource values
    resource
    |> Enum.map(fn {key, value} when is_number(value) -> 
      {key, value / divisor}
      {key, value} -> 
      {key, value}
    end)
    |> Map.new()
  end
  
  defp divide_resource(resource, _divisor) do
    resource
  end
  
  defp is_units_turn?(unit, state) do
    # Simple round-robin based on unit activity
    last_active = Map.get(state.s1_units, unit, %{})[:last_active]
    
    if last_active do
      # Check if enough time has passed
      DateTime.diff(DateTime.utc_now(), last_active, :millisecond) > 50
    else
      true
    end
  end
  
  defp process_operational_variety(variety_data, state) do
    # Update our understanding of operational patterns
    new_metrics = %{state.health_metrics |
      last_efficiency_calc: System.monotonic_time(:millisecond)
    }
    
    %{state | health_metrics: new_metrics}
  end
  
  defp analyze_resource_needs(variety_data) do
    # Analyze patterns to determine resource requirements
    %{
      cpu: if(variety_data.volume > 500, do: :high, else: :medium),
      memory: :medium,
      io: if(length(variety_data.patterns) > 10, do: :high, else: :low)
    }
  end

  # VSM Pattern Publishing - Complete VSM Integration
  defp publish_pattern_events(state) do
    # Publish S2-specific coordination patterns for VSM integration
    try do
      # Create S2 coordination pattern from current state
      pattern_data = %{
        subsystem: "S2",
        type: "coordination_pattern",
        timestamp: DateTime.utc_now(),
        metrics: %{
          health_score: calculate_health_score(state),
          coordination_efficiency: state.health_metrics.coordination_efficiency,
          resource_utilization: calculate_resource_utilization(state),
          active_conflicts: length(state.conflict_history),
          oscillation_risk: calculate_oscillation_risk(state),
          dampening_active: MapSet.size(state.damping_controller.affected_units) > 0
        },
        coordination_data: %{
          active_s1_units: map_size(state.s1_units),
          resource_pressure: calculate_resource_pressure(state),
          conflicts_resolved: state.health_metrics.conflicts_resolved,
          queue_length: :queue.len(state.serialization_queue),
          dampening_units: MapSet.to_list(state.damping_controller.affected_units)
        },
        resource_status: %{
          cpu: state.resource_pools.cpu,
          memory: state.resource_pools.memory,
          io: state.resource_pools.io,
          network: state.resource_pools.network
        }
      }

      # Publish to S2-specific pattern channel
      EventBus.publish(:vsm_s2_patterns, pattern_data)
      
      # Also publish to general VSM pattern flow
      EventBus.publish(:vsm_pattern_flow, pattern_data)
      
      # Publish anti-oscillation patterns
      oscillation_pattern = %{
        subsystem: "S2",
        type: "anti_oscillation_pattern",
        timestamp: DateTime.utc_now(),
        oscillation_detected: not Enum.empty?(detect_oscillation_patterns(state.conflict_history)),
        dampening_factor: @damping_factor,
        affected_units: MapSet.size(state.damping_controller.affected_units),
        conflict_patterns: analyze_conflict_patterns(state.conflict_history),
        intervention_needed: needs_intervention?(state)
      }
      
      EventBus.publish(:vsm_s2_patterns, oscillation_pattern)
      EventBus.publish(:vsm_pattern_flow, oscillation_pattern)
      
    catch
      :exit, {:noproc, _} ->
        # EventBus not available, skip publishing
        :ok
      error ->
        Logger.warning("S2: Failed to publish pattern events: #{inspect(error)}")
    end
  end
  
  defp analyze_conflict_patterns(conflict_history) do
    # Analyze patterns in conflict history
    recent_conflicts = Enum.filter(conflict_history, fn c ->
      c.timestamp > System.monotonic_time(:millisecond) - 30_000  # Last 30 seconds
    end)
    
    %{
      total_recent: length(recent_conflicts),
      resource_conflicts: Enum.frequencies(Enum.map(recent_conflicts, & &1.resource)),
      unit_pairs: recent_conflicts
        |> Enum.map(fn c -> c.units |> Enum.sort() |> Enum.join("-") end)
        |> Enum.frequencies(),
      conflict_rate: length(recent_conflicts) / max(30, 1)  # conflicts per second
    }
  end
end