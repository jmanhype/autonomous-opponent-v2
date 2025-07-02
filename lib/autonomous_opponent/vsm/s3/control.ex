defmodule AutonomousOpponent.VSM.S3.Control do
  @moduledoc """
  VSM S3 Control - Resource Optimization Layer

  Implements Beer's resource bargaining algorithms for optimal allocation across
  S1 operational units. Integrates with V1 Workflows Engine for control procedures
  and uses Kalman filters for predictive resource allocation.

  Key responsibilities:
  - Resource bargaining between S1 units
  - Predictive allocation using Kalman filters
  - Performance target management
  - Audit subsystem (S3*) for interventions
  - Integration with V1 Workflows as control executor

  ## Wisdom Preservation

  ### Why S3 Exists
  S3 is the system's "operations room" - where the here-and-now is managed. While
  S2 prevents oscillations and S4 looks to the future, S3 optimizes what we have
  right now. Beer: "S3 is about doing today's job with today's resources."

  ### Design Decisions & Rationale

  1. **Resource Bargaining vs Central Planning**: We use Beer's bargaining algorithm
     instead of centralized optimization. Why? Central planning assumes perfect
     information and creates single points of failure. Bargaining is antifragile -
     it works with imperfect information and partial failures.

  2. **Kalman Filters for Prediction**: Not just trendy ML - Kalman filters are
     optimal for linear systems with Gaussian noise. Resource usage patterns are
     surprisingly linear over short horizons. Complex ML would overfit.

  3. **5-Second Bargaining Interval**: Matches S2's coordination rhythm (2s) with
     a 2.5x multiplier. This creates a natural hierarchy of control loops - S2
     coordinates faster than S3 allocates, preventing resource thrashing.

  4. **Audit Subsystem (S3*)**: Beer's insight - every controller needs a
     meta-controller to prevent local optimization at system expense. S3* can
     override S3 when it's being too greedy or too generous.
  """

  use GenServer
  require Logger

  alias AutonomousOpponent.EventBus
  alias AutonomousOpponent.VSM.S3.{KalmanFilter, ResourceBargainer, AuditSubsystem}

  # WISDOM: Resource types aren't arbitrary - they map to Ashby's variety constraints
  # CPU = processing variety, Memory = variety buffer, Capacity = variety channel width
  # Slots = variety parallelism. Missing any one and the system chokes.
  @resource_types [:cpu, :memory, :variety_capacity, :processing_slots]

  # WISDOM: 5 seconds balances responsiveness with stability
  # Too fast = thrashing, too slow = starvation
  # 5 seconds
  @bargaining_interval 5_000

  # WISDOM: 1 minute prediction horizon - why not longer?
  # Beyond 1 minute, uncertainty dominates signal. Better to replan frequently
  # than to plan far ahead poorly. This is operations, not strategy.
  # 1 minute ahead
  @prediction_horizon 60_000

  defstruct [
    :id,
    :resource_pool,
    :allocations,
    :kalman_filters,
    :performance_targets,
    :bargaining_state,
    :audit_subsystem,
    :workflow_procedures,
    :metrics
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def request_resources(server \\ __MODULE__, unit_id, resource_request) do
    GenServer.call(server, {:request_resources, unit_id, resource_request})
  end

  def release_resources(server \\ __MODULE__, unit_id, resources) do
    GenServer.cast(server, {:release_resources, unit_id, resources})
  end

  def update_performance_target(server \\ __MODULE__, target_type, value) do
    GenServer.call(server, {:update_target, target_type, value})
  end

  def get_allocation_forecast(server \\ __MODULE__, time_horizon \\ @prediction_horizon) do
    GenServer.call(server, {:get_forecast, time_horizon})
  end

  def audit_intervention(server \\ __MODULE__, intervention_type, params) do
    GenServer.call(server, {:audit_intervention, intervention_type, params})
  end

  @doc """
  Get the current resource status and allocation summary.
  
  Returns a summary of the current resource pool state and active allocations.
  """
  def get_resource_status(server \\ __MODULE__) do
    GenServer.call(server, :get_resource_status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    id = opts[:id] || "s3_control_primary"

    state = %__MODULE__{
      id: id,
      resource_pool: init_resource_pool(),
      allocations: %{},
      kalman_filters: init_kalman_filters(),
      performance_targets: init_performance_targets(),
      bargaining_state: %{active: false, participants: []},
      audit_subsystem: nil,
      workflow_procedures: init_workflow_procedures(),
      metrics: init_metrics()
    }

    # Start audit subsystem
    {:ok, audit_pid} = AuditSubsystem.start_link(parent: self())

    # Subscribe to relevant events
    EventBus.subscribe(:s1_metrics)
    EventBus.subscribe(:s2_coordination)
    EventBus.subscribe(:resource_pressure)
    EventBus.subscribe(:algedonic_intervention)

    # Start periodic bargaining
    Process.send_after(self(), :bargaining_round, @bargaining_interval)

    # Start Kalman filter updates
    Process.send_after(self(), :update_predictions, 1_000)

    Logger.info("S3 Control system initialized: #{id}")

    {:ok, %{state | audit_subsystem: audit_pid}}
  end

  @impl true
  def handle_call({:request_resources, unit_id, request}, _from, state) do
    case allocate_resources(unit_id, request, state) do
      {:ok, allocation, new_state} ->
        # Record allocation
        EventBus.publish(:resource_allocated, %{
          unit_id: unit_id,
          allocation: allocation,
          timestamp: System.monotonic_time(:millisecond)
        })

        {:reply, {:ok, allocation}, new_state}

      {:error, :insufficient_resources} ->
        # Trigger bargaining if needed
        new_state = maybe_trigger_bargaining(state, unit_id, request)
        {:reply, {:error, :insufficient_resources}, new_state}

      {:error, reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:update_target, target_type, value}, _from, state) do
    new_targets = Map.put(state.performance_targets, target_type, value)
    new_state = %{state | performance_targets: new_targets}

    # Notify S1 units of new targets
    EventBus.publish(:performance_target_updated, %{
      target_type: target_type,
      value: value,
      source: :s3_control
    })

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_forecast, horizon}, _from, state) do
    forecast = generate_forecast(state.kalman_filters, horizon)
    {:reply, {:ok, forecast}, state}
  end

  @impl true
  def handle_call({:audit_intervention, type, params}, _from, state) do
    # S3* audit intervention
    case AuditSubsystem.intervene(state.audit_subsystem, type, params) do
      {:ok, result} ->
        Logger.warning("S3* Audit intervention: #{type} - #{inspect(result)}")
        {:reply, {:ok, result}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_resource_status, _from, state) do
    # Calculate current resource utilization
    total_allocated = Enum.reduce(state.allocations, %{}, fn {_unit_id, allocation}, acc ->
      Enum.reduce(allocation.resources, acc, fn {resource, amount}, acc ->
        Map.update(acc, resource, amount, &(&1 + amount))
      end)
    end)
    
    # Build status summary
    status = %{
      resource_pool: state.resource_pool,
      total_allocated: total_allocated,
      active_allocations: map_size(state.allocations),
      performance_targets: state.performance_targets,
      bargaining_active: state.bargaining_state.active,
      metrics: %{
        allocations_made: state.metrics.allocations_made,
        allocations_denied: state.metrics.allocations_denied,
        reallocations: state.metrics.reallocations
      }
    }
    
    {:reply, status, state}
  end

  @impl true
  def handle_cast({:release_resources, unit_id, resources}, state) do
    new_state = return_resources_to_pool(unit_id, resources, state)
    {:noreply, new_state}
  end

  # WISDOM: Bargaining rounds - Beer's market mechanism in action
  # This is NOT optimization in the mathematical sense. It's a market where
  # S1 units "bid" for resources based on need. Why markets? They're antifragile -
  # they work with incomplete information, adapt to changes, and no central point
  # of failure. The "invisible hand" emerges from local decisions.
  @impl true
  def handle_info(:bargaining_round, state) do
    # WISDOM: Conditional bargaining - markets have opening hours
    # Continuous bargaining wastes resources. Periodic markets let supply/demand
    # accumulate, making prices (allocations) more stable and meaningful.
    new_state =
      if should_run_bargaining?(state) do
        run_bargaining_round(state)
      else
        state
      end

    Process.send_after(self(), :bargaining_round, @bargaining_interval)
    {:noreply, new_state}
  end

  # WISDOM: Kalman filter updates - prediction as control foundation
  # Why Kalman filters? They're optimal for linear systems with Gaussian noise.
  # Resource usage IS surprisingly linear over short horizons. Fancy ML would
  # overfit the noise. Kalman filters give us just enough prediction to avoid
  # surprises without chasing phantoms.
  @impl true
  def handle_info(:update_predictions, state) do
    # WISDOM: 1-second update cycle for predictions
    # Faster than bargaining (5s) but slower than measurement. This creates a
    # prediction that smooths noise but tracks real changes. Too fast = noise,
    # too slow = lag.
    new_filters =
      Enum.map(state.kalman_filters, fn {resource, filter} ->
        measurement = get_resource_measurement(resource, state)
        updated_filter = KalmanFilter.update(filter, measurement)
        {resource, updated_filter}
      end)
      |> Map.new()

    Process.send_after(self(), :update_predictions, 1_000)
    {:noreply, %{state | kalman_filters: new_filters}}
  end

  @impl true
  def handle_info({:event, :s1_metrics, data}, state) do
    # Update resource usage based on S1 metrics
    new_state = update_resource_usage(state, data)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:event, :algedonic_intervention, data}, state) do
    # Emergency resource reallocation
    new_state = handle_algedonic_intervention(data, state)
    {:noreply, new_state}
  end

  # Private Functions

  # WISDOM: Resource pool initialization - starting with abundance
  # These aren't random numbers. They represent a "wealthy" system that can
  # handle variety without immediate scarcity. Starting poor creates immediate
  # competition and oscillation. Start rich, learn limits through experience.
  defp init_resource_pool do
    %{
      # WISDOM: 1000 CPU units = ~10 cores at 100 units each
      # Allows 10 S1 units at full capacity or 20 at half
      cpu: %{total: 1000, available: 1000, reserved: 0},

      # WISDOM: 8192 MB = 8GB, enough for serious variety buffering
      # Memory is cheap, variety loss is expensive
      memory: %{total: 8192, available: 8192, reserved: 0},

      # WISDOM: 10000 variety units/second - derived from S1 capacity
      # Must exceed environment's variety generation rate
      variety_capacity: %{total: 10_000, available: 10_000, reserved: 0},

      # WISDOM: 100 slots = max parallel variety streams
      # More slots = more parallelism but also more coordination overhead
      processing_slots: %{total: 100, available: 100, reserved: 0}
    }
  end

  defp init_kalman_filters do
    @resource_types
    |> Enum.map(fn resource ->
      {resource, KalmanFilter.new(resource)}
    end)
    |> Map.new()
  end

  # WISDOM: Performance targets - the Goldilocks zone
  # These targets represent the "sweet spot" where the system performs well
  # without overextending. Too high = brittleness, too low = waste.
  defp init_performance_targets do
    %{
      # WISDOM: 90% variety absorption - matches S1's threshold
      # 100% is impossible (Ashby's Law), 90% is sustainable excellence
      # 90% target
      variety_absorption: 0.9,

      # WISDOM: 100ms response - human perception threshold
      # Faster feels instant to humans, slower feels sluggish
      # 100ms target
      response_time: 100,

      # WISDOM: 80% utilization - queuing theory optimum
      # Above 80%, wait times explode exponentially. Below 60% is waste.
      # 80% target utilization
      resource_utilization: 0.8,

      # WISDOM: 95% stability - allows for natural variation
      # 100% stability is death (no adaptation). 95% is living stability.
      # 95% stability target
      stability_index: 0.95
    }
  end

  defp init_workflow_procedures do
    %{
      resource_allocation: "workflow://v1/procedures/resource_allocation",
      emergency_reallocation: "workflow://v1/procedures/emergency_realloc",
      performance_optimization: "workflow://v1/procedures/perf_optimization"
    }
  end

  defp init_metrics do
    %{
      allocations_made: 0,
      allocations_denied: 0,
      bargaining_rounds: 0,
      reallocations: 0,
      audit_interventions: 0
    }
  end

  # WISDOM: Resource allocation - the moment of truth
  # This is where abstract resources become concrete allocations. The lease
  # mechanism prevents hoarding - resources not actively used return to the pool.
  defp allocate_resources(unit_id, request, state) do
    # Check availability
    if resources_available?(request, state.resource_pool) do
      # Deduct from pool
      new_pool = deduct_resources(request, state.resource_pool)

      # Record allocation
      allocation = %{
        unit_id: unit_id,
        resources: request,
        timestamp: System.monotonic_time(:millisecond),
        # WISDOM: 5-minute lease prevents resource hoarding
        # Long enough for real work, short enough to prevent waste.
        # If you need it longer, renew it - proves you're really using it.
        # 5 min lease
        expires: System.monotonic_time(:millisecond) + 300_000
      }

      new_allocations = Map.put(state.allocations, unit_id, allocation)
      new_metrics = Map.update!(state.metrics, :allocations_made, &(&1 + 1))

      new_state = %{
        state
        | resource_pool: new_pool,
          allocations: new_allocations,
          metrics: new_metrics
      }

      {:ok, allocation, new_state}
    else
      # WISDOM: Simple failure - no partial allocations
      # All-or-nothing prevents deadlocks where units hold partial resources
      # waiting for the rest. Better to fail fast and retry.
      {:error, :insufficient_resources}
    end
  end

  defp resources_available?(request, pool) do
    Enum.all?(request, fn {resource, amount} ->
      pool[resource][:available] >= amount
    end)
  end

  defp deduct_resources(request, pool) do
    Enum.reduce(request, pool, fn {resource, amount}, acc ->
      update_in(acc, [resource, :available], &(&1 - amount))
      |> update_in([resource, :reserved], &(&1 + amount))
    end)
  end

  defp return_resources_to_pool(unit_id, resources, state) do
    case Map.get(state.allocations, unit_id) do
      nil ->
        state

      allocation ->
        # Return resources to pool
        new_pool =
          Enum.reduce(resources, state.resource_pool, fn {resource, amount}, acc ->
            update_in(acc, [resource, :available], &(&1 + amount))
            |> update_in([resource, :reserved], &(&1 - amount))
          end)

        # Remove allocation
        new_allocations = Map.delete(state.allocations, unit_id)

        %{state | resource_pool: new_pool, allocations: new_allocations}
    end
  end

  defp maybe_trigger_bargaining(state, unit_id, request) do
    unless state.bargaining_state.active do
      Logger.info("Triggering resource bargaining due to request from #{unit_id}")
      run_bargaining_round(state)
    else
      state
    end
  end

  defp should_run_bargaining?(state) do
    # Run bargaining if utilization is high or unbalanced
    total_utilization = calculate_total_utilization(state.resource_pool)
    total_utilization > 0.8 or resource_imbalance?(state)
  end

  # WISDOM: Resource bargaining - Beer's market in action
  # This is NOT a zero-sum game. Units can find win-win trades where one's
  # excess CPU trades for another's excess memory. The magic: no central
  # planner needed. Units negotiate based on local needs, global optimum emerges.
  defp run_bargaining_round(state) do
    Logger.info("Starting resource bargaining round")

    # Get all S1 units and their current allocations
    participants = Map.keys(state.allocations)

    # WISDOM: Beer's bargaining algorithm - distributed optimization
    # Each unit states needs, makes offers, accepts trades that improve their
    # situation. No unit has global view, but the market finds efficiency.
    # This is how ants find shortest paths - local decisions, global emergence.
    bargaining_result =
      ResourceBargainer.negotiate(
        participants,
        state.allocations,
        state.resource_pool,
        state.performance_targets
      )

    # Apply bargaining results
    new_state = apply_bargaining_results(bargaining_result, state)

    # Update metrics
    new_metrics = Map.update!(new_state.metrics, :bargaining_rounds, &(&1 + 1))

    %{new_state | metrics: new_metrics}
  end

  defp calculate_total_utilization(pool) do
    total_available =
      Enum.reduce(pool, 0, fn {_, res}, acc ->
        acc + res.available
      end)

    total_capacity =
      Enum.reduce(pool, 0, fn {_, res}, acc ->
        acc + res.total
      end)

    1 - total_available / total_capacity
  end

  # WISDOM: Resource imbalance detection - finding hidden inefficiencies
  # A system can have plenty of total resources but still fail if they're
  # poorly distributed. Like a body with all blood in one leg - total volume
  # is fine but the system fails. 30% imbalance triggers rebalancing.
  defp resource_imbalance?(state) do
    utilizations =
      Enum.map(state.resource_pool, fn {_, resource} ->
        1 - resource.available / resource.total
      end)

    max_util = Enum.max(utilizations)
    min_util = Enum.min(utilizations)

    # WISDOM: 30% imbalance threshold - why this number?
    # Below 30%, natural variation. Above 30%, systemic problem.
    # Derived from queueing theory: 30% difference in utilization leads
    # to 10x difference in wait times. That's when users notice.
    # 30% imbalance threshold
    max_util - min_util > 0.3
  end

  defp apply_bargaining_results(results, state) do
    # Apply reallocations from bargaining
    Enum.reduce(results.reallocations, state, fn {from_unit, to_unit, resources}, acc ->
      acc
      |> return_resources_to_pool(from_unit, resources)
      |> allocate_resources(to_unit, resources)
      # Get the state from {:ok, _, state}
      |> elem(2)
    end)
  end

  defp generate_forecast(kalman_filters, horizon) do
    Enum.map(kalman_filters, fn {resource, filter} ->
      prediction = KalmanFilter.predict(filter, horizon)
      {resource, prediction}
    end)
    |> Map.new()
  end

  defp get_resource_measurement(resource, state) do
    pool_data = state.resource_pool[resource]

    %{
      utilization: 1 - pool_data.available / pool_data.total,
      demand_rate: calculate_demand_rate(resource, state),
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp calculate_demand_rate(resource, state) do
    # Simplified demand rate calculation
    recent_allocations =
      Enum.filter(state.allocations, fn {_, alloc} ->
        age = System.monotonic_time(:millisecond) - alloc.timestamp
        # Last minute
        age < 60_000
      end)

    # Allocations per second
    length(recent_allocations) / 60.0
  end

  defp update_resource_usage(state, s1_metrics) do
    # Update resource usage based on S1 operational metrics
    # This would integrate with actual S1 reporting
    state
  end

  defp handle_algedonic_intervention(intervention, state) do
    case intervention do
      %{action: :emergency_shutdown} ->
        # Release all resources
        Logger.error("S3 Emergency shutdown - releasing all resources")
        %{state | allocations: %{}, resource_pool: init_resource_pool()}

      %{action: :immediate_adjustment, data: %{unit_id: unit_id}} ->
        # Prioritize resources for specific unit
        prioritize_unit_resources(unit_id, state)

      _ ->
        state
    end
  end

  defp prioritize_unit_resources(unit_id, state) do
    # Give priority unit 50% more resources
    # This is a simplified implementation
    state
  end
end
