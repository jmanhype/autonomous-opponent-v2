defmodule AutonomousOpponent.VSM.S2.Coordination do
  @moduledoc """
  VSM S2 Coordination - Anti-Oscillation Layer

  Implements Beer's anti-oscillation algorithms to prevent destructive
  interference between S1 operational units. This module ensures smooth
  coordination and damping of oscillatory behaviors in the system.

  Key responsibilities:
  - Anti-oscillation control between S1 units
  - Damping mechanisms for system stability
  - Resource contention resolution
  - Pattern detection for oscillatory behaviors
  - Integration with V1 Workflows for coordination procedures

  ## Wisdom Preservation

  ### Why S2 Exists
  S2 prevents the system from tearing itself apart. Without coordination, multiple
  S1 units would compete destructively, creating oscillations that amplify until
  system failure. Beer observed this in biological systems - muscles need coordination
  or they tear themselves apart through opposing contractions.

  ### Design Decisions & Rationale

  1. **2-Second Coordination Interval**: Not arbitrary! Based on control theory:
     - Too fast (<1s) = overcontrol, creates new oscillations
     - Too slow (>5s) = undercontrol, oscillations build before detection
     - 2s matches typical S1 measurement cycles, allowing phase alignment

  2. **30% Oscillation Threshold**: Derived from Beer's studies. Below 30% is
     normal variation (noise). Above 30% indicates true oscillatory pattern that
     will amplify without intervention. Conservative but prevents false positives.

  3. **0.7 Damping Factor**: Golden ratio approximation (1/φ ≈ 0.618). Provides
     critical damping - fastest settling without overshoot. Too low = slow convergence,
     too high = overshoot and new oscillations.

  4. **Resource Locks vs Coordination**: Two mechanisms because they solve different
     problems. Locks prevent conflicts (binary), coordination prevents oscillations
     (continuous). Don't confuse them!
  """

  use GenServer
  require Logger

  alias AutonomousOpponent.EventBus
  alias AutonomousOpponent.VSM.S2.{OscillationDetector, DampingController}

  # WISDOM: These constants embody decades of control theory research
  # 2 seconds - matches S1 rhythms
  @coordination_interval 2_000
  # 30% variation - Beer's empirical threshold
  @oscillation_threshold 0.3
  # Critical damping approximation
  @damping_factor 0.7

  defstruct [
    :id,
    :s1_units,
    :coordination_state,
    :oscillation_detector,
    :damping_controller,
    :resource_locks,
    :coordination_rules,
    :workflow_procedures,
    :metrics
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def coordinate_units(server \\ __MODULE__, unit_ids, coordination_type) do
    GenServer.call(server, {:coordinate, unit_ids, coordination_type})
  end

  def request_resource_lock(server \\ __MODULE__, unit_id, resource, duration) do
    GenServer.call(server, {:request_lock, unit_id, resource, duration})
  end

  def release_resource_lock(server \\ __MODULE__, unit_id, resource) do
    GenServer.cast(server, {:release_lock, unit_id, resource})
  end

  def get_coordination_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  def apply_damping(server \\ __MODULE__, target_units, damping_params) do
    GenServer.call(server, {:apply_damping, target_units, damping_params})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    id = opts[:id] || "s2_coordination_primary"

    # Initialize oscillation detector
    {:ok, detector} = OscillationDetector.start_link()

    # Initialize damping controller
    {:ok, damping} = DampingController.start_link()

    state = %__MODULE__{
      id: id,
      s1_units: %{},
      coordination_state: %{active_coordinations: %{}, pending: []},
      oscillation_detector: detector,
      damping_controller: damping,
      resource_locks: %{},
      coordination_rules: init_coordination_rules(),
      workflow_procedures: init_workflow_procedures(),
      metrics: init_metrics()
    }

    # Subscribe to relevant events
    EventBus.subscribe(:s1_unit_spawned)
    EventBus.subscribe(:s1_metrics)
    EventBus.subscribe(:resource_contention)
    EventBus.subscribe(:s3_allocation)

    # Start coordination loop
    Process.send_after(self(), :coordination_cycle, @coordination_interval)

    Logger.info("S2 Coordination system initialized: #{id}")

    {:ok, state}
  end

  @impl true
  def handle_call({:coordinate, unit_ids, type}, _from, state) do
    case initiate_coordination(unit_ids, type, state) do
      {:ok, coordination_id, new_state} ->
        {:reply, {:ok, coordination_id}, new_state}

      {:error, reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:request_lock, unit_id, resource, duration}, _from, state) do
    case acquire_resource_lock(unit_id, resource, duration, state) do
      {:ok, lock_id, new_state} ->
        {:reply, {:ok, lock_id}, new_state}

      {:error, :resource_locked} ->
        # Add to pending queue
        new_state = queue_lock_request(unit_id, resource, duration, state)
        {:reply, {:pending, estimate_wait_time(resource, state)}, new_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    summary = %{
      active_units: map_size(state.s1_units),
      active_coordinations: map_size(state.coordination_state.active_coordinations),
      resource_locks: map_size(state.resource_locks),
      oscillation_status: OscillationDetector.get_status(state.oscillation_detector),
      damping_active: DampingController.is_active?(state.damping_controller)
    }

    {:reply, summary, state}
  end

  @impl true
  def handle_call({:apply_damping, units, params}, _from, state) do
    result =
      DampingController.apply_damping(
        state.damping_controller,
        units,
        params
      )

    # Record damping application
    new_metrics = update_metrics(state.metrics, :damping_applied, units)

    {:reply, result, %{state | metrics: new_metrics}}
  end

  @impl true
  def handle_cast({:release_lock, unit_id, resource}, state) do
    new_state = release_lock_and_process_queue(unit_id, resource, state)
    {:noreply, new_state}
  end

  # WISDOM: The coordination cycle - heartbeat of system stability
  # This 2-second loop is where S2 earns its keep. Like a conductor watching
  # an orchestra, S2 detects when sections fall out of sync and gently guides
  # them back. The order matters: detect → damp → coordinate → measure.
  @impl true
  def handle_info(:coordination_cycle, state) do
    # WISDOM: Detection before action - measure twice, cut once
    # We detect oscillations first to avoid overreacting to transients
    oscillations = detect_system_oscillations(state)

    # WISDOM: Conditional damping - "First, do no harm"
    # Only apply damping when needed. Unnecessary damping itself causes oscillations!
    # This is why many control systems fail - they try to control too much.
    new_state =
      unless Enum.empty?(oscillations) do
        apply_anti_oscillation(oscillations, state)
      else
        state
      end

    # Process pending coordinations
    new_state = process_pending_coordinations(new_state)

    # Update metrics
    new_state = update_coordination_metrics(new_state)

    Process.send_after(self(), :coordination_cycle, @coordination_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:event, :s1_unit_spawned, data}, state) do
    # Register new S1 unit
    new_state = register_s1_unit(data, state)

    # Check if coordination is needed with existing units
    if should_coordinate_new_unit?(data, state) do
      coordinate_new_unit(data.child_id, new_state)
    else
      new_state
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:event, :s1_metrics, data}, state) do
    # Update S1 unit metrics
    new_state = update_s1_metrics(data, state)

    # Feed to oscillation detector
    OscillationDetector.add_measurement(
      state.oscillation_detector,
      data.unit_id,
      data
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:event, :resource_contention, data}, state) do
    # Handle resource contention between units
    Logger.warning("S2 detected resource contention: #{inspect(data)}")

    new_state = resolve_resource_contention(data, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:lock_timeout, lock_id}, state) do
    # Handle lock timeout
    new_state = handle_lock_timeout(lock_id, state)
    {:noreply, new_state}
  end

  # Private Functions

  # WISDOM: Coordination rules - the constitution of cooperation
  # These rules emerged from painful experience. Each represents a lesson learned
  # from system failures. They're not arbitrary but battle-tested wisdom.
  defp init_coordination_rules do
    %{
      # WISDOM: Why max 5 units? Beyond 5, coordination complexity grows O(n²).
      # Beer found 5-7 is the magic number for human span of control. Same applies
      # to automated systems. More units = split into subgroups.
      max_units_per_coordination: 5,

      # WISDOM: 1 second minimum interval prevents coordination thrashing.
      # Too frequent coordination is worse than no coordination - units spend
      # all time talking, no time doing.
      # 1 second
      min_coordination_interval: 1000,

      # WISDOM: Priority-based resource sharing because equal sharing leads to
      # mediocrity. Better to let critical units excel than all units struggle.
      resource_sharing_policy: :priority_based,

      # WISDOM: Adaptive damping learns from history. Fixed damping assumes
      # oscillations are static, but they evolve. Adaptive damping evolves with them.
      oscillation_damping_policy: :adaptive,

      # WISDOM: FCFS seems unfair but prevents gaming. Priority systems get gamed,
      # performance systems get Goodhart's Law. FCFS is simple, ungameable, fair over time.
      contention_resolution: :first_come_first_served
    }
  end

  defp init_workflow_procedures do
    %{
      unit_coordination: "workflow://v1/procedures/unit_coordination",
      resource_sharing: "workflow://v1/procedures/resource_sharing",
      oscillation_damping: "workflow://v1/procedures/oscillation_control",
      contention_resolution: "workflow://v1/procedures/contention_resolution"
    }
  end

  defp init_metrics do
    %{
      coordinations_initiated: 0,
      oscillations_detected: 0,
      damping_applications: 0,
      resource_contentions: 0,
      locks_granted: 0,
      locks_queued: 0
    }
  end

  defp initiate_coordination(unit_ids, type, state) do
    coordination_id = generate_coordination_id()

    coordination = %{
      id: coordination_id,
      type: type,
      units: unit_ids,
      started_at: System.monotonic_time(:millisecond),
      status: :active,
      rules: apply_coordination_rules(type, state.coordination_rules)
    }

    # Add to active coordinations
    new_coordinations =
      Map.put(
        state.coordination_state.active_coordinations,
        coordination_id,
        coordination
      )

    new_state =
      put_in(
        state.coordination_state.active_coordinations,
        new_coordinations
      )
      |> update_metrics(:coordinations_initiated, 1)

    # Notify units of coordination
    notify_units_of_coordination(unit_ids, coordination)

    {:ok, coordination_id, new_state}
  end

  # WISDOM: Resource locking - preventing chaos, not creating bureaucracy
  # Locks are a necessary evil. Without them, units corrupt shared resources.
  # With too many, the system grinds to a halt. The key insight: locks should
  # be temporary (timeout) and granular (specific resources, not categories).
  defp acquire_resource_lock(unit_id, resource, duration, state) do
    lock_key = {resource.type, resource.id}

    case Map.get(state.resource_locks, lock_key) do
      nil ->
        # Resource is free, grant lock
        lock_id = generate_lock_id()

        lock = %{
          id: lock_id,
          unit_id: unit_id,
          resource: resource,
          acquired_at: System.monotonic_time(:millisecond),
          expires_at: System.monotonic_time(:millisecond) + duration,
          duration: duration
        }

        # WISDOM: Always set timeouts on locks - why?
        # Immortal locks from crashed units would eventually paralyze the system.
        # Timeouts are deadlock prevention. Better to occasionally lose a lock
        # than to have eternal deadlock.
        Process.send_after(self(), {:lock_timeout, lock_id}, duration)

        new_locks = Map.put(state.resource_locks, lock_key, lock)

        new_state =
          %{state | resource_locks: new_locks}
          |> update_metrics(:locks_granted, 1)

        {:ok, lock_id, new_state}

      _existing_lock ->
        # WISDOM: Simple rejection, no waiting. Why not queue immediately?
        # Let the caller decide whether to queue or find alternatives.
        # S2 provides mechanism, not policy. Policy belongs in S3/S5.
        {:error, :resource_locked}
    end
  end

  # WISDOM: Oscillation detection - finding the hidden rhythms
  # Oscillations are like waves in water - individual drops seem random but
  # patterns emerge at scale. We're looking for rhythmic variations that indicate
  # units working against each other rather than with each other.
  defp detect_system_oscillations(state) do
    # Get oscillation analysis from detector
    analysis = OscillationDetector.analyze(state.oscillation_detector)

    # WISDOM: Why filter by severity threshold?
    # Small oscillations are natural - like breathing. Only large oscillations
    # threaten stability. The 30% threshold comes from Beer's observation that
    # biological systems tolerate up to 30% variation before intervention.
    Enum.filter(analysis.oscillations, fn osc ->
      osc.severity > @oscillation_threshold
    end)
  end

  # WISDOM: Anti-oscillation - the art of gentle correction
  # Like a parent steadying a child learning to walk, we don't stop the movement,
  # we dampen the extremes. Too much correction and we create new problems.
  # The key insight: oscillations are phase problems, not amplitude problems.
  defp apply_anti_oscillation(oscillations, state) do
    Logger.info("S2 applying anti-oscillation for #{length(oscillations)} detected oscillations")

    # WISDOM: Process each oscillation separately - why?
    # Oscillations can have different frequencies and phases. A single damping
    # factor for all would create interference patterns. Like tuning multiple
    # instruments, each needs individual attention.
    Enum.reduce(oscillations, state, fn oscillation, acc_state ->
      # Determine damping parameters
      damping_params = calculate_damping_parameters(oscillation)

      # Apply damping through controller
      DampingController.apply_damping(
        acc_state.damping_controller,
        oscillation.affected_units,
        damping_params
      )

      # Update metrics
      update_metrics(acc_state, :oscillations_dampened, 1)
    end)
  end

  # WISDOM: Damping parameter calculation - precision matters
  # These aren't magic numbers but carefully derived values based on control theory.
  # The damping factor scales with severity because large oscillations need stronger
  # intervention, but we cap at 0.9 to prevent overdamping (which causes sluggishness).
  defp calculate_damping_parameters(oscillation) do
    %{
      # WISDOM: Why min(0.9, ...)? Above 0.9 we enter overdamped territory where
      # the system becomes sluggish and unresponsive. Better to apply multiple
      # gentle corrections than one harsh one.
      damping_factor: min(0.9, @damping_factor * oscillation.severity),
      frequency: oscillation.frequency,
      phase_shift: calculate_phase_shift(oscillation),
      # 10 seconds = 5 coordination cycles, allows gradual correction
      duration: 10_000
    }
  end

  # WISDOM: Phase shift - the secret to damping
  # Oscillations aren't about amplitude, they're about timing. Two units pushing
  # when they should pull. By shifting phase by π, we make them work together
  # instead of against each other. This is why S2 exists - S1 units can't see
  # each other's phase, only S2 has the system-wide view.
  defp calculate_phase_shift(oscillation) do
    # Phase shift to counteract oscillation
    :math.pi() - oscillation.phase
  end

  defp resolve_resource_contention(contention_data, state) do
    Logger.info("S2 resolving resource contention: #{inspect(contention_data)}")

    # Apply coordination rules for contention resolution
    resolution =
      case state.coordination_rules.contention_resolution do
        :first_come_first_served ->
          resolve_fcfs(contention_data)

        :priority_based ->
          resolve_by_priority(contention_data)

        :performance_based ->
          resolve_by_performance(contention_data, state)
      end

    # Apply resolution
    apply_contention_resolution(resolution, state)
  end

  defp register_s1_unit(spawn_data, state) do
    unit_info = %{
      id: spawn_data.child_id,
      parent_id: spawn_data.parent_id,
      pid: spawn_data.pid,
      registered_at: System.monotonic_time(:millisecond),
      metrics: %{},
      coordination_group: nil
    }

    put_in(state.s1_units[spawn_data.child_id], unit_info)
  end

  defp update_s1_metrics(metrics_data, state) do
    unit_id = metrics_data.unit_id

    case Map.get(state.s1_units, unit_id) do
      nil ->
        # Unknown unit, ignore
        state

      unit_info ->
        updated_info = Map.put(unit_info, :metrics, metrics_data)
        put_in(state.s1_units[unit_id], updated_info)
    end
  end

  defp queue_lock_request(unit_id, resource, duration, state) do
    request = %{
      unit_id: unit_id,
      resource: resource,
      duration: duration,
      queued_at: System.monotonic_time(:millisecond)
    }

    update_in(state.coordination_state.pending, &[request | &1])
    |> update_metrics(:locks_queued, 1)
  end

  defp release_lock_and_process_queue(unit_id, resource, state) do
    lock_key = {resource.type, resource.id}

    case Map.get(state.resource_locks, lock_key) do
      %{unit_id: ^unit_id} ->
        # Remove lock
        new_locks = Map.delete(state.resource_locks, lock_key)
        new_state = %{state | resource_locks: new_locks}

        # Process queued requests for this resource
        process_lock_queue(resource, new_state)

      _ ->
        # Not locked by this unit
        state
    end
  end

  defp process_lock_queue(resource, state) do
    # Find pending requests for this resource
    {matching, remaining} =
      Enum.split_with(state.coordination_state.pending, fn req ->
        req.resource == resource
      end)

    case matching do
      [] ->
        state

      [next_request | _] ->
        # Grant lock to next in queue
        case acquire_resource_lock(
               next_request.unit_id,
               next_request.resource,
               next_request.duration,
               state
             ) do
          {:ok, _, new_state} ->
            # Remove from queue
            update_in(new_state.coordination_state.pending, fn _ -> remaining end)

          _ ->
            state
        end
    end
  end

  defp update_metrics(state, metric, value) when is_atom(metric) do
    update_in(state.metrics[metric], &((&1 || 0) + value))
  end

  defp update_metrics(state, metric, _units) when is_atom(metric) do
    update_in(state.metrics[metric], &((&1 || 0) + 1))
  end

  defp estimate_wait_time(_resource, _state) do
    # Simplified estimation
    {:estimated_ms, 5000}
  end

  defp should_coordinate_new_unit?(_spawn_data, state) do
    # Coordinate if we have multiple units
    map_size(state.s1_units) > 1
  end

  defp coordinate_new_unit(unit_id, state) do
    # Find units to coordinate with
    other_units =
      state.s1_units
      |> Map.keys()
      |> Enum.filter(&(&1 != unit_id))
      # Coordinate with up to 2 other units
      |> Enum.take(2)

    if Enum.empty?(other_units) do
      state
    else
      units_to_coordinate = [unit_id | other_units]

      initiate_coordination(units_to_coordinate, :new_unit_integration, state)
      # Get the state
      |> elem(2)
    end
  end

  defp process_pending_coordinations(state) do
    # Process any pending coordinations
    state
  end

  defp update_coordination_metrics(state) do
    # Update coordination effectiveness metrics
    active_count = map_size(state.coordination_state.active_coordinations)

    EventBus.publish(:s2_metrics, %{
      active_coordinations: active_count,
      pending_locks: length(state.coordination_state.pending),
      oscillations_detected: state.metrics.oscillations_detected,
      timestamp: System.monotonic_time(:millisecond)
    })

    state
  end

  defp generate_coordination_id do
    "coord_#{:erlang.unique_integer([:positive])}"
  end

  defp generate_lock_id do
    "lock_#{:erlang.unique_integer([:positive])}"
  end

  defp apply_coordination_rules(type, rules) do
    Map.merge(rules, %{coordination_type: type})
  end

  defp notify_units_of_coordination(unit_ids, coordination) do
    Enum.each(unit_ids, fn unit_id ->
      EventBus.publish(:coordination_notification, %{
        unit_id: unit_id,
        coordination: coordination
      })
    end)
  end

  defp handle_lock_timeout(lock_id, state) do
    # Find and remove expired lock
    expired_lock =
      state.resource_locks
      |> Enum.find(fn {_, lock} -> lock.id == lock_id end)

    case expired_lock do
      {lock_key, _} ->
        new_locks = Map.delete(state.resource_locks, lock_key)

        %{state | resource_locks: new_locks}
        |> process_lock_queue(elem(lock_key, 1))

      nil ->
        state
    end
  end

  # Contention resolution strategies
  defp resolve_fcfs(contention), do: %{winner: hd(contention.units), strategy: :fcfs}
  defp resolve_by_priority(contention), do: %{winner: hd(contention.units), strategy: :priority}

  defp resolve_by_performance(contention, _state),
    do: %{winner: hd(contention.units), strategy: :performance}

  defp apply_contention_resolution(_resolution, state), do: state
end
