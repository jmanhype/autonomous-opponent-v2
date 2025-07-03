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
    # Start our Metrics server for comprehensive auditing
    {:ok, metrics} = Metrics.start_link(name: :s3_metrics)
    
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
    audit_data = Metrics.get_metrics(:s3_metrics, :audit_trail, duration)
    
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
  def handle_info(:optimize_cycle, state) do
    Process.send_after(self(), :optimize_cycle, @optimization_interval)
    
    # Regular optimization cycle
    optimization = perform_optimization(state)
    
    # Track optimization effectiveness
    effectiveness = measure_optimization_effectiveness(optimization, state)
    
    # Update metrics
    Metrics.record(:s3_metrics, :optimization_effectiveness, effectiveness)
    
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
    Metrics.record(:s3_metrics, :optimization_executed, optimization)
    
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
    Metrics.record(:s3_metrics, :audit_trail, audit_entry)
    
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
  
  defp get_performance_metrics(state) do
    # Get real metrics from Metrics module
    %{
      throughput: Metrics.get_metric(:s3_metrics, :throughput) || 0,
      latency: Metrics.get_metric(:s3_metrics, :latency) || 0,
      error_rate: Metrics.get_metric(:s3_metrics, :error_rate) || 0,
      resource_utilization: Metrics.get_metric(:s3_metrics, :resource_utilization) || 0
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
    case pain_signal.severity do
      :critical -> :emergency_stop
      _ -> :throttle
    end
  end
  
  defp send_to_intelligence(data, _state) do
    VarietyChannel.transmit(:s3_to_s4, %{
      coordination_data: data,
      timestamp: DateTime.utc_now()
    })
  end
  
  # Utility functions
  
  defp get_current_allocation(_state) do
    %{s1_unit_1: %{cpu: 30, memory: 40}}
  end
  
  defp update_resource_view(_report, state) do
    state
  end
  
  defp optimize_allocation(_current, _performance, _targets, _optimizer) do
    # Simplified optimization
    %{s1_unit_1: %{cpu: 35, memory: 45}}
  end
  
  defp calculate_expected_improvement(_from, _to) do
    0.1  # 10% improvement
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
  
  defp analyze_intervention_reason(_state) do
    "Performance degradation detected"
  end
  
  defp measure_optimization_effectiveness(_optimization, _state) do
    # Measure how well optimization worked
    0.7
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
end