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
    :health_metrics
  ]
  
  # Control thresholds
  @intervention_threshold 0.7
  @critical_threshold 0.85
  @optimization_interval 5_000  # 5 seconds
  
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
    
    # Subscribe to coordination reports and algedonic signals
    EventBus.subscribe(:s2_coordination)
    EventBus.subscribe(:algedonic_pain)
    EventBus.subscribe(:algedonic_intervention)
    EventBus.subscribe(:s5_policy)
    
    # Start optimization cycle
    Process.send_after(self(), :optimize_cycle, @optimization_interval)
    Process.send_after(self(), :report_health, 1000)
    
    state = %__MODULE__{
      metrics_server: metrics,
      resource_optimizer: init_optimizer(),
      intervention_engine: init_intervention_engine(),
      audit_log: [],
      control_state: %{
        mode: :normal,
        active_interventions: [],
        resource_allocation: %{}
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
      }
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
    audit_data = Metrics.get_metrics(Metrics, :audit_trail, duration)
    
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
    Metrics.record(Metrics, :optimization_effectiveness, effectiveness)
    
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
  def handle_info(:report_health, state) do
    Process.send_after(self(), :report_health, 1000)
    
    health = calculate_health_score(state)
    EventBus.publish(:s3_health, %{health: health})
    
    # Performance vs targets
    performance = get_performance_metrics(state)
    
    cond do
      health < 0.3 ->
        Algedonic.report_pain(:s3_control, :health, 1.0 - health)
        
      performance.resource_utilization > @critical_threshold ->
        Algedonic.report_pain(:s3_control, :overload, performance.resource_utilization)
        
      performance.throughput < state.performance_targets.throughput * 0.5 ->
        Algedonic.report_pain(:s3_control, :underperformance, 0.8)
        
      health > 0.9 && meeting_all_targets?(performance, state) ->
        Algedonic.report_pleasure(:s3_control, :excellence, health)
        
      true ->
        :ok
    end
    
    {:noreply, state}
  end
  
  # Private Functions
  
  defp init_optimizer do
    %{
      algorithm: :linear_programming,
      constraints: [],
      objective: :maximize_throughput
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
      history: []
    }
  end
  
  defp perform_optimization(state) do
    # Gather current state
    current_allocation = get_current_allocation(state)
    performance = get_performance_metrics(state)
    
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
    Enum.each(optimization.to, fn {unit, allocation} ->
      command = %{
        type: :allocate_resources,
        params: allocation
      }
      
      S1.execute_control_command(command)
    end)
    
    # Update control state
    new_control_state = %{state.control_state |
      resource_allocation: optimization.to
    }
    
    # Record in metrics
    Metrics.record(Metrics, :optimization_executed, optimization)
    
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
    Metrics.record(Metrics, :audit_trail, audit_entry)
    
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
    case intervention.action do
      :throttle ->
        S1.execute_control_command(%{type: :throttle, params: %{rate: 500}})
        
      :circuit_break ->
        S1.execute_control_command(%{type: :circuit_break, params: %{}})
        
      :redistribute ->
        # Redistribute load
        perform_load_redistribution(state)
        
      :scale_up ->
        # Request more resources
        request_scale_up(state)
        
      :emergency_stop ->
        S1.execute_control_command(%{type: :emergency_stop, params: %{}})
    end
    
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
    
    # Immediate command to S1 - bypass normal flow
    S1.execute_control_command(%{
      type: :emergency_stop,
      params: %{source: intervention.target}
    })
    
    # Update state to emergency mode
    new_control_state = %{state.control_state | mode: :emergency}
    
    # Audit emergency action
    audit_decision(:emergency_intervention, intervention, state)
    
    {:noreply, %{state | control_state: new_control_state}}
  end
  
  defp get_performance_metrics(_state) do
    # Get real metrics from Metrics module
    # For now, return simulated metrics
    %{
      throughput: (:rand.uniform() * 500 + 500),  # 500-1000
      latency: (:rand.uniform() * 50 + 50),        # 50-100ms
      error_rate: (:rand.uniform() * 0.02),        # 0-2%
      resource_utilization: (:rand.uniform() * 0.4 + 0.4)  # 40-80%
    }
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
    state.control_state.resource_allocation
    |> Map.put_new(:s1_unit_1, %{cpu: 30, memory: 40})  # Default if empty
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
    # Optimize resource allocation based on performance and targets
    case optimizer.algorithm do
      :linear_programming ->
        # Simple linear optimization - adjust based on utilization
        current
        |> Enum.map(fn {unit, resources} ->
          utilization = performance.resource_utilization
          
          new_resources = if utilization > targets.resource_utilization do
            # Scale down
            %{
              cpu: round(resources.cpu * 0.9),
              memory: round(resources.memory * 0.9)
            }
          else
            # Scale up if under target
            %{
              cpu: min(100, round(resources.cpu * 1.1)),
              memory: min(100, round(resources.memory * 1.1))
            }
          end
          
          {unit, new_resources}
        end)
        |> Map.new()
        
      :genetic_algorithm ->
        # More sophisticated optimization (simplified)
        current
        |> Enum.map(fn {unit, resources} ->
          # Random mutation for genetic algorithm
          mutation = :rand.uniform() * 0.2 - 0.1  # -10% to +10%
          
          {unit, %{
            cpu: max(10, min(100, round(resources.cpu * (1 + mutation)))),
            memory: max(10, min(100, round(resources.memory * (1 + mutation))))
          }}
        end)
        |> Map.new()
        
      _ ->
        current
    end
  end
  
  defp calculate_expected_improvement(from, to) do
    # Calculate expected improvement from optimization
    from_total = from |> Map.values() |> Enum.flat_map(&Map.values/1) |> Enum.sum()
    to_total = to |> Map.values() |> Enum.flat_map(&Map.values/1) |> Enum.sum()
    
    if from_total > 0 do
      (to_total - from_total) / from_total
    else
      0.0
    end
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
  
  defp perform_load_redistribution(_state) do
    Logger.info("S3 redistributing load across S1 units")
  end
  
  defp request_scale_up(_state) do
    Logger.info("S3 requesting scale up from S5")
    EventBus.publish(:s5_policy, {:scale_request, :up})
  end
  
  defp update_policy_constraints(optimizer, policy_data) do
    # Extract policy constraints and update optimizer
    constraints = if Map.has_key?(policy_data, :constraints) do
      policy_data.constraints
    else
      []
    end
    
    %{optimizer | constraints: constraints}
  end
end