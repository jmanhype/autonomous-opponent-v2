defmodule AutonomousOpponent.VSM.S3.AuditSubsystem do
  @moduledoc """
  S3* Audit Subsystem - Sporadic intervention mechanism for S3 Control.
  
  Following Beer's VSM model, S3* provides sporadic audit and intervention
  capabilities, monitoring S3's performance and intervening when necessary.
  This implements the "management by exception" principle.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponent.EventBus
  
  @audit_interval 30_000  # 30 seconds between audits
  @intervention_threshold %{
    allocation_efficiency: 0.7,    # Below 70% triggers intervention
    response_time_violation: 1.5,  # 50% over target
    stability_index: 0.8,          # Below 80% stability
    bargaining_deadlock: 5         # 5 failed rounds
  }
  
  defstruct [
    :parent_s3,
    :audit_history,
    :intervention_count,
    :last_audit,
    :monitoring_state,
    :intervention_rules
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def intervene(server \\ __MODULE__, intervention_type, params) do
    GenServer.call(server, {:intervene, intervention_type, params})
  end
  
  def request_audit(server \\ __MODULE__, audit_type \\ :full) do
    GenServer.call(server, {:request_audit, audit_type})
  end
  
  def get_audit_report(server \\ __MODULE__) do
    GenServer.call(server, :get_audit_report)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    parent_s3 = opts[:parent] || Process.whereis(AutonomousOpponent.VSM.S3.Control)
    
    state = %__MODULE__{
      parent_s3: parent_s3,
      audit_history: [],
      intervention_count: 0,
      last_audit: nil,
      monitoring_state: init_monitoring_state(),
      intervention_rules: init_intervention_rules()
    }
    
    # Subscribe to S3 performance events
    EventBus.subscribe(:s3_performance)
    EventBus.subscribe(:resource_allocation_failed)
    EventBus.subscribe(:bargaining_deadlock)
    
    # Start periodic auditing
    Process.send_after(self(), :periodic_audit, @audit_interval)
    
    Logger.info("S3* Audit Subsystem initialized")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:intervene, type, params}, _from, state) do
    case execute_intervention(type, params, state) do
      {:ok, result} ->
        new_state = record_intervention(type, result, state)
        {:reply, {:ok, result}, new_state}
      
      {:error, reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:request_audit, audit_type}, _from, state) do
    audit_result = perform_audit(audit_type, state)
    new_state = record_audit(audit_result, state)
    
    # Check if intervention is needed
    if requires_intervention?(audit_result) do
      trigger_intervention(audit_result, new_state)
    end
    
    {:reply, {:ok, audit_result}, new_state}
  end
  
  @impl true
  def handle_call(:get_audit_report, _from, state) do
    report = compile_audit_report(state)
    {:reply, report, state}
  end
  
  @impl true
  def handle_info(:periodic_audit, state) do
    # Perform routine audit
    audit_result = perform_audit(:routine, state)
    new_state = record_audit(audit_result, state)
    
    # Check intervention triggers
    if requires_intervention?(audit_result) do
      new_state = trigger_intervention(audit_result, new_state)
    end
    
    # Schedule next audit
    Process.send_after(self(), :periodic_audit, @audit_interval)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :resource_allocation_failed, data}, state) do
    # Immediate audit on allocation failure
    Logger.warning("S3* detected allocation failure: #{inspect(data)}")
    
    if should_intervene_on_failure?(data, state) do
      intervention = %{
        type: :allocation_failure,
        action: :force_reallocation,
        params: data
      }
      
      new_state = execute_and_record_intervention(intervention, state)
      {:noreply, new_state}
    else
      {:noreply, update_monitoring_state(state, :allocation_failure, data)}
    end
  end
  
  @impl true
  def handle_info({:event, :bargaining_deadlock, data}, state) do
    # Intervene on bargaining deadlock
    Logger.warning("S3* detected bargaining deadlock: #{inspect(data)}")
    
    intervention = %{
      type: :bargaining_deadlock,
      action: :arbitrate,
      params: data
    }
    
    new_state = execute_and_record_intervention(intervention, state)
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp init_monitoring_state do
    %{
      allocation_failures: [],
      performance_violations: [],
      stability_measurements: [],
      bargaining_history: []
    }
  end
  
  defp init_intervention_rules do
    %{
      allocation_failure: [
        {:consecutive_failures, 3, :force_reallocation},
        {:failure_rate, 0.2, :adjust_parameters}
      ],
      performance_violation: [
        {:response_time_exceeded, 1.5, :emergency_resources},
        {:variety_absorption_low, 0.6, :spawn_units}
      ],
      stability_issue: [
        {:oscillation_detected, true, :damping_adjustment},
        {:chaos_indicator, 0.3, :stabilization_protocol}
      ]
    }
  end
  
  defp perform_audit(audit_type, state) do
    # Collect S3 performance metrics
    s3_metrics = collect_s3_metrics(state.parent_s3)
    
    # Analyze performance
    analysis = analyze_performance(s3_metrics, audit_type)
    
    # Check compliance with targets
    compliance = check_compliance(s3_metrics)
    
    %{
      type: audit_type,
      timestamp: System.monotonic_time(:millisecond),
      metrics: s3_metrics,
      analysis: analysis,
      compliance: compliance,
      recommendations: generate_recommendations(analysis, compliance)
    }
  end
  
  defp collect_s3_metrics(s3_pid) do
    # In real implementation, would query S3 Control
    # For now, return mock metrics
    %{
      allocation_efficiency: 0.75 + :rand.uniform() * 0.2,
      average_response_time: 90 + :rand.uniform() * 30,
      resource_utilization: %{
        cpu: 0.7 + :rand.uniform() * 0.2,
        memory: 0.6 + :rand.uniform() * 0.3,
        variety_capacity: 0.8 + :rand.uniform() * 0.15
      },
      bargaining_success_rate: 0.8 + :rand.uniform() * 0.15,
      stability_index: 0.85 + :rand.uniform() * 0.1
    }
  end
  
  defp analyze_performance(metrics, audit_type) do
    %{
      efficiency_trend: calculate_trend(:efficiency, metrics),
      bottlenecks: identify_bottlenecks(metrics),
      optimization_opportunities: find_optimizations(metrics),
      risk_factors: assess_risks(metrics)
    }
  end
  
  defp check_compliance(metrics) do
    %{
      allocation_efficiency: metrics.allocation_efficiency >= @intervention_threshold.allocation_efficiency,
      response_time: metrics.average_response_time <= 100 * @intervention_threshold.response_time_violation,
      stability: metrics.stability_index >= @intervention_threshold.stability_index,
      overall: compliance_score(metrics)
    }
  end
  
  defp requires_intervention?(audit_result) do
    not audit_result.compliance.overall or
    Enum.any?(audit_result.analysis.risk_factors, &(&1.severity == :high))
  end
  
  defp trigger_intervention(audit_result, state) do
    intervention_type = determine_intervention_type(audit_result)
    intervention_params = build_intervention_params(audit_result)
    
    Logger.warning("S3* triggering intervention: #{intervention_type}")
    
    execute_and_record_intervention(
      %{type: intervention_type, params: intervention_params},
      state
    )
  end
  
  defp execute_intervention(type, params, state) do
    case type do
      :force_reallocation ->
        force_resource_reallocation(params, state)
      
      :adjust_parameters ->
        adjust_s3_parameters(params, state)
      
      :emergency_resources ->
        allocate_emergency_resources(params, state)
      
      :spawn_units ->
        request_unit_spawning(params, state)
      
      :arbitrate ->
        arbitrate_bargaining(params, state)
      
      :stabilization_protocol ->
        execute_stabilization(params, state)
      
      _ ->
        {:error, :unknown_intervention_type}
    end
  end
  
  defp force_resource_reallocation(params, state) do
    # Force S3 to reallocate resources
    Logger.info("S3* forcing resource reallocation: #{inspect(params)}")
    
    # Send direct command to S3
    GenServer.cast(state.parent_s3, {:audit_intervention, :force_reallocation, params})
    
    {:ok, %{action: :forced_reallocation, params: params}}
  end
  
  defp adjust_s3_parameters(params, state) do
    # Adjust S3 operating parameters
    adjustments = calculate_parameter_adjustments(params)
    
    GenServer.call(state.parent_s3, {:audit_adjustment, adjustments})
    
    {:ok, %{action: :parameter_adjustment, adjustments: adjustments}}
  end
  
  defp allocate_emergency_resources(params, state) do
    # Emergency resource injection
    emergency_allocation = %{
      cpu: 200,
      memory: 1024,
      variety_capacity: 500
    }
    
    GenServer.cast(state.parent_s3, {:emergency_resources, emergency_allocation})
    
    {:ok, %{action: :emergency_allocation, resources: emergency_allocation}}
  end
  
  defp arbitrate_bargaining(params, state) do
    # Arbitrate deadlocked bargaining
    arbitration_decision = make_arbitration_decision(params)
    
    GenServer.cast(state.parent_s3, {:arbitration, arbitration_decision})
    
    {:ok, %{action: :arbitration, decision: arbitration_decision}}
  end
  
  defp record_intervention(type, result, state) do
    intervention_record = %{
      type: type,
      result: result,
      timestamp: System.monotonic_time(:millisecond),
      intervention_number: state.intervention_count + 1
    }
    
    # Publish intervention event
    EventBus.publish(:s3_audit_intervention, intervention_record)
    
    %{state |
      intervention_count: state.intervention_count + 1,
      audit_history: [intervention_record | state.audit_history] |> Enum.take(100)
    }
  end
  
  defp record_audit(audit_result, state) do
    %{state |
      last_audit: audit_result,
      audit_history: [audit_result | state.audit_history] |> Enum.take(50)
    }
  end
  
  defp compile_audit_report(state) do
    recent_audits = Enum.take(state.audit_history, 10)
    
    %{
      total_audits: length(state.audit_history),
      total_interventions: state.intervention_count,
      recent_audits: recent_audits,
      intervention_rate: calculate_intervention_rate(state),
      system_health: assess_system_health(recent_audits),
      recommendations: compile_recommendations(recent_audits)
    }
  end
  
  defp calculate_intervention_rate(state) do
    if length(state.audit_history) > 0 do
      state.intervention_count / length(state.audit_history)
    else
      0.0
    end
  end
  
  defp assess_system_health(recent_audits) do
    if Enum.empty?(recent_audits) do
      :unknown
    else
      avg_compliance = recent_audits
      |> Enum.map(&(&1[:compliance][:overall] || 0))
      |> Enum.sum()
      |> Kernel./(length(recent_audits))
      
      cond do
        avg_compliance > 0.9 -> :excellent
        avg_compliance > 0.8 -> :good
        avg_compliance > 0.7 -> :fair
        true -> :poor
      end
    end
  end
  
  defp compliance_score(metrics) do
    scores = [
      if(metrics.allocation_efficiency >= 0.7, do: 1, else: 0),
      if(metrics.average_response_time <= 150, do: 1, else: 0),
      if(metrics.stability_index >= 0.8, do: 1, else: 0),
      if(metrics.bargaining_success_rate >= 0.7, do: 1, else: 0)
    ]
    
    Enum.sum(scores) / length(scores)
  end
  
  defp determine_intervention_type(audit_result) do
    cond do
      not audit_result.compliance.allocation_efficiency ->
        :force_reallocation
      
      not audit_result.compliance.response_time ->
        :emergency_resources
      
      not audit_result.compliance.stability ->
        :stabilization_protocol
      
      true ->
        :adjust_parameters
    end
  end
  
  defp build_intervention_params(audit_result) do
    %{
      audit_result: audit_result,
      priority_issues: Enum.filter(audit_result.analysis.risk_factors, &(&1.severity == :high)),
      target_metrics: %{
        allocation_efficiency: 0.85,
        response_time: 100,
        stability_index: 0.9
      }
    }
  end
  
  # Stub implementations
  defp calculate_trend(_type, _metrics), do: :stable
  defp identify_bottlenecks(_metrics), do: []
  defp find_optimizations(_metrics), do: []
  defp assess_risks(_metrics), do: []
  defp should_intervene_on_failure?(_data, _state), do: :rand.uniform() > 0.7
  defp update_monitoring_state(state, _type, _data), do: state
  defp execute_and_record_intervention(intervention, state), do: state
  defp request_unit_spawning(_params, _state), do: {:ok, %{}}
  defp execute_stabilization(_params, _state), do: {:ok, %{}}
  defp calculate_parameter_adjustments(_params), do: %{}
  defp make_arbitration_decision(_params), do: %{}
  defp generate_recommendations(_analysis, _compliance), do: []
  defp compile_recommendations(_audits), do: []
end