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
    :health_metrics
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
    # Subscribe to S1 variety reports
    EventBus.subscribe(:s1_operations)
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
        coordination_efficiency: 1.0
      }
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
            
          {:redirect, alternative} ->
            # Suggest alternative approach
            {:reply, {:redirect, alternative}, state}
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
    if detecting_oscillation?(new_history) do
      Logger.warning("S2 detected oscillation between #{unit1} and #{unit2}")
      handle_oscillation(unit1, unit2, resource, state)
    else
      {:noreply, %{state | conflict_history: new_history}}
    end
  end
  
  @impl true
  def handle_info({:event, :s1_operations, s1_report}, state) do
    # Update S1 unit state
    unit_id = s1_report.unit_id
    
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
    EventBus.publish(:s2_health, %{health: health})
    
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
    
    {:noreply, state}
  end
  
  # Private Functions
  
  defp init_oscillation_detector do
    %{
      patterns: [],
      detection_window: @oscillation_window,
      threshold: @oscillation_threshold
    }
  end
  
  defp init_damping_controller do
    %{
      damping_active: false,
      damping_factor: @damping_factor,
      affected_units: []
    }
  end
  
  defp init_resource_pools do
    %{
      cpu: %{total: 100, allocated: 0},
      memory: %{total: 100, allocated: 0},
      io: %{total: 100, allocated: 0},
      network: %{total: 100, allocated: 0}
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
    recent_conflicts = Enum.take(conflict_history, 10)
    
    # Count conflicts in window
    window_start = System.monotonic_time(:millisecond) - @oscillation_window
    
    conflicts_in_window = recent_conflicts
    |> Enum.filter(&(&1.timestamp > window_start))
    |> length()
    
    conflicts_in_window >= @oscillation_threshold
  end
  
  defp handle_oscillation(unit1, unit2, resource, state) do
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
    conflict_history
    |> Enum.group_by(fn conflict -> 
      conflict.units |> Enum.sort() |> Enum.join("-")
    end)
    |> Enum.filter(fn {_key, conflicts} ->
      length(conflicts) >= @oscillation_threshold
    end)
    |> Enum.map(fn {units_key, conflicts} ->
      %{
        units: String.split(units_key, "-"),
        frequency: length(conflicts),
        resources: Enum.map(conflicts, & &1.resource) |> Enum.uniq()
      }
    end)
  end
  
  defp dampen_oscillation(pattern, _state) do
    # Send dampening commands to affected units
    Enum.each(pattern.units, fn unit ->
      # Publish to specific S1 unit event channel
      EventBus.publish(String.to_atom("s1_#{unit}"), {:apply_dampening, @damping_factor})
    end)
    
    # Report pattern to S4 for learning
    VarietyChannel.transmit(:s2_to_s4, %{
      oscillation_pattern: pattern,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp calculate_health_score(state) do
    metrics = state.health_metrics
    
    # Health based on conflicts and efficiency
    base_health = metrics.coordination_efficiency
    
    # Penalty for unresolved conflicts
    conflict_penalty = length(state.conflict_history) * 0.01
    
    max(0.0, base_health - conflict_penalty)
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
  
  defp allocate_resources(resource, state) do
    pools = state.resource_pools
    
    # Calculate available resources
    available = %{
      cpu: pools.cpu.total - pools.cpu.allocated,
      memory: pools.memory.total - pools.memory.allocated,
      io: pools.io.total - pools.io.allocated,
      network: pools.network.total - pools.network.allocated
    }
    
    # Allocate what's requested or what's available
    %{
      cpu: min(Map.get(resource, :cpu, 10), available.cpu),
      memory: min(Map.get(resource, :memory, 20), available.memory),
      io: min(Map.get(resource, :io, 5), available.io),
      network: min(Map.get(resource, :network, 2), available.network)
    }
  end
  
  defp update_s1_allocation(state, unit, allocation) do
    put_in(state.s1_units[unit], %{resources_held: allocation})
  end
  
  defp calculate_resource_utilization(state) do
    # Calculate overall resource usage
    pools = state.resource_pools
    
    utilizations = [
      pools.cpu.allocated / pools.cpu.total,
      pools.memory.allocated / pools.memory.total,
      pools.io.allocated / pools.io.total,
      pools.network.allocated / pools.network.total
    ]
    
    # Return average utilization
    Enum.sum(utilizations) / length(utilizations)
  end
  
  defp calculate_oscillation_risk(state) do
    # Risk based on recent conflicts
    min(1.0, length(state.conflict_history) / 20)
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
end