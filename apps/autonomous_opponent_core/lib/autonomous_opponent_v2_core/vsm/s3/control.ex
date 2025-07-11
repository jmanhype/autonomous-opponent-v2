defmodule AutonomousOpponentV2Core.VSM.S3.Control do
  @moduledoc """
  System 3: Control - The executive management of the VSM.
  
  S3 manages the here-and-now, optimizing resource allocation,
  monitoring performance, and intervening when necessary.
  It uses the Metrics module for comprehensive auditing and
  decision tracking.
  
  Key responsibilities:
  - Resource optimization across S1 units
  - Performance monitoring and intervention
  - Audit trail of all decisions (using Metrics)
  - Direct control commands to S1 (closing the loop)
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Core.Metrics
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: Algedonic
  alias AutonomousOpponentV2Core.VSM.S1.Operations, as: S1
  
  defstruct [
    :metrics_server,
    :resource_optimizer,
    :intervention_engine,
    :audit_log,
    :control_state,
    :performance_targets,
    :health_metrics,
    :resource_monitors,
    :performance_history,
    :control_loops,
    :resource_pools
  ]
  
  # Control thresholds
  @intervention_threshold 0.7
  @critical_threshold 0.85
  @optimization_interval 5_000  # 5 seconds
  @resource_check_interval 1_000  # 1 second
  @history_window 300  # Keep 5 minutes of history
  
  # Resource limits
  @max_cpu_percent 80.0
  @max_memory_percent 85.0
  @max_io_rate 10_000  # KB/s
  @max_network_rate 100_000  # KB/s
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def optimize_resources do
    GenServer.call(__MODULE__, :optimize)
  end
  
  def intervene(target, action) do
    GenServer.cast(__MODULE__, {:intervene, target, action})
  end
  
  def get_control_state do
    GenServer.call(__MODULE__, :get_state)
  end
  
  def get_audit_trail(duration \\ 60_000) do
    GenServer.call(__MODULE__, {:get_audit, duration})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Use the main Metrics server for comprehensive auditing
    metrics = AutonomousOpponentV2Core.Core.Metrics
    
    # Subscribe to coordination reports via variety channel and algedonic signals
    EventBus.subscribe(:s3_control)  # Changed from :s2_coordination - now receives from variety channel
    EventBus.subscribe(:algedonic_pain)
    EventBus.subscribe(:algedonic_intervention)
    EventBus.subscribe(:s5_policy)
    EventBus.subscribe(:s1_performance)
    
    # Start monitoring cycles
    Process.send_after(self(), :optimize_cycle, @optimization_interval)
    Process.send_after(self(), :report_health, 1000)
    Process.send_after(self(), :monitor_resources, @resource_check_interval)
    
    state = %__MODULE__{
      metrics_server: metrics,
      resource_optimizer: init_optimizer(),
      intervention_engine: init_intervention_engine(),
      audit_log: [],
      control_state: %{
        mode: :normal,
        active_interventions: [],
        resource_allocation: init_resource_allocation()
      },
      performance_targets: %{
        throughput: 1000,
        latency: 100,
        error_rate: 0.01,
        resource_utilization: 0.7
      },
      health_metrics: %{
        decisions_made: 0,
        interventions: 0,
        optimization_cycles: 0,
        control_effectiveness: 1.0
      },
      resource_monitors: init_resource_monitors(),
      performance_history: :queue.new(),
      control_loops: init_control_loops(),
      resource_pools: init_resource_pools()
    }
    
    Logger.info("S3 Control online - managing the here-and-now")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:optimize, _from, state) do
    # Perform resource optimization
    optimization_result = perform_optimization(state)
    
    # Audit the optimization decision
    audit_decision(:optimization, optimization_result, state)
    
    # Execute optimization
    new_state = execute_optimization(optimization_result, state)
    
    {:reply, {:ok, optimization_result}, new_state}
  end
  
  @impl true
  def handle_call(:get_state, _from, state) do
    control_state = %{
      mode: state.control_state.mode,
      active_interventions: state.control_state.active_interventions,
      resource_allocation: get_current_allocation(state),
      performance: get_performance_metrics(state),
      health: calculate_health_score(state)
    }
    
    {:reply, control_state, state}
  end
  
  @impl true
  def handle_call({:get_audit, duration}, _from, state) do
    # Get audit trail from Metrics
    audit_data = Metrics.get_metrics(state.metrics_server, "audit_trail", duration)
    
    {:reply, audit_data, state}
  end
  
  @impl true
  def handle_cast({:intervene, target, action}, state) do
    Logger.info("S3 intervening: #{target} -> #{action}")
    
    # Record intervention decision
    intervention = %{
      target: target,
      action: action,
      timestamp: DateTime.utc_now(),
      reason: analyze_intervention_reason(state)
    }
    
    # Audit the intervention
    audit_decision(:intervention, intervention, state)
    
    # Execute intervention
    new_state = execute_intervention(intervention, state)
    
    {:noreply, new_state}
  end
  
  @impl true
  # Handle new HLC event format from EventBus
  def handle_info({:event_bus_hlc, event}, state) do
    # Extract event data and forward to existing handler
    handle_info({:event_bus, event.type, event.data}, state)
  end
  
  def handle_info({:event_bus, :algedonic_pain, pain_signal}, state) do
    # Handle algedonic pain signal - trigger immediate intervention
    Logger.warning("S3 received algedonic pain signal: #{inspect(pain_signal)}")
    
    # Determine emergency intervention
    intervention = %{
      type: :emergency_stop,
      target: pain_signal.source,
      action: :throttle,
      priority: :critical
    }
    
    # Execute intervention
    new_state = execute_intervention(intervention, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus, :s3_intervention_required, pain_signal}, state) do
    # Handle intervention request from algedonic channel
    handle_info({:event_bus, :algedonic_pain, pain_signal}, state)
  end
  
  @impl true
  def handle_info({:event, :s2_coordination, coordination_report}, state) do
    # Process S2 coordination report
    Logger.debug("S3 received coordination report")
    
    # Update resource view
    new_state = update_resource_view(coordination_report, state)
    
    # Check if intervention needed
    if needs_intervention?(coordination_report) do
      intervention = determine_intervention(coordination_report, state)
      handle_cast({:intervene, intervention.target, intervention.action}, new_state)
    else
      # Forward to S4 for learning
      send_to_intelligence(coordination_report, new_state)
      {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info({:event, :algedonic_pain, pain_signal}, state) do
    Logger.warning("S3 received pain signal: #{inspect(pain_signal)}")
    
    # Immediate intervention for pain
    intervention = %{
      target: pain_signal.source,
      action: determine_pain_response(pain_signal),
      priority: :high
    }
    
    # Bypass normal channels
    execute_emergency_intervention(intervention, state)
  end
  
  @impl true
  def handle_info({:event, :s5_policy, policy_data}, state) do
    # S5 sends policy updates - adjust our operation accordingly
    Logger.debug("S3 received policy update from S5")
    
    # Update our constraints based on policy
    new_optimizer = update_policy_constraints(state.resource_optimizer, policy_data)
    
    {:noreply, %{state | resource_optimizer: new_optimizer}}
  end

  @impl true
  def handle_info(:optimize_cycle, state) do
    Process.send_after(self(), :optimize_cycle, @optimization_interval)
    
    # Regular optimization cycle
    optimization = perform_optimization(state)
    
    # Track optimization effectiveness
    effectiveness = measure_optimization_effectiveness(optimization, state)
    
    # Update metrics
    Metrics.record(state.metrics_server, "optimization_effectiveness", effectiveness)
    
    new_state = if effectiveness > 0.5 do
      execute_optimization(optimization, state)
    else
      # Optimization not effective, try different approach
      Logger.warning("S3 optimization ineffective, changing strategy")
      adjust_optimization_strategy(state)
    end
    
    # Update health metrics
    new_health = Map.update!(new_state.health_metrics, :optimization_cycles, &(&1 + 1))
    
    {:noreply, %{new_state | health_metrics: new_health}}
  end
  
  @impl true
  def handle_info(:monitor_resources, state) do
    Process.send_after(self(), :monitor_resources, @resource_check_interval)
    
    # Get real system resources
    resources = get_system_resources()
    
    # Update resource monitors
    new_monitors = update_resource_monitors(state.resource_monitors, resources)
    
    # Check for resource violations
    violations = check_resource_violations(resources, state)
    
    # Take action on violations
    new_state = if violations != [] do
      handle_resource_violations(violations, %{state | resource_monitors: new_monitors})
    else
      %{state | resource_monitors: new_monitors}
    end
    
    # Update performance history
    perf_data = %{
      timestamp: System.monotonic_time(:millisecond),
      resources: resources,
      violations: violations
    }
    
    new_history = :queue.in(perf_data, new_state.performance_history)
    # Keep only recent history
    new_history = trim_history(new_history, @history_window)
    
    {:noreply, %{new_state | performance_history: new_history}}
  end
  
  @impl true
  def handle_info(:report_health, state) do
    Process.send_after(self(), :report_health, 1000)
    
    health = calculate_health_score(state)
    EventBus.publish(:s3_health, %{health: health})
    
    # Performance vs targets
    performance = get_real_performance_metrics(state)
    
    cond do
      health < 0.3 ->
        Algedonic.report_pain(:s3_control, :health, 1.0 - health)
        
      performance.resource_utilization > @critical_threshold ->
        Algedonic.report_pain(:s3_control, :overload, performance.resource_utilization)
        
      performance.throughput < state.performance_targets.throughput * 0.5 ->
        # Calculate pain intensity based on how bad the underperformance is
        underperformance_ratio = 1.0 - (performance.throughput / state.performance_targets.throughput)
        pain_intensity = min(0.95, 0.85 + (underperformance_ratio * 0.1))
        if pain_intensity > 0.85 do
          Algedonic.report_pain(:s3_control, :underperformance, pain_intensity)
        end
        
      health > 0.9 && meeting_all_targets?(performance, state) ->
        Algedonic.report_pleasure(:s3_control, :excellence, health)
        
      true ->
        :ok
    end
    
    # Publish VSM pattern events for HNSW streaming
    publish_pattern_events(state)
    
    {:noreply, state}
  end
  
  # Private Functions
  
  defp init_optimizer do
    %{
      algorithm: :linear_programming,
      constraints: [
        {:cpu, :max, @max_cpu_percent},
        {:memory, :max, @max_memory_percent},
        {:io, :max, @max_io_rate},
        {:network, :max, @max_network_rate}
      ],
      objective: :maximize_throughput,
      weights: %{
        cpu: 0.3,
        memory: 0.3,
        io: 0.2,
        network: 0.2
      }
    }
  end
  
  defp init_intervention_engine do
    %{
      strategies: [
        :throttle,
        :circuit_break,
        :redistribute,
        :scale_up,
        :emergency_stop
      ],
      history: [],
      active_controls: %{}
    }
  end
  
  defp init_resource_allocation do
    %{
      s1_operations: %{
        cpu_limit: 50.0,
        memory_limit: 4096,  # MB
        io_priority: :normal,
        network_bandwidth: 50_000  # KB/s
      },
      s2_coordination: %{
        cpu_limit: 20.0,
        memory_limit: 2048,
        io_priority: :high,
        network_bandwidth: 10_000
      },
      s4_intelligence: %{
        cpu_limit: 30.0,
        memory_limit: 8192,
        io_priority: :low,
        network_bandwidth: 20_000
      }
    }
  end
  
  defp init_resource_monitors do
    %{
      cpu: %{
        current: 0.0,
        average: 0.0,
        peak: 0.0,
        samples: []
      },
      memory: %{
        current: 0,
        average: 0,
        peak: 0,
        samples: []
      },
      io: %{
        read_rate: 0,
        write_rate: 0,
        queue_depth: 0,
        samples: []
      },
      network: %{
        rx_rate: 0,
        tx_rate: 0,
        connections: 0,
        samples: []
      },
      processes: %{
        count: 0,
        schedulers: 0,
        run_queue: 0
      }
    }
  end
  
  defp init_control_loops do
    %{
      cpu_governor: %{
        type: :pid,
        setpoint: 70.0,
        kp: 0.5,
        ki: 0.1,
        kd: 0.05,
        integral: 0.0,
        last_error: 0.0
      },
      memory_controller: %{
        type: :threshold,
        high_water: 80.0,
        low_water: 60.0,
        state: :normal
      },
      io_scheduler: %{
        type: :token_bucket,
        tokens: 1000,
        rate: 100,
        max_tokens: 10000
      }
    }
  end
  
  defp init_resource_pools do
    %{
      connection_pool: %{
        max_size: 100,
        current_size: 0,
        available: 100,
        waiting: []
      },
      worker_pool: %{
        max_workers: System.schedulers_online() * 2,
        active_workers: 0,
        idle_workers: System.schedulers_online(),
        job_queue: :queue.new()
      },
      memory_pool: %{
        total_allocated: 0,
        free_blocks: [],
        allocations: %{}
      }
    }
  end
  
  defp perform_optimization(state) do
    # Gather current state
    current_allocation = get_current_allocation(state)
    performance = get_real_performance_metrics(state)
    
    # Run optimization algorithm
    optimal_allocation = optimize_allocation(
      current_allocation,
      performance,
      state.performance_targets,
      state.resource_optimizer
    )
    
    %{
      type: :resource_optimization,
      from: current_allocation,
      to: optimal_allocation,
      expected_improvement: calculate_expected_improvement(current_allocation, optimal_allocation),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp execute_optimization(optimization, state) do
    # Send control commands to S1
    commands = Enum.map(optimization.to, fn {_unit, allocation} ->
      %{
        type: :allocate_resources,
        params: allocation
      }
    end)
    
    # Send through variety channel for proper VSM flow
    VarietyChannel.transmit(:s3_to_s1, %{
      commands: commands,
      optimization: true,
      timestamp: DateTime.utc_now()
    })
    
    # Also execute directly
    Enum.each(commands, &S1.execute_control_command/1)
    
    # Update control state
    new_control_state = %{state.control_state |
      resource_allocation: optimization.to
    }
    
    # Record in metrics
    Metrics.record(state.metrics_server, "optimization_executed", 1)
    
    %{state | control_state: new_control_state}
  end
  
  defp audit_decision(type, decision, state) do
    # Comprehensive audit using Metrics
    audit_entry = %{
      type: type,
      decision: decision,
      state_before: summarize_state(state),
      timestamp: DateTime.utc_now(),
      decision_maker: :s3_control
    }
    
    # Record in Metrics for analysis
    Metrics.gauge(state.metrics_server, "audit_trail", 1, %{type: Atom.to_string(type)})
    
    # Also keep local audit log
    new_audit_log = [audit_entry | state.audit_log] |> Enum.take(1000)
    
    # Send to S4 for learning
    VarietyChannel.transmit(:s3_to_s4, %{
      audit_entry: audit_entry,
      decision_context: get_decision_context(state)
    })
    
    %{state | audit_log: new_audit_log}
  end
  
  defp execute_intervention(intervention, state) do
    # Different intervention strategies
    command = case intervention.action do
      :throttle ->
        %{type: :throttle, params: %{rate: 500}}
        
      :circuit_break ->
        %{type: :circuit_break, params: %{}}
        
      :redistribute ->
        # Redistribute load
        perform_load_redistribution(state)
        %{type: :redistribute, params: %{}}
        
      :scale_up ->
        # Request more resources
        request_scale_up(state)
        %{type: :scale_up, params: %{}}
        
      :emergency_stop ->
        %{type: :emergency_stop, params: %{}}
    end
    
    # Send control command through variety channel (CLOSES THE LOOP!)
    VarietyChannel.transmit(:s3_to_s1, %{
      commands: [command],
      emergency: intervention[:priority] == :critical,
      timestamp: DateTime.utc_now()
    })
    
    # Also send directly for immediate response
    S1.execute_control_command(command)
    
    # Track intervention
    new_interventions = [intervention | state.control_state.active_interventions]
    new_control_state = %{state.control_state | active_interventions: new_interventions}
    
    # Update metrics
    new_health = Map.update!(state.health_metrics, :interventions, &(&1 + 1))
    
    %{state | 
      control_state: new_control_state,
      health_metrics: new_health
    }
  end
  
  defp execute_emergency_intervention(intervention, state) do
    Logger.error("S3 EMERGENCY INTERVENTION: #{inspect(intervention)}")
    
    command = %{
      type: :emergency_stop,
      params: %{source: intervention.target}
    }
    
    # Send through variety channel with emergency flag
    VarietyChannel.transmit(:s3_to_s1, %{
      commands: [command],
      emergency: true,
      bypass_buffers: true,
      timestamp: DateTime.utc_now()
    })
    
    # Also execute directly for immediate response
    S1.execute_control_command(command)
    
    # Update state to emergency mode
    new_control_state = %{state.control_state | mode: :emergency}
    
    # Audit emergency action
    audit_decision(:emergency_intervention, intervention, state)
    
    {:noreply, %{state | control_state: new_control_state}}
  end
  
  defp get_real_performance_metrics(state) do
    # Get real metrics from system and history
    resources = get_latest_resources(state)
    
    # Calculate actual metrics - handle both resource formats
    cpu_util = case resources.cpu do
      %{current: current} -> current / 100.0
      %{usage: usage} -> usage / 100.0
      value when is_number(value) -> value / 100.0
      _ -> 0.5  # Default to 50% if unknown
    end
    
    memory_util = case resources.memory do
      %{current: current, total: total} when total > 0 -> 
        current / total
      %{used: used} when is_number(used) ->
        used / get_total_memory()
      _ -> 
        # Fallback to direct memory check
        memory_info = :erlang.memory()
        total_mb = get_total_memory()
        if total_mb > 0, do: (memory_info[:total] / 1_048_576) / total_mb, else: 0.5
    end
    
    # Get throughput from actual system metrics
    throughput = case Metrics.get_metrics(state.metrics_server, "throughput", 60_000) do
      data when is_list(data) and length(data) > 0 ->
        Enum.sum(data) / length(data)
      _ ->
        0
    end
    
    # Get latency from actual measurements
    latency = case Metrics.get_metrics(state.metrics_server, "latency", 60_000) do
      data when is_list(data) and length(data) > 0 ->
        Enum.sum(data) / length(data)
      _ ->
        0
    end
    
    # Get error rate from actual errors
    error_rate = case Metrics.get_metrics(state.metrics_server, "errors", 60_000) do
      errors when is_list(errors) ->
        total_requests = throughput * 60  # requests in last minute
        if total_requests > 0, do: length(errors) / total_requests, else: 0.0
      _ ->
        0.0
    end
    
    %{
      throughput: throughput,
      latency: latency,
      error_rate: error_rate,
      resource_utilization: (cpu_util * 0.4 + memory_util * 0.6)
    }
  end
  
  defp get_performance_metrics(state) do
    # Deprecated - use get_real_performance_metrics
    get_real_performance_metrics(state)
  end
  
  defp calculate_health_score(state) do
    metrics = state.health_metrics
    
    # Base health on control effectiveness
    base_health = metrics.control_effectiveness
    
    # Penalty for too many interventions
    intervention_penalty = min(0.5, metrics.interventions * 0.01)
    
    max(0.0, base_health - intervention_penalty)
  end
  
  defp needs_intervention?(coordination_report) do
    coordination_report.intervention_recommended ||
    coordination_report.resource_pressure > @intervention_threshold
  end
  
  defp determine_intervention(report, _state) do
    # Logic to determine appropriate intervention
    %{
      target: :s1_operations,
      action: if(report.resource_pressure > @critical_threshold, 
        do: :throttle,
        else: :redistribute
      )
    }
  end
  
  defp determine_pain_response(pain_signal) do
    case pain_signal.intensity do
      intensity when intensity >= 0.9 -> :emergency_stop
      intensity when intensity >= 0.7 -> :throttle
      _ -> :monitor
    end
  end
  
  defp send_to_intelligence(data, _state) do
    VarietyChannel.transmit(:s3_to_s4, %{
      coordination_data: data,
      timestamp: DateTime.utc_now()
    })
  end
  
  # Utility functions
  
  defp get_current_allocation(state) do
    # Get current resource allocation from control state
    case state.control_state.resource_allocation do
      allocation when map_size(allocation) > 0 ->
        allocation
      _ ->
        # Return default allocation if empty
        init_resource_allocation()
    end
  end
  
  defp update_resource_view(report, state) do
    # Update our view of resource allocation based on S2 report
    if Map.has_key?(report, :resource_pressure) do
      # Adjust targets based on pressure
      new_targets = if report.resource_pressure > 0.8 do
        %{state.performance_targets | 
          throughput: state.performance_targets.throughput * 0.9,
          resource_utilization: 0.85
        }
      else
        state.performance_targets
      end
      
      %{state | performance_targets: new_targets}
    else
      state
    end
  end
  
  defp optimize_allocation(current, performance, targets, optimizer) do
    # Optimize resource allocation based on real performance and targets
    case optimizer.algorithm do
      :linear_programming ->
        # Linear optimization with constraints
        optimize_with_linear_programming(current, performance, targets, optimizer)
        
      :genetic_algorithm ->
        # Genetic algorithm optimization
        optimize_with_genetic_algorithm(current, performance, targets, optimizer)
        
      _ ->
        current
    end
  end
  
  defp optimize_with_linear_programming(current, performance, targets, optimizer) do
    # Calculate resource pressure for each metric
    cpu_pressure = performance.resource_utilization
    _latency_pressure = performance.latency / targets.latency
    throughput_deficit = targets.throughput / max(1, performance.throughput)
    
    # Apply weighted optimization
    current
    |> Enum.map(fn {unit, resources} ->
      # Calculate adjustment factors based on constraints
      cpu_factor = calculate_adjustment_factor(
        resources.cpu_limit,
        cpu_pressure,
        optimizer.constraints,
        :cpu
      )
      
      memory_factor = calculate_adjustment_factor(
        resources.memory_limit,
        cpu_pressure,
        optimizer.constraints,
        :memory
      )
      
      # Apply multi-objective optimization
      new_cpu = adjust_resource(
        resources.cpu_limit,
        cpu_factor,
        throughput_deficit,
        optimizer.weights.cpu
      )
      
      new_memory = adjust_resource(
        resources.memory_limit,
        memory_factor,
        throughput_deficit,
        optimizer.weights.memory
      )
      
      new_resources = %{resources |
        cpu_limit: new_cpu,
        memory_limit: new_memory
      }
      
      {unit, new_resources}
    end)
    |> Map.new()
  end
  
  defp optimize_with_genetic_algorithm(current, performance, targets, optimizer) do
    # Generate population of solutions
    population = generate_population(current, 10)
    
    # Evaluate fitness of each solution
    evaluated = Enum.map(population, fn solution ->
      fitness = evaluate_fitness(solution, performance, targets, optimizer)
      {solution, fitness}
    end)
    
    # Select best solution
    {best_solution, _} = Enum.max_by(evaluated, fn {_, fitness} -> fitness end)
    
    best_solution
  end
  
  defp calculate_adjustment_factor(current_value, pressure, constraints, resource_type) do
    # Find constraint for this resource type
    constraint = Enum.find(constraints, fn
      {^resource_type, :max, _} -> true
      _ -> false
    end)
    
    case constraint do
      {_, :max, max_value} ->
        # Calculate how much room we have to grow
        headroom = (max_value - current_value) / max_value
        
        if pressure > 0.8 do
          # High pressure - scale down
          0.9 - (pressure - 0.8) * 0.5
        else
          # Low pressure - scale up if we have headroom
          1.0 + (headroom * 0.1)
        end
        
      _ ->
        # No constraint - use simple adjustment
        if pressure > 0.7, do: 0.95, else: 1.05
    end
  end
  
  defp adjust_resource(current, factor, throughput_deficit, weight) do
    # Multi-objective adjustment
    base_adjustment = current * factor
    
    # Add throughput-based adjustment
    throughput_adjustment = if throughput_deficit > 1.2 do
      current * 0.1 * weight  # Boost resources if throughput is low
    else
      0
    end
    
    new_value = base_adjustment + throughput_adjustment
    
    # Ensure bounds
    max(10, min(100, round(new_value)))
  end
  
  defp generate_population(base_allocation, size) do
    # Generate variations of the base allocation
    Enum.map(1..size, fn _ ->
      base_allocation
      |> Enum.map(fn {unit, resources} ->
        # Apply small random variations
        variation = 1.0 + (:rand.uniform() * 0.2 - 0.1)
        
        new_resources = %{resources |
          cpu_limit: max(10, min(100, round(resources.cpu_limit * variation))),
          memory_limit: max(512, min(16384, round(resources.memory_limit * variation)))
        }
        
        {unit, new_resources}
      end)
      |> Map.new()
    end)
  end
  
  defp evaluate_fitness(solution, performance, targets, optimizer) do
    # Calculate fitness score based on multiple objectives
    total_cpu = solution
    |> Map.values()
    |> Enum.map(& &1.cpu_limit)
    |> Enum.sum()
    
    total_memory = solution
    |> Map.values()
    |> Enum.map(& &1.memory_limit)
    |> Enum.sum()
    
    # Fitness components
    efficiency_score = 100.0 / (total_cpu + total_memory / 100)
    
    performance_score = calculate_performance_score(performance, targets)
    
    constraint_penalty = calculate_constraint_penalty(solution, optimizer.constraints)
    
    # Combined fitness
    efficiency_score * 0.3 + performance_score * 0.6 - constraint_penalty * 0.1
  end
  
  defp calculate_performance_score(performance, targets) do
    throughput_score = min(1.0, performance.throughput / targets.throughput)
    latency_score = min(1.0, targets.latency / max(1, performance.latency))
    error_score = 1.0 - min(1.0, performance.error_rate / targets.error_rate)
    
    (throughput_score + latency_score + error_score) / 3.0
  end
  
  defp calculate_constraint_penalty(solution, constraints) do
    # Calculate penalty for violating constraints
    Enum.reduce(solution, 0.0, fn {_, resources}, penalty ->
      Enum.reduce(constraints, penalty, fn constraint, acc ->
        case constraint do
          {:cpu, :max, max_cpu} ->
            if resources.cpu_limit > max_cpu do
              acc + (resources.cpu_limit - max_cpu)
            else
              acc
            end
            
          {:memory, :max, max_memory} ->
            if resources.memory_limit > max_memory * 1024 do  # Convert to MB
              acc + (resources.memory_limit - max_memory * 1024) / 1024
            else
              acc
            end
            
          _ ->
            acc
        end
      end)
    end)
  end
  
  defp calculate_expected_improvement(from, to) do
    # Calculate expected improvement from optimization
    from_score = calculate_allocation_score(from)
    to_score = calculate_allocation_score(to)
    
    if from_score > 0 do
      (to_score - from_score) / from_score
    else
      0.0
    end
  end
  
  defp calculate_allocation_score(allocation) do
    # Calculate a score for resource allocation efficiency
    allocation
    |> Map.values()
    |> Enum.reduce(0, fn resources, acc ->
      # Score based on resource efficiency
      cpu_score = if Map.has_key?(resources, :cpu_limit) do
        100.0 / max(1, resources.cpu_limit)  # Lower is better
      else
        0
      end
      
      memory_score = if Map.has_key?(resources, :memory_limit) do
        8192.0 / max(1, resources.memory_limit)  # Lower is better
      else
        0
      end
      
      acc + cpu_score + memory_score
    end)
  end
  
  defp summarize_state(state) do
    %{
      mode: state.control_state.mode,
      interventions: length(state.control_state.active_interventions)
    }
  end
  
  defp get_decision_context(state) do
    %{
      performance: get_performance_metrics(state),
      health: calculate_health_score(state)
    }
  end
  
  defp analyze_intervention_reason(state) do
    # Analyze why intervention is needed
    performance = get_performance_metrics(state)
    targets = state.performance_targets
    
    cond do
      performance.throughput < targets.throughput * 0.5 ->
        "Severe throughput degradation"
        
      performance.error_rate > targets.error_rate * 2 ->
        "Error rate exceeding acceptable limits"
        
      performance.latency > targets.latency * 1.5 ->
        "Latency exceeding targets"
        
      performance.resource_utilization > 0.9 ->
        "Resource exhaustion imminent"
        
      true ->
        "Performance degradation detected"
    end
  end
  
  defp measure_optimization_effectiveness(optimization, state) do
    # Measure how well optimization worked
    # Compare expected vs actual improvement
    expected = optimization.expected_improvement
    
    # Get current performance (simplified - would track actual changes)
    current_performance = get_performance_metrics(state)
    
    # Effectiveness based on meeting targets
    effectiveness = cond do
      current_performance.throughput >= state.performance_targets.throughput -> 1.0
      current_performance.error_rate <= state.performance_targets.error_rate -> 0.8
      current_performance.resource_utilization <= state.performance_targets.resource_utilization -> 0.7
      true -> 0.5
    end
    
    # Adjust for expectation vs reality
    if expected > 0 do
      effectiveness * 0.8 + 0.2  # Some credit for trying
    else
      effectiveness
    end
  end
  
  defp adjust_optimization_strategy(state) do
    # Change optimization approach
    new_optimizer = %{state.resource_optimizer | 
      algorithm: :genetic_algorithm
    }
    
    %{state | resource_optimizer: new_optimizer}
  end
  
  defp meeting_all_targets?(performance, state) do
    targets = state.performance_targets
    
    performance.throughput >= targets.throughput &&
    performance.latency <= targets.latency &&
    performance.error_rate <= targets.error_rate
  end
  
  # Note: perform_load_redistribution and request_scale_up are defined later with full implementations
  
  defp update_policy_constraints(optimizer, policy_data) do
    # Extract policy constraints and update optimizer
    constraints = if Map.has_key?(policy_data, :constraints) do
      policy_data.constraints
    else
      []
    end
    
    %{optimizer | constraints: constraints}
  end
  
  # Real resource monitoring functions
  
  defp get_system_resources do
    # Get real system resource usage
    memory_info = :erlang.memory()
    
    %{
      cpu: get_cpu_usage(),
      memory: %{
        current: memory_info[:total] / 1_048_576,  # Convert to MB
        total: get_total_memory(),
        processes: memory_info[:processes] / 1_048_576,
        ets: memory_info[:ets] / 1_048_576,
        binary: memory_info[:binary] / 1_048_576
      },
      io: get_io_stats(),
      network: get_network_stats(),
      processes: %{
        count: :erlang.system_info(:process_count),
        schedulers: :erlang.system_info(:schedulers_online),
        run_queue: :erlang.statistics(:run_queue),
        reductions: :erlang.element(1, :erlang.statistics(:reductions))
      }
    }
  end
  
  defp get_cpu_usage do
    # Get scheduler utilization as proxy for CPU usage
    case :scheduler.utilization(1) do
      {:ok, utils} ->
        # Average utilization across all schedulers
        total_util = Enum.reduce(utils, 0.0, fn {_, util, _}, acc -> acc + util end)
        avg_util = total_util / length(utils)
        %{
          current: avg_util * 100,
          per_scheduler: Enum.map(utils, fn {id, util, _} -> {id, util * 100} end)
        }
      _ ->
        # Fallback to scheduler wall time
        wall_time = :erlang.statistics(:scheduler_wall_time)
        if wall_time != :undefined do
          calculate_cpu_from_wall_time(wall_time)
        else
          %{current: 0.0, per_scheduler: []}
        end
    end
  end
  
  defp calculate_cpu_from_wall_time(wall_time) do
    # Calculate CPU usage from scheduler wall time
    total_active = Enum.reduce(wall_time, 0, fn {_, active, _}, acc -> acc + active end)
    total_time = Enum.reduce(wall_time, 0, fn {_, _, total}, acc -> acc + total end)
    
    if total_time > 0 do
      %{
        current: (total_active / total_time) * 100,
        per_scheduler: Enum.map(wall_time, fn {id, active, total} ->
          {id, if(total > 0, do: (active / total) * 100, else: 0.0)}
        end)
      }
    else
      %{current: 0.0, per_scheduler: []}
    end
  end
  
  defp get_total_memory do
    # Get total system memory
    case :os.type() do
      {:unix, :darwin} ->
        # macOS
        case System.cmd("sysctl", ["-n", "hw.memsize"]) do
          {output, 0} -> (String.trim(output) |> String.to_integer()) / 1_048_576
          _ -> 8192  # Default 8GB
        end
      {:unix, _} ->
        # Linux
        case File.read("/proc/meminfo") do
          {:ok, content} ->
            case Regex.run(~r/MemTotal:\s+(\d+)/, content) do
              [_, kb] -> String.to_integer(kb) / 1024
              _ -> 8192
            end
          _ -> 8192
        end
      _ ->
        8192  # Default for other systems
    end
  end
  
  defp get_io_stats do
    # Get I/O statistics with error handling
    try do
      {{input, output}, _} = :erlang.statistics(:io)
      
      # Ensure we have numbers
      safe_input = if is_number(input), do: input, else: 0
      safe_output = if is_number(output), do: output, else: 0
      
      %{
        read_rate: safe_input / 1024,  # KB/s approximation
        write_rate: safe_output / 1024,
        queue_depth: 0  # Would need OS-specific implementation
      }
    rescue
      _ ->
        %{
          read_rate: 0.0,
          write_rate: 0.0,
          queue_depth: 0
        }
    end
  end
  
  defp get_network_stats do
    # Get network statistics (simplified)
    # In real implementation, would interface with system network stats
    %{
      rx_rate: 0,
      tx_rate: 0,
      connections: length(:erlang.ports())
    }
  end
  
  defp update_resource_monitors(monitors, resources) do
    # Update each monitor with new sample
    %{monitors |
      cpu: update_monitor(monitors.cpu, resources.cpu.current),
      memory: update_monitor(monitors.memory, resources.memory.current),
      io: Map.merge(monitors.io, resources.io),
      network: Map.merge(monitors.network, resources.network),
      processes: resources.processes
    }
  end
  
  defp update_monitor(monitor, value) do
    # Add new sample and update statistics
    samples = [value | monitor.samples] |> Enum.take(60)  # Keep 1 minute of samples
    
    %{monitor |
      current: value,
      average: Enum.sum(samples) / length(samples),
      peak: Enum.max([monitor.peak, value]),
      samples: samples
    }
  end
  
  defp check_resource_violations(resources, _state) do
    violations = []
    
    # Check CPU
    violations = if resources.cpu.current > @max_cpu_percent do
      [{:cpu, :exceeded, resources.cpu.current} | violations]
    else
      violations
    end
    
    # Check memory
    memory_percent = (resources.memory.current / resources.memory.total) * 100
    violations = if memory_percent > @max_memory_percent do
      [{:memory, :exceeded, memory_percent} | violations]
    else
      violations
    end
    
    # Check I/O rates
    violations = if resources.io.read_rate + resources.io.write_rate > @max_io_rate do
      [{:io, :exceeded, resources.io.read_rate + resources.io.write_rate} | violations]
    else
      violations
    end
    
    violations
  end
  
  defp handle_resource_violations(violations, state) do
    # Take action based on violations
    Enum.reduce(violations, state, fn violation, acc_state ->
      case violation do
        {:cpu, :exceeded, value} ->
          Logger.warning("CPU usage exceeded: #{value}%")
          # Throttle CPU-intensive operations
          execute_cpu_throttling(acc_state, value)
          
        {:memory, :exceeded, value} ->
          Logger.warning("Memory usage exceeded: #{value}%")
          # Trigger memory pressure response
          execute_memory_management(acc_state, value)
          
        {:io, :exceeded, value} ->
          Logger.warning("I/O rate exceeded: #{value} KB/s")
          # Apply I/O throttling
          execute_io_throttling(acc_state, value)
          
        _ ->
          acc_state
      end
    end)
  end
  
  defp execute_cpu_throttling(state, cpu_usage) do
    # Apply PID control to CPU usage
    controller = state.control_loops.cpu_governor
    
    # Calculate PID control signal
    error = cpu_usage - controller.setpoint
    integral = controller.integral + error
    derivative = error - controller.last_error
    
    control_signal = controller.kp * error + controller.ki * integral + controller.kd * derivative
    
    # Apply control action
    if control_signal > 10 do
      # Significant overshoot - throttle aggressively
      S1.execute_control_command(%{
        type: :cpu_throttle,
        params: %{reduction: min(50, control_signal)}
      })
    end
    
    # Update controller state
    new_controller = %{controller |
      integral: integral,
      last_error: error
    }
    
    put_in(state.control_loops.cpu_governor, new_controller)
  end
  
  defp execute_memory_management(state, memory_percent) do
    controller = state.control_loops.memory_controller
    
    new_state = case controller.state do
      :normal when memory_percent > controller.high_water ->
        # Transition to pressure mode
        Logger.warning("Memory pressure detected - entering conservation mode")
        S1.execute_control_command(%{
          type: :memory_pressure,
          params: %{mode: :high, limit: memory_percent}
        })
        put_in(state.control_loops.memory_controller.state, :pressure)
        
      :pressure when memory_percent < controller.low_water ->
        # Return to normal
        Logger.info("Memory pressure relieved - returning to normal mode")
        S1.execute_control_command(%{
          type: :memory_pressure,
          params: %{mode: :normal}
        })
        put_in(state.control_loops.memory_controller.state, :normal)
        
      _ ->
        state
    end
    
    new_state
  end
  
  defp execute_io_throttling(state, io_rate) do
    scheduler = state.control_loops.io_scheduler
    
    # Token bucket algorithm for I/O throttling
    tokens_needed = io_rate / 100  # Simplified calculation
    
    if scheduler.tokens >= tokens_needed do
      # Allow I/O
      new_scheduler = %{scheduler | tokens: scheduler.tokens - tokens_needed}
      put_in(state.control_loops.io_scheduler, new_scheduler)
    else
      # Throttle I/O
      S1.execute_control_command(%{
        type: :io_throttle,
        params: %{rate: scheduler.rate}
      })
      state
    end
  end
  
  defp get_latest_resources(state) do
    # Get the most recent resource snapshot
    case state.resource_monitors do
      nil -> get_system_resources()
      monitors -> %{
        cpu: monitors.cpu,
        memory: monitors.memory,
        io: monitors.io,
        network: monitors.network,
        processes: monitors.processes
      }
    end
  end
  
  defp trim_history(queue, max_age_seconds) do
    # Remove old entries from history
    now = System.monotonic_time(:millisecond)
    cutoff = now - (max_age_seconds * 1000)
    
    :queue.filter(fn entry ->
      entry.timestamp > cutoff
    end, queue)
  end
  
  defp perform_load_redistribution(state) do
    Logger.info("S3 redistributing load across S1 units")
    
    # Get current resource usage per unit
    allocation = state.control_state.resource_allocation
    
    # Calculate optimal distribution based on current load
    total_cpu = Enum.reduce(allocation, 0, fn {_, res}, acc -> acc + res.cpu_limit end)
    unit_count = map_size(allocation)
    fair_share = total_cpu / unit_count
    
    # Redistribute evenly with some headroom
    new_allocation = allocation
    |> Enum.map(fn {unit, resources} ->
      {unit, %{resources | cpu_limit: fair_share * 0.9}}
    end)
    |> Map.new()
    
    # Apply new allocation
    Enum.each(new_allocation, fn {unit, resources} ->
      S1.execute_control_command(%{
        type: :reallocate,
        params: %{unit: unit, resources: resources}
      })
    end)
    
    put_in(state.control_state.resource_allocation, new_allocation)
  end
  
  defp request_scale_up(state) do
    Logger.info("S3 requesting scale up from S5")
    
    # Calculate resource needs
    current_usage = get_latest_resources(state)
    
    scale_request = %{
      type: :scale_request,
      direction: :up,
      reason: :resource_pressure,
      current: %{
        cpu: current_usage.cpu.current,
        memory: current_usage.memory.current
      },
      requested: %{
        cpu: @max_cpu_percent * 1.5,
        memory: current_usage.memory.total * 1.5
      }
    }
    
    EventBus.publish(:s5_policy, scale_request)
    state
  end

  # VSM Pattern Publishing - Complete VSM Integration
  defp publish_pattern_events(state) do
    # Publish S3-specific control patterns for VSM integration
    try do
      # Create S3 control pattern from current state
      pattern_data = %{
        subsystem: "S3",
        type: "control_pattern",
        timestamp: DateTime.utc_now(),
        metrics: %{
          health_score: calculate_health_score(state),
          resource_utilization: get_resource_utilization(state),
          performance_score: calculate_performance_score(state),
          intervention_count: Map.get(state.intervention_engine, :total_interventions, length(Map.get(state.intervention_engine, :history, []))),
          decision_count: :queue.len(state.audit_log)
        },
        control_data: %{
          active_interventions: map_size(Map.get(state.intervention_engine, :active_interventions, %{})),
          resource_optimization_active: Map.get(state.resource_optimizer, :enabled, false),
          performance_targets: state.performance_targets,
          current_allocation: summarize_resource_allocation(state),
          control_commands_sent: Map.get(state.intervention_engine, :commands_sent, 0)
        },
        resource_status: %{
          cpu: get_cpu_status(state),
          memory: get_memory_status(state),
          io: get_io_status(state),
          network: get_network_status(state)
        }
      }

      # Publish to S3-specific pattern channel
      EventBus.publish(:vsm_s3_patterns, pattern_data)
      
      # Also publish to general VSM pattern flow
      EventBus.publish(:vsm_pattern_flow, pattern_data)
      
      # Publish resource optimization patterns
      optimization_pattern = %{
        subsystem: "S3",
        type: "resource_optimization_pattern",
        timestamp: DateTime.utc_now(),
        optimization_active: state.resource_optimizer.enabled,
        efficiency_score: calculate_optimization_efficiency(state),
        resource_pressure: calculate_resource_pressure(state),
        optimization_decisions: get_recent_optimization_decisions(state),
        target_achievement: measure_target_achievement(state)
      }
      
      EventBus.publish(:vsm_s3_patterns, optimization_pattern)
      EventBus.publish(:vsm_pattern_flow, optimization_pattern)
      
    catch
      :exit, {:noproc, _} ->
        # EventBus not available, skip publishing
        :ok
      error ->
        Logger.warning("S3: Failed to publish pattern events: #{inspect(error)}")
    end
  end
  
  defp summarize_resource_allocation(state) do
    allocation = state.control_state.resource_allocation
    %{
      total_units: map_size(allocation),
      avg_cpu_limit: avg_cpu_allocation(allocation),
      memory_distribution: memory_distribution(allocation)
    }
  end
  
  defp avg_cpu_allocation(allocation) do
    if map_size(allocation) > 0 do
      total = Enum.reduce(allocation, 0, fn {_, res}, acc -> acc + res.cpu_limit end)
      total / map_size(allocation)
    else
      0.0
    end
  end
  
  defp memory_distribution(allocation) do
    allocation
    |> Enum.map(fn {_, res} -> res.memory_limit end)
    |> Enum.frequencies()
  end
  
  defp get_cpu_status(state) do
    current = get_latest_resources(state)
    %{
      current: current.cpu.current,
      limit: @max_cpu_percent,
      utilization: current.cpu.current / @max_cpu_percent
    }
  end
  
  defp get_memory_status(state) do
    current = get_latest_resources(state)
    %{
      current: current.memory.current,
      total: current.memory.total,
      utilization: current.memory.current / current.memory.total
    }
  end
  
  defp get_io_status(state) do
    current = get_latest_resources(state)
    %{
      current: current.io.current,
      limit: @max_io_rate,
      utilization: current.io.current / @max_io_rate
    }
  end
  
  defp get_network_status(state) do
    current = get_latest_resources(state)
    %{
      current: current.network.current,
      limit: @max_network_rate,
      utilization: current.network.current / @max_network_rate
    }
  end
  
  defp calculate_optimization_efficiency(state) do
    performance = get_real_performance_metrics(state)
    targets = state.performance_targets
    
    efficiency_scores = [
      performance.throughput / targets.throughput,
      performance.latency / targets.latency,
      (1.0 - performance.resource_utilization)  # Lower utilization = more efficient
    ]
    
    Enum.sum(efficiency_scores) / length(efficiency_scores)
  end
  
  defp calculate_resource_pressure(state) do
    current = get_latest_resources(state)
    
    pressures = [
      current.cpu.current / @max_cpu_percent,
      current.memory.current / current.memory.total,
      current.io.current / @max_io_rate,
      current.network.current / @max_network_rate
    ]
    
    Enum.max(pressures)
  end
  
  defp get_recent_optimization_decisions(state) do
    # Get recent decisions from audit log
    now = System.monotonic_time(:millisecond)
    recent_cutoff = now - 60_000  # Last minute
    
    audit_entries = :queue.to_list(state.audit_log)
    
    audit_entries
    |> Enum.filter(fn entry -> entry.timestamp > recent_cutoff end)
    |> Enum.filter(fn entry -> entry.action_type == :optimize_resources end)
    |> length()
  end
  
  defp measure_target_achievement(state) do
    performance = get_real_performance_metrics(state)
    targets = state.performance_targets
    
    %{
      throughput_achievement: performance.throughput / targets.throughput,
      latency_achievement: targets.latency / performance.latency,  # Inverted - lower is better
      resource_efficiency: 1.0 - performance.resource_utilization,
      overall_score: calculate_performance_score(state)
    }
  end

  defp calculate_performance_score(state) do
    # Calculate overall performance score based on health metrics
    health = state.health_metrics
    
    # Weighted performance calculation
    efficiency_score = Map.get(health, :resource_efficiency, 0.5) * 0.3
    throughput_score = min(Map.get(health, :throughput, 0) / 1000.0, 1.0) * 0.3  # Normalize to max 1000/sec
    intervention_penalty = min(Map.get(health, :intervention_count, health.interventions) / 100.0, 0.2) * 0.2  # Penalty for too many interventions
    uptime_score = Map.get(health, :uptime_percentage, 1.0) * 0.2
    
    max(0.0, efficiency_score + throughput_score - intervention_penalty + uptime_score)
  end

  defp get_resource_utilization(state) do
    # Get current resource utilization across all monitored resources
    monitors = state.resource_monitors
    
    %{
      cpu: get_monitor_utilization(monitors.cpu),
      memory: get_monitor_utilization(monitors.memory),
      io: get_monitor_utilization(monitors.io),
      network: get_monitor_utilization(monitors.network),
      overall: calculate_overall_utilization(monitors)
    }
  end

  defp get_monitor_utilization(monitor) do
    case monitor do
      %{current: current, limit: limit} when limit > 0 ->
        current / limit
      _ ->
        0.0
    end
  end

  defp calculate_overall_utilization(monitors) do
    utilizations = [
      get_monitor_utilization(monitors.cpu),
      get_monitor_utilization(monitors.memory), 
      get_monitor_utilization(monitors.io),
      get_monitor_utilization(monitors.network)
    ]
    
    Enum.sum(utilizations) / length(utilizations)
  end
end