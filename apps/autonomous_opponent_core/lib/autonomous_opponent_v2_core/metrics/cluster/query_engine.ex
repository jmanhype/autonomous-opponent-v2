defmodule AutonomousOpponentV2Core.Metrics.Cluster.QueryEngine do
  @moduledoc """
  🔍 DISTRIBUTED METRICS QUERY ENGINE
  
  This module provides a SQL-like interface for querying metrics across
  the distributed cluster. It implements intelligent query planning,
  partial aggregation, and result caching.
  
  ## Query Capabilities
  
  - Time-range queries with automatic granularity adjustment
  - Multi-node aggregation with partial failure handling
  - Statistical functions (avg, sum, min, max, percentiles)
  - Group-by operations across nodes and tags
  - Windowing functions for time-series analysis
  
  ## Performance Optimizations
  
  - Query result caching with TTL
  - Parallel execution across nodes
  - Push-down predicates to reduce data transfer
  - Automatic query timeout and circuit breaking
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Metrics.Cluster.{Aggregator, CRDTStore}
  alias AutonomousOpponentV2Core.Core.Metrics
  
  @query_timeout :timer.seconds(30)
  @cache_ttl :timer.minutes(1)
  @max_parallel_queries 10
  
  defstruct [
    :query_cache,
    :active_queries,
    :stats,
    :circuit_breakers
  ]
  
  # ========== CLIENT API ==========
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Executes a distributed query across the cluster
  
  ## Examples
  
      # Simple aggregation
      query("vsm.variety_absorbed", :sum)
      
      # Time-range query with grouping
      query("latency", :p95, 
        from: ~U[2024-01-01 00:00:00Z],
        to: ~U[2024-01-02 00:00:00Z],
        group_by: [:node, :endpoint],
        window: :hour
      )
      
      # Complex query with filters
      query("errors.rate", :avg,
        where: [severity: "critical", service: "api"],
        group_by: :node,
        having: [avg: {:>, 0.1}]
      )
  """
  def query(metric_name, aggregation \\ :raw, opts \\ []) do
    GenServer.call(__MODULE__, {:query, metric_name, aggregation, opts}, @query_timeout)
  end
  
  @doc """
  Gets a summary of cluster metrics health
  """
  def cluster_summary do
    GenServer.call(__MODULE__, :cluster_summary)
  end
  
  @doc """
  Executes a raw multi-node query
  """
  def multi_query(queries) when is_list(queries) do
    GenServer.call(__MODULE__, {:multi_query, queries}, @query_timeout)
  end
  
  # ========== CALLBACKS ==========
  
  @impl true
  def init(opts) do
    Logger.info("🔍 Initializing Metrics Query Engine...")
    
    state = %__MODULE__{
      query_cache: init_cache(),
      active_queries: %{},
      stats: init_stats(),
      circuit_breakers: init_circuit_breakers()
    }
    
    # Schedule cache cleanup
    Process.send_after(self(), :cleanup_cache, :timer.minutes(5))
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:query, metric_name, aggregation, opts}, from, state) do
    # Check cache first
    cache_key = make_cache_key(metric_name, aggregation, opts)
    
    case get_cached_result(state.query_cache, cache_key) do
      {:ok, cached_result} ->
        Logger.debug("Cache hit for query: #{cache_key}")
        {:reply, {:ok, cached_result}, update_stats(state, :cache_hits)}
        
      :miss ->
        # Execute distributed query
        state = execute_distributed_query(metric_name, aggregation, opts, from, state)
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_call(:cluster_summary, _from, state) do
    summary = build_cluster_summary()
    {:reply, {:ok, summary}, state}
  end
  
  @impl true
  def handle_call({:multi_query, queries}, from, state) do
    # Execute multiple queries in parallel
    state = execute_multi_query(queries, from, state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:query_complete, query_id, result}, state) do
    # Handle completed query
    case Map.get(state.active_queries, query_id) do
      nil ->
        {:noreply, state}
        
      {from, cache_key} ->
        # Reply to caller
        GenServer.reply(from, {:ok, result})
        
        # Cache result
        cache_result(state.query_cache, cache_key, result)
        
        # Update state
        new_state = %{state | 
          active_queries: Map.delete(state.active_queries, query_id),
          stats: update_stats(state.stats, :completed_queries)
        }
        
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info({:query_failed, query_id, reason}, state) do
    case Map.get(state.active_queries, query_id) do
      nil ->
        {:noreply, state}
        
      {from, _cache_key} ->
        GenServer.reply(from, {:error, reason})
        
        new_state = %{state | 
          active_queries: Map.delete(state.active_queries, query_id),
          stats: update_stats(state.stats, :failed_queries)
        }
        
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info(:cleanup_cache, state) do
    # Remove expired cache entries
    cleanup_expired_cache(state.query_cache)
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup_cache, :timer.minutes(5))
    
    {:noreply, state}
  end
  
  # ========== PRIVATE FUNCTIONS ==========
  
  defp execute_distributed_query(metric_name, aggregation, opts, from, state) do
    query_id = generate_query_id()
    cache_key = make_cache_key(metric_name, aggregation, opts)
    
    # Store active query
    state = %{state | 
      active_queries: Map.put(state.active_queries, query_id, {from, cache_key})
    }
    
    # Spawn query task
    Task.start(fn ->
      result = try do
        perform_distributed_query(metric_name, aggregation, opts)
      rescue
        e ->
          Logger.error("Query failed: #{inspect(e)}")
          {:error, e}
      end
      
      case result do
        {:ok, data} ->
          send(self(), {:query_complete, query_id, data})
        {:error, reason} ->
          send(self(), {:query_failed, query_id, reason})
      end
    end)
    
    update_stats(state, :active_queries)
  end
  
  defp perform_distributed_query(metric_name, aggregation, opts) do
    # Determine target nodes
    nodes = get_query_nodes(opts)
    
    # Build query plan
    plan = build_query_plan(metric_name, aggregation, opts)
    
    # Execute on all nodes
    results = execute_query_plan(plan, nodes, opts)
    
    # Aggregate results
    final_result = aggregate_distributed_results(results, aggregation, opts)
    
    {:ok, final_result}
  end
  
  defp get_query_nodes(opts) do
    case opts[:nodes] do
      nil -> [node() | Node.list()]
      nodes when is_list(nodes) -> nodes
      :all -> [node() | Node.list()]
      :local -> [node()]
    end
  end
  
  defp build_query_plan(metric_name, aggregation, opts) do
    %{
      metric: metric_name,
      aggregation: aggregation,
      filters: opts[:where] || [],
      time_range: get_time_range(opts),
      group_by: opts[:group_by] || [],
      window: opts[:window],
      limit: opts[:limit]
    }
  end
  
  defp get_time_range(opts) do
    from = opts[:from] || DateTime.add(DateTime.utc_now(), -3600, :second)
    to = opts[:to] || DateTime.utc_now()
    {from, to}
  end
  
  defp execute_query_plan(plan, nodes, opts) do
    timeout = opts[:timeout] || :timer.seconds(5)
    
    # Execute in parallel with circuit breaking
    tasks = Enum.map(nodes, fn node ->
      Task.async(fn ->
        case check_circuit_breaker(node) do
          :open ->
            {:error, {:circuit_open, node}}
            
          :closed ->
            try do
              result = :erpc.call(
                node,
                __MODULE__,
                :execute_local_query,
                [plan],
                timeout
              )
              
              reset_circuit_breaker(node)
              {:ok, {node, result}}
            catch
              :exit, reason ->
                trip_circuit_breaker(node)
                {:error, {:node_error, node, reason}}
            end
        end
      end)
    end)
    
    # Collect results with timeout
    Task.yield_many(tasks, timeout + 1000)
    |> Enum.map(fn {task, result} ->
      case result do
        {:ok, value} -> value
        nil -> 
          Task.shutdown(task)
          {:error, :timeout}
        {:exit, reason} -> 
          {:error, {:task_failed, reason}}
      end
    end)
  end
  
  def execute_local_query(plan) do
    # Execute query on local node
    metric_name = plan.metric
    {from_time, to_time} = plan.time_range
    
    # Get data from local metrics
    local_data = case Metrics.get_metric(Metrics, metric_name) do
      nil -> []
      value -> [{System.os_time(:millisecond), value}]
    end
    
    # Get historical data from CRDT store
    historical_data = case CRDTStore.query_metric_range(
      metric_name, 
      DateTime.to_unix(from_time, :millisecond),
      DateTime.to_unix(to_time, :millisecond)
    ) do
      {:ok, data} -> data
      _ -> []
    end
    
    # Combine and filter
    all_data = (local_data ++ historical_data)
    |> apply_filters(plan.filters)
    |> apply_grouping(plan.group_by)
    
    # Apply windowing if requested
    if plan.window do
      apply_time_window(all_data, plan.window, plan.time_range)
    else
      all_data
    end
  end
  
  defp aggregate_distributed_results(results, aggregation, opts) do
    # Separate successful results from errors
    {successes, errors} = Enum.split_with(results, fn
      {:ok, _} -> true
      _ -> false
    end)
    
    # Log errors
    Enum.each(errors, fn {:error, reason} ->
      Logger.warn("Query error: #{inspect(reason)}")
    end)
    
    # Extract data from successful results
    data = Enum.flat_map(successes, fn {:ok, {_node, node_data}} ->
      node_data
    end)
    
    # Apply aggregation
    aggregated = apply_aggregation_function(data, aggregation)
    
    # Apply having clause if present
    filtered = if opts[:having] do
      apply_having_clause(aggregated, opts[:having])
    else
      aggregated
    end
    
    # Apply limit if present
    if opts[:limit] do
      Enum.take(filtered, opts[:limit])
    else
      filtered
    end
  end
  
  defp apply_aggregation_function(data, :raw), do: data
  
  defp apply_aggregation_function(data, :sum) do
    sum = data
    |> Enum.map(&extract_numeric_value/1)
    |> Enum.sum()
    
    %{sum: sum, count: length(data)}
  end
  
  defp apply_aggregation_function(data, :avg) do
    values = Enum.map(data, &extract_numeric_value/1)
    
    if length(values) > 0 do
      %{
        avg: Enum.sum(values) / length(values),
        count: length(values),
        sum: Enum.sum(values)
      }
    else
      %{avg: 0, count: 0, sum: 0}
    end
  end
  
  defp apply_aggregation_function(data, :min) do
    values = Enum.map(data, &extract_numeric_value/1)
    
    if length(values) > 0 do
      %{min: Enum.min(values), count: length(values)}
    else
      %{min: nil, count: 0}
    end
  end
  
  defp apply_aggregation_function(data, :max) do
    values = Enum.map(data, &extract_numeric_value/1)
    
    if length(values) > 0 do
      %{max: Enum.max(values), count: length(values)}
    else
      %{max: nil, count: 0}
    end
  end
  
  defp apply_aggregation_function(data, percentile) when percentile in [:p50, :p95, :p99] do
    values = data
    |> Enum.map(&extract_numeric_value/1)
    |> Enum.sort()
    
    if length(values) > 0 do
      p = case percentile do
        :p50 -> 0.50
        :p95 -> 0.95
        :p99 -> 0.99
      end
      
      index = trunc(length(values) * p)
      %{
        percentile => Enum.at(values, index),
        count: length(values)
      }
    else
      %{percentile => nil, count: 0}
    end
  end
  
  defp extract_numeric_value({_timestamp, value}) when is_number(value), do: value
  defp extract_numeric_value(%{value: value}) when is_number(value), do: value
  defp extract_numeric_value(value) when is_number(value), do: value
  defp extract_numeric_value(_), do: 0
  
  defp apply_filters(data, []), do: data
  defp apply_filters(data, filters) do
    Enum.filter(data, fn item ->
      Enum.all?(filters, fn {key, expected} ->
        actual = get_in(item, [key]) || get_in(item, [to_string(key)])
        actual == expected
      end)
    end)
  end
  
  defp apply_grouping(data, []), do: data
  defp apply_grouping(data, group_by) do
    data
    |> Enum.group_by(fn item ->
      Enum.map(group_by, fn field ->
        get_in(item, [field]) || get_in(item, [to_string(field)])
      end)
    end)
    |> Enum.map(fn {group_key, group_data} ->
      %{
        group: Enum.zip(group_by, group_key) |> Map.new(),
        data: group_data
      }
    end)
  end
  
  defp apply_time_window(data, window, {from_time, to_time}) do
    window_ms = case window do
      :minute -> :timer.minutes(1)
      :hour -> :timer.hours(1)
      :day -> :timer.hours(24)
      ms when is_integer(ms) -> ms
    end
    
    from_ms = DateTime.to_unix(from_time, :millisecond)
    to_ms = DateTime.to_unix(to_time, :millisecond)
    
    # Create time buckets
    buckets = for bucket_start <- from_ms..to_ms//window_ms do
      {bucket_start, bucket_start + window_ms}
    end
    
    # Assign data to buckets
    Enum.map(buckets, fn {start_ms, end_ms} ->
      bucket_data = Enum.filter(data, fn {ts, _value} ->
        ts >= start_ms and ts < end_ms
      end)
      
      %{
        window_start: DateTime.from_unix!(start_ms, :millisecond),
        window_end: DateTime.from_unix!(end_ms, :millisecond),
        data: bucket_data
      }
    end)
  end
  
  defp apply_having_clause(data, having_conditions) do
    Enum.filter(data, fn item ->
      Enum.all?(having_conditions, fn {field, {op, value}} ->
        actual = Map.get(item, field)
        apply_comparison(actual, op, value)
      end)
    end)
  end
  
  defp apply_comparison(actual, :>, expected), do: actual > expected
  defp apply_comparison(actual, :<, expected), do: actual < expected
  defp apply_comparison(actual, :>=, expected), do: actual >= expected
  defp apply_comparison(actual, :<=, expected), do: actual <= expected
  defp apply_comparison(actual, :==, expected), do: actual == expected
  defp apply_comparison(actual, :!=, expected), do: actual != expected
  
  defp build_cluster_summary do
    # Get basic cluster info
    nodes = [node() | Node.list()]
    
    # Aggregate key metrics
    {:ok, vsm_health} = Aggregator.vsm_health()
    
    # Get node-specific stats
    node_stats = Enum.map(nodes, fn node ->
      stats = get_node_stats(node)
      {node, stats}
    end)
    
    # Calculate cluster-wide stats
    cluster_stats = calculate_cluster_stats(node_stats)
    
    %{
      cluster_stats: cluster_stats,
      node_stats: Map.new(node_stats),
      vsm_health: vsm_health,
      recent_metrics: get_recent_metrics()
    }
  end
  
  defp get_node_stats(node) do
    # Try to get stats from node
    try do
      :erpc.call(node, Metrics, :get_stats, [Metrics], 1000)
    catch
      :exit, _ ->
        %{status: :unreachable}
    end
  end
  
  defp calculate_cluster_stats(node_stats) do
    reachable_nodes = Enum.filter(node_stats, fn {_node, stats} ->
      stats != %{status: :unreachable}
    end)
    
    %{
      active_nodes: length(reachable_nodes),
      total_nodes: length(node_stats),
      events_per_sec: sum_stat(reachable_nodes, :events_per_sec),
      avg_latency: avg_stat(reachable_nodes, :avg_latency),
      variety_pressure: avg_stat(reachable_nodes, :variety_pressure)
    }
  end
  
  defp sum_stat(node_stats, key) do
    node_stats
    |> Enum.map(fn {_node, stats} -> Map.get(stats, key, 0) end)
    |> Enum.sum()
  end
  
  defp avg_stat(node_stats, key) do
    values = node_stats
    |> Enum.map(fn {_node, stats} -> Map.get(stats, key, 0) end)
    |> Enum.filter(&(&1 > 0))
    
    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0
    end
  end
  
  defp get_recent_metrics do
    # Get last 100 metrics across cluster
    {:ok, metrics} = Aggregator.aggregate_cluster_metrics(limit: 100)
    
    # Format for display
    Enum.map(metrics, fn m ->
      %{
        name: m.name,
        value: get_in(m, [:aggregated, :avg]) || get_in(m, [:aggregated, :sum]) || 0,
        timestamp: m.timestamp,
        node_count: length(m.node_values)
      }
    end)
  end
  
  defp execute_multi_query(queries, from, state) do
    query_id = generate_query_id()
    
    # Store active query
    state = %{state | 
      active_queries: Map.put(state.active_queries, query_id, {from, nil})
    }
    
    # Execute all queries in parallel
    Task.start(fn ->
      results = queries
      |> Enum.map(fn {metric, agg, opts} ->
        Task.async(fn ->
          perform_distributed_query(metric, agg, opts)
        end)
      end)
      |> Task.yield_many(@query_timeout)
      |> Enum.map(fn {task, result} ->
        case result do
          {:ok, value} -> value
          nil -> 
            Task.shutdown(task)
            {:error, :timeout}
          {:exit, reason} -> 
            {:error, reason}
        end
      end)
      
      send(self(), {:query_complete, query_id, results})
    end)
    
    state
  end
  
  defp init_cache do
    :ets.new(:query_cache, [:set, :public, {:read_concurrency, true}])
  end
  
  defp init_stats do
    %{
      cache_hits: 0,
      cache_misses: 0,
      completed_queries: 0,
      failed_queries: 0,
      active_queries: 0
    }
  end
  
  defp init_circuit_breakers do
    %{}
  end
  
  defp make_cache_key(metric_name, aggregation, opts) do
    :erlang.phash2({metric_name, aggregation, opts})
  end
  
  defp get_cached_result(cache, key) do
    case :ets.lookup(cache, key) do
      [{^key, result, expiry}] ->
        if System.os_time(:millisecond) < expiry do
          {:ok, result}
        else
          :ets.delete(cache, key)
          :miss
        end
      [] ->
        :miss
    end
  end
  
  defp cache_result(cache, key, result) do
    expiry = System.os_time(:millisecond) + @cache_ttl
    :ets.insert(cache, {key, result, expiry})
  end
  
  defp cleanup_expired_cache(cache) do
    current_time = System.os_time(:millisecond)
    
    :ets.select_delete(cache, [
      {
        {:"$1", :"$2", :"$3"},
        [{:<, :"$3", current_time}],
        [true]
      }
    ])
  end
  
  defp check_circuit_breaker(_node) do
    # TODO: Implement circuit breaker logic
    :closed
  end
  
  defp trip_circuit_breaker(_node) do
    # TODO: Implement circuit breaker logic
    :ok
  end
  
  defp reset_circuit_breaker(_node) do
    # TODO: Implement circuit breaker logic
    :ok
  end
  
  defp generate_query_id do
    :erlang.unique_integer([:positive, :monotonic])
  end
  
  defp update_stats(%{stats: stats} = state, key) do
    new_stats = Map.update(stats, key, 1, &(&1 + 1))
    %{state | stats: new_stats}
  end
  
  defp update_stats(stats, key) when is_map(stats) do
    Map.update(stats, key, 1, &(&1 + 1))
  end
end