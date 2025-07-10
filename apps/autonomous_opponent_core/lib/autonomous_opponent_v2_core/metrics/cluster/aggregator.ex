defmodule AutonomousOpponentV2Core.Metrics.Cluster.Aggregator do
  @moduledoc """
  🧠 CYBERNETIC METRICS AGGREGATOR - THE NERVOUS SYSTEM OF THE VSM
  
  This module implements distributed metrics aggregation following Stafford Beer's
  principles of variety engineering. It acts as the sensory apparatus that maintains
  requisite variety for human operators over the distributed system.
  
  ## Variety Management
  
  Each node generates operational variety V_node. Without aggregation:
  - Total variety = V_node^n (exponential explosion)
  - Human cognitive capacity = ~7±2 items (Miller's Law)
  - Result: System becomes uncontrollable
  
  This aggregator provides variety attenuation through:
  - Statistical summarization (mean, percentiles)
  - Dimensional reduction (grouping by subsystem)
  - Temporal aggregation (rolling windows)
  - Alert thresholds (continuous → discrete)
  
  ## VSM Mapping
  
  - S1: Operational metrics from each node
  - S2: Cross-node coordination and anti-oscillation
  - S3: Resource optimization and control decisions
  - S4: Environmental scanning and trend detection
  - S5: Policy-level KPIs and governance metrics
  
  ## Algedonic Channels
  
  Critical metrics bypass normal aggregation for immediate action:
  - Pain signals: System failures, resource exhaustion
  - Pleasure signals: Performance records, optimizations
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Core.Metrics
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Metrics.Cluster.CRDTStore
  alias AutonomousOpponentV2Core.EventBus.Cluster.VarietyManager
  
  @aggregation_interval :timer.seconds(10)
  @query_timeout :timer.seconds(5)
  @max_nodes 100
  @variety_quota 1000  # Max metrics/second
  
  # VSM time constants for different control loops
  @time_constants %{
    algedonic: 100,        # 100ms - immediate pain/pleasure
    operational: 1_000,    # 1s - S1/S2 operations
    tactical: 5_000,       # 5s - S3 control
    strategic: 30_000,     # 30s - S4 intelligence
    policy: 60_000         # 1min - S5 governance
  }
  
  defstruct [
    :node_registry,
    :aggregation_rules,
    :cache,
    :circuit_breakers,
    :variety_tracker,
    :last_aggregation,
    :pending_aggregations
  ]
  
  # ========== CLIENT API ==========
  
  @doc """
  Starts the metrics aggregator with cybernetic consciousness
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Aggregates metrics across all nodes in the cluster
  """
  def aggregate_cluster_metrics(opts \\ []) do
    timeout = opts[:timeout] || @query_timeout * 2
    GenServer.call(__MODULE__, {:aggregate_all, opts}, timeout)
  end
  
  @doc """
  Aggregates a specific metric across the cluster
  """
  def aggregate_metric(metric_name, opts \\ []) do
    GenServer.call(__MODULE__, {:aggregate_metric, metric_name, opts})
  end
  
  @doc """
  Queries aggregated metrics with time range
  """
  def query_time_range(metric_name, start_time, end_time, opts \\ []) do
    GenServer.call(__MODULE__, {:query_range, metric_name, start_time, end_time, opts})
  end
  
  @doc """
  Gets cluster-wide VSM health metrics
  """
  def vsm_health do
    GenServer.call(__MODULE__, :vsm_health)
  end
  
  @doc """
  Triggers immediate aggregation (for algedonic signals)
  """
  def aggregate_now!(metric_name, reason \\ :algedonic) do
    GenServer.cast(__MODULE__, {:aggregate_immediate, metric_name, reason})
  end
  
  # ========== CALLBACKS ==========
  
  @impl true
  def init(opts) do
    Logger.info("🧠 Initializing Cybernetic Metrics Aggregator...")
    
    # Subscribe to relevant events
    EventBus.subscribe(:metrics_update)
    EventBus.subscribe(:algedonic_signal)
    EventBus.subscribe(:node_status_change)
    
    # Join the metrics cluster
    :pg.join(:metrics_cluster, :aggregator, self())
    
    # Initialize state
    state = %__MODULE__{
      node_registry: MapSet.new([node() | Node.list()]),
      aggregation_rules: load_aggregation_rules(),
      cache: init_cache(),
      circuit_breakers: init_circuit_breakers(),
      variety_tracker: %{current: 0, limit: @variety_quota},
      last_aggregation: %{},
      pending_aggregations: []
    }
    
    # Schedule first aggregation
    schedule_aggregation(@aggregation_interval)
    
    # Monitor nodes
    :net_kernel.monitor_nodes(true)
    
    Logger.info("✅ Metrics Aggregator initialized - Ready for distributed consciousness!")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:aggregate_all, opts}, _from, state) do
    Logger.debug("🔄 Aggregating all cluster metrics...")
    
    # Check variety constraints
    case check_variety_constraint(state) do
      {:ok, new_state} ->
        results = perform_cluster_aggregation(new_state, opts)
        {:reply, {:ok, results}, new_state}
        
      {:error, :variety_exceeded} ->
        Logger.warn("⚠️ Variety quota exceeded - returning cached results")
        {:reply, {:ok, get_cached_results(state)}, state}
    end
  end
  
  @impl true
  def handle_call({:aggregate_metric, metric_name, opts}, _from, state) do
    case aggregate_single_metric(metric_name, state, opts) do
      {:ok, result, new_state} ->
        {:reply, {:ok, result}, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:query_range, metric_name, start_time, end_time, opts}, _from, state) do
    # Query from CRDT store with time range
    result = CRDTStore.query_metric_range(metric_name, start_time, end_time, opts)
    {:reply, {:ok, result}, state}
  end
  
  @impl true
  def handle_call(:vsm_health, _from, state) do
    health = calculate_vsm_health(state)
    {:reply, {:ok, health}, state}
  end
  
  @impl true
  def handle_cast({:aggregate_immediate, metric_name, reason}, state) do
    Logger.info("⚡ Immediate aggregation requested for #{metric_name} (#{reason})")
    
    # Bypass variety constraints for algedonic signals
    if reason == :algedonic do
      {:ok, result, new_state} = aggregate_single_metric(metric_name, state, [bypass: true])
      broadcast_algedonic_result(metric_name, result)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:scheduled_aggregation, state) do
    Logger.debug("⏱️ Scheduled aggregation triggered")
    
    # Perform aggregation based on time constants
    new_state = perform_tiered_aggregation(state)
    
    # Schedule next aggregation
    schedule_aggregation(@aggregation_interval)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    Logger.info("🌟 Node joined cluster: #{node}")
    
    new_state = %{state | 
      node_registry: MapSet.put(state.node_registry, node)
    }
    
    # Trigger discovery aggregation
    GenServer.cast(self(), {:aggregate_immediate, "node_discovery", :topology_change})
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:nodedown, node, _info}, state) do
    Logger.warn("💔 Node left cluster: #{node}")
    
    new_state = %{state | 
      node_registry: MapSet.delete(state.node_registry, node)
    }
    
    # Mark node metrics as stale
    mark_node_metrics_stale(node)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{event_name: :metrics_update} = event}, state) do
    # Check if this is a cluster-wide metric event
    if should_aggregate_event?(event) do
      state = queue_aggregation(event.data.metric_name, state)
      process_pending_aggregations(state)
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{event_name: :algedonic_signal} = event}, state) do
    # Immediate aggregation for algedonic signals
    Logger.warn("🚨 Algedonic signal received: #{inspect(event.data)}")
    
    metric_name = "algedonic.#{event.data.type}.#{event.data.source}"
    GenServer.cast(self(), {:aggregate_immediate, metric_name, :algedonic})
    
    {:noreply, state}
  end
  
  # ========== PRIVATE FUNCTIONS ==========
  
  defp perform_cluster_aggregation(state, opts) do
    nodes = MapSet.to_list(state.node_registry)
    
    # Use :erpc for efficient multi-node query
    task_timeout = opts[:timeout] || @query_timeout
    
    # Fan-out to all nodes
    results = :erpc.multicall(
      nodes,
      Metrics,
      :get_all_metrics,
      [Metrics],
      task_timeout
    )
    
    # Process results
    {metrics, errors} = process_multicall_results(results, nodes)
    
    # Log any errors
    Enum.each(errors, fn {node, reason} ->
      Logger.warn("Failed to collect from #{node}: #{inspect(reason)}")
    end)
    
    # Aggregate by metric name and type
    aggregated = aggregate_metrics_by_type(metrics)
    
    # Update cache
    state = update_cache(state, aggregated)
    
    # Update CRDT store
    persist_to_crdt(aggregated)
    
    # Emit telemetry
    emit_aggregation_telemetry(aggregated, length(nodes), length(errors))
    
    aggregated
  end
  
  defp aggregate_single_metric(metric_name, state, opts) do
    nodes = MapSet.to_list(state.node_registry)
    
    # Check variety unless bypassed
    unless opts[:bypass] do
      case check_variety_constraint(state) do
        {:error, :variety_exceeded} ->
          return {:error, :variety_exceeded}
        {:ok, state} ->
          :ok
      end
    end
    
    # Query specific metric from all nodes
    results = :erpc.multicall(
      nodes,
      Metrics,
      :get_metric,
      [Metrics, metric_name],
      @query_timeout
    )
    
    {values, _errors} = process_multicall_results(results, nodes)
    
    # Aggregate based on metric type
    aggregated = aggregate_by_type(metric_name, values)
    
    # Update CRDT
    CRDTStore.update_metric(metric_name, aggregated, node())
    
    {:ok, aggregated, state}
  end
  
  defp process_multicall_results({results, bad_nodes}, nodes) do
    # Process successful results
    metrics = nodes
    |> Enum.zip(results)
    |> Enum.flat_map(fn
      {node, {:ok, node_metrics}} when is_list(node_metrics) ->
        Enum.map(node_metrics, fn {key, value} ->
          %{
            key: key,
            value: value,
            node: node,
            timestamp: System.os_time(:millisecond)
          }
        end)
      {node, {:ok, node_metrics}} when is_map(node_metrics) ->
        Enum.map(node_metrics, fn {key, value} ->
          %{
            key: key,
            value: value,
            node: node,
            timestamp: System.os_time(:millisecond)
          }
        end)
      {node, {:error, reason}} ->
        Logger.warn("Error collecting from #{node}: #{inspect(reason)}")
        []
    end)
    
    # Process bad nodes
    errors = Enum.map(bad_nodes, fn node ->
      {node, :noconnection}
    end)
    
    {metrics, errors}
  end
  
  defp aggregate_metrics_by_type(metrics) do
    metrics
    |> Enum.group_by(& &1.key)
    |> Enum.map(fn {key, values} ->
      type = infer_metric_type(key)
      aggregated_value = aggregate_by_type(key, values)
      
      %{
        name: key,
        type: type,
        aggregated: aggregated_value,
        node_values: Enum.map(values, fn v -> {v.node, v.value} end),
        timestamp: System.os_time(:millisecond)
      }
    end)
  end
  
  defp aggregate_by_type(metric_name, values) when is_list(values) do
    numeric_values = values
    |> Enum.map(fn
      %{value: v} -> to_number(v)
      v -> to_number(v)
    end)
    |> Enum.filter(&is_number/1)
    
    case infer_metric_type(metric_name) do
      :counter ->
        %{
          sum: Enum.sum(numeric_values),
          count: length(numeric_values)
        }
        
      :gauge ->
        if length(numeric_values) > 0 do
          %{
            avg: Enum.sum(numeric_values) / length(numeric_values),
            min: Enum.min(numeric_values),
            max: Enum.max(numeric_values),
            count: length(numeric_values)
          }
        else
          %{avg: 0, min: 0, max: 0, count: 0}
        end
        
      :histogram ->
        percentiles = calculate_percentiles(numeric_values)
        %{
          p50: percentiles[:p50],
          p95: percentiles[:p95],
          p99: percentiles[:p99],
          count: length(numeric_values)
        }
        
      _ ->
        %{values: numeric_values}
    end
  end
  
  defp infer_metric_type(metric_name) do
    cond do
      String.contains?(metric_name, "_total") -> :counter
      String.contains?(metric_name, "_count") -> :counter
      String.contains?(metric_name, "_sum") -> :counter
      String.contains?(metric_name, "_gauge") -> :gauge
      String.contains?(metric_name, "_duration") -> :histogram
      String.contains?(metric_name, "_latency") -> :histogram
      String.contains?(metric_name, "_size") -> :histogram
      String.starts_with?(metric_name, "vsm.") -> :gauge
      String.contains?(metric_name, "algedonic") -> :gauge
      true -> :gauge
    end
  end
  
  defp calculate_percentiles([]), do: %{p50: 0, p95: 0, p99: 0}
  defp calculate_percentiles(values) do
    sorted = Enum.sort(values)
    len = length(sorted)
    
    %{
      p50: Enum.at(sorted, trunc(len * 0.50)),
      p95: Enum.at(sorted, trunc(len * 0.95)),
      p99: Enum.at(sorted, trunc(len * 0.99))
    }
  end
  
  defp to_number(v) when is_number(v), do: v
  defp to_number(v) when is_binary(v) do
    case Float.parse(v) do
      {num, _} -> num
      :error -> 0
    end
  end
  defp to_number(_), do: 0
  
  defp check_variety_constraint(state) do
    current_variety = state.variety_tracker.current
    
    if current_variety < state.variety_tracker.limit do
      new_tracker = %{state.variety_tracker | current: current_variety + 1}
      {:ok, %{state | variety_tracker: new_tracker}}
    else
      {:error, :variety_exceeded}
    end
  end
  
  defp perform_tiered_aggregation(state) do
    current_time = System.os_time(:millisecond)
    
    # Aggregate different metrics based on their time constants
    Enum.reduce(@time_constants, state, fn {tier, interval}, acc_state ->
      last_run = Map.get(acc_state.last_aggregation, tier, 0)
      
      if current_time - last_run >= interval do
        # Aggregate metrics for this tier
        metrics = get_metrics_for_tier(tier)
        
        Enum.each(metrics, fn metric ->
          aggregate_single_metric(metric, acc_state, [tier: tier])
        end)
        
        put_in(acc_state.last_aggregation[tier], current_time)
      else
        acc_state
      end
    end)
  end
  
  defp get_metrics_for_tier(:algedonic), do: ["algedonic.*"]
  defp get_metrics_for_tier(:operational), do: ["vsm.s1.*", "vsm.s2.*"]
  defp get_metrics_for_tier(:tactical), do: ["vsm.s3.*", "resource.*"]
  defp get_metrics_for_tier(:strategic), do: ["vsm.s4.*", "pattern.*"]
  defp get_metrics_for_tier(:policy), do: ["vsm.s5.*", "sla.*"]
  
  defp calculate_vsm_health(state) do
    # Aggregate VSM subsystem health across cluster
    nodes = MapSet.to_list(state.node_registry)
    
    vsm_metrics = :erpc.multicall(
      nodes,
      __MODULE__,
      :get_local_vsm_metrics,
      [],
      @query_timeout
    )
    
    {health_data, _} = process_multicall_results(vsm_metrics, nodes)
    
    # Calculate aggregate health
    %{
      s1_operational: aggregate_health(health_data, "vsm.s1"),
      s2_coordination: aggregate_health(health_data, "vsm.s2"),
      s3_control: aggregate_health(health_data, "vsm.s3"),
      s4_intelligence: aggregate_health(health_data, "vsm.s4"),
      s5_policy: aggregate_health(health_data, "vsm.s5"),
      algedonic_balance: calculate_algedonic_balance(health_data),
      variety_pressure: calculate_variety_pressure(state),
      cluster_viability: calculate_cluster_viability(health_data)
    }
  end
  
  defp aggregate_health(data, prefix) do
    values = data
    |> Enum.filter(fn %{key: k} -> String.starts_with?(k, prefix) end)
    |> Enum.map(fn %{value: v} -> to_number(v) end)
    
    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0.0
    end
  end
  
  defp calculate_algedonic_balance(data) do
    pain = aggregate_health(data, "algedonic.pain")
    pleasure = aggregate_health(data, "algedonic.pleasure")
    
    # Balance score: -1 (all pain) to +1 (all pleasure)
    if pain + pleasure > 0 do
      (pleasure - pain) / (pleasure + pain)
    else
      0.0
    end
  end
  
  defp calculate_variety_pressure(state) do
    # Variety pressure as percentage of quota
    (state.variety_tracker.current / state.variety_tracker.limit) * 100
  end
  
  defp calculate_cluster_viability(health_data) do
    # Overall viability score based on all subsystems
    subsystem_health = [
      aggregate_health(health_data, "vsm.s1"),
      aggregate_health(health_data, "vsm.s2"),
      aggregate_health(health_data, "vsm.s3"),
      aggregate_health(health_data, "vsm.s4"),
      aggregate_health(health_data, "vsm.s5")
    ]
    
    # Viability requires all subsystems above threshold
    min_health = Enum.min(subsystem_health)
    avg_health = Enum.sum(subsystem_health) / 5
    
    # Score based on minimum and average
    (min_health * 0.7 + avg_health * 0.3) * 100
  end
  
  defp persist_to_crdt(aggregated_metrics) do
    Enum.each(aggregated_metrics, fn metric ->
      CRDTStore.persist_aggregated_metric(metric)
    end)
  end
  
  defp emit_aggregation_telemetry(metrics, total_nodes, failed_nodes) do
    :telemetry.execute(
      [:metrics, :cluster, :aggregation],
      %{
        metrics_count: length(metrics),
        total_nodes: total_nodes,
        failed_nodes: failed_nodes,
        timestamp: System.os_time(:millisecond)
      },
      %{node: node()}
    )
  end
  
  defp broadcast_algedonic_result(metric_name, result) do
    # Broadcast via Phoenix.PubSub for immediate action
    Phoenix.PubSub.broadcast(
      AutonomousOpponentV2Core.PubSub,
      "algedonic:critical",
      {:algedonic_metric, metric_name, result}
    )
  end
  
  defp should_aggregate_event?(%{data: %{aggregate: true}}), do: true
  defp should_aggregate_event?(%{data: %{metric_name: name}}) do
    # Aggregate VSM and critical metrics
    String.starts_with?(name, "vsm.") or
    String.contains?(name, "algedonic") or
    String.contains?(name, "cluster")
  end
  defp should_aggregate_event?(_), do: false
  
  defp queue_aggregation(metric_name, state) do
    if metric_name not in state.pending_aggregations do
      %{state | pending_aggregations: [metric_name | state.pending_aggregations]}
    else
      state
    end
  end
  
  defp process_pending_aggregations(state) do
    if length(state.pending_aggregations) > 0 do
      # Process in batches to avoid overwhelming the system
      {to_process, remaining} = Enum.split(state.pending_aggregations, 10)
      
      Enum.each(to_process, fn metric ->
        aggregate_single_metric(metric, state, [])
      end)
      
      %{state | pending_aggregations: remaining}
    else
      state
    end
  end
  
  defp load_aggregation_rules do
    # Load rules for how to aggregate different metric types
    %{
      "vsm.variety_absorbed" => :sum,
      "vsm.variety_generated" => :sum,
      "algedonic.pain" => :max,  # Worst pain wins
      "algedonic.pleasure" => :avg,  # Average pleasure
      "resource.cpu" => :avg,
      "resource.memory" => :avg,
      "errors.total" => :sum,
      "latency" => :percentile
    }
  end
  
  defp init_cache do
    # Initialize ETS cache for fast lookups
    :ets.new(:metrics_cache, [:set, :public, {:read_concurrency, true}])
  end
  
  defp init_circuit_breakers do
    # Initialize circuit breakers for each node
    %{}
  end
  
  defp update_cache(state, metrics) do
    # Update cache with latest aggregated metrics
    Enum.each(metrics, fn metric ->
      :ets.insert(state.cache, {metric.name, metric})
    end)
    state
  end
  
  defp get_cached_results(state) do
    :ets.tab2list(state.cache)
    |> Enum.map(fn {_key, value} -> value end)
  end
  
  defp mark_node_metrics_stale(node) do
    # Mark metrics from failed node as stale in CRDT
    CRDTStore.mark_node_stale(node)
  end
  
  defp schedule_aggregation(interval) do
    Process.send_after(self(), :scheduled_aggregation, interval)
  end
  
  # Local function for RPC calls
  def get_local_vsm_metrics do
    # Get VSM metrics from local node
    Metrics.get_by_prefix(Metrics, "vsm.")
  end
end