defmodule AutonomousOpponentV2Core.Metrics.Cluster.TimeSeriesStore do
  @moduledoc """
  ⏰ DISTRIBUTED TIME-SERIES STORAGE ENGINE
  
  This module provides efficient storage and retrieval of time-series metrics
  data across the cluster. It implements a multi-tier storage strategy:
  
  - Hot tier: ETS for sub-microsecond access to recent data
  - Warm tier: DETS for fast disk-based storage
  - Cold tier: Mnesia for distributed, replicated storage
  
  ## Features
  
  - Automatic data rotation between tiers
  - Configurable retention policies
  - Compression for historical data
  - Parallel query execution
  - Automatic failover and replication
  
  ## VSM Integration
  
  The storage tiers map to VSM time constants:
  - Hot: Operational (S1/S2) - seconds to minutes
  - Warm: Tactical (S3) - hours to days
  - Cold: Strategic (S4/S5) - days to months
  """
  
  use GenServer
  require Logger
  
  @hot_retention :timer.minutes(5)
  @warm_retention :timer.hours(24)
  @cold_retention :timer.days(30)
  @rotation_interval :timer.minutes(1)
  
  defstruct [
    :hot_table,
    :warm_table,
    :cold_table,
    :rotation_timer,
    :stats
  ]
  
  # ========== CLIENT API ==========
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Writes a metric data point to the time-series store
  """
  def write(metric_name, value, tags \\ %{}, timestamp \\ nil) do
    GenServer.cast(__MODULE__, {:write, metric_name, value, tags, timestamp})
  end
  
  @doc """
  Queries time-series data with configurable granularity
  """
  def query(metric_name, start_time, end_time, opts \\ []) do
    GenServer.call(__MODULE__, {:query, metric_name, start_time, end_time, opts})
  end
  
  @doc """
  Gets storage statistics
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Forces rotation of data between tiers
  """
  def rotate_now do
    GenServer.cast(__MODULE__, :rotate_now)
  end
  
  # ========== CALLBACKS ==========
  
  @impl true
  def init(opts) do
    Logger.info("⏰ Initializing Time-Series Store...")
    
    # Initialize storage tiers
    hot_table = init_hot_storage()
    warm_table = init_warm_storage()
    init_cold_storage()
    
    state = %__MODULE__{
      hot_table: hot_table,
      warm_table: warm_table,
      cold_table: :metrics_cold,
      rotation_timer: schedule_rotation(),
      stats: %{
        writes: 0,
        queries: 0,
        rotations: 0,
        compressions: 0
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:write, metric_name, value, tags, timestamp}, state) do
    ts = timestamp || System.os_time(:microsecond)
    
    # Create composite key
    key = {metric_name, tags, ts}
    
    # Always write to hot tier
    :ets.insert(state.hot_table, {key, value})
    
    # Update stats
    new_state = update_stats(state, :writes)
    
    # Emit telemetry
    :telemetry.execute(
      [:metrics, :timeseries, :write],
      %{count: 1},
      %{metric: metric_name, tier: :hot}
    )
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast(:rotate_now, state) do
    new_state = perform_rotation(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call({:query, metric_name, start_time, end_time, opts}, _from, state) do
    # Query all tiers in parallel
    result = parallel_query(metric_name, start_time, end_time, opts, state)
    
    # Update stats
    new_state = update_stats(state, :queries)
    
    {:reply, {:ok, result}, new_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      hot_size: :ets.info(state.hot_table, :size),
      warm_size: get_dets_size(state.warm_table),
      cold_size: get_mnesia_size(state.cold_table)
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info(:rotate_tiers, state) do
    new_state = perform_rotation(state)
    
    # Schedule next rotation
    rotation_timer = schedule_rotation()
    
    {:noreply, %{new_state | rotation_timer: rotation_timer}}
  end
  
  # ========== PRIVATE FUNCTIONS ==========
  
  defp init_hot_storage do
    :ets.new(:metrics_hot_tier, [
      :ordered_set,
      :public,
      :named_table,
      {:write_concurrency, true},
      {:read_concurrency, true},
      {:decentralized_counters, true}
    ])
  end
  
  defp init_warm_storage do
    file = Path.join(
      :code.priv_dir(:autonomous_opponent_core),
      "metrics_warm_tier.dets"
    )
    
    {:ok, table} = :dets.open_file(:metrics_warm_tier, [
      file: String.to_charlist(file),
      type: :set,
      auto_save: :timer.seconds(30),
      estimated_no_objects: 1_000_000
    ])
    
    table
  end
  
  defp init_cold_storage do
    # Ensure Mnesia is running
    ensure_mnesia_started()
    
    # Create table if it doesn't exist
    case :mnesia.create_table(:metrics_cold, [
      attributes: [:key, :value, :node, :timestamp],
      type: :ordered_set,
      disc_copies: [node()],
      index: [:timestamp],
      storage_properties: [
        {ets: [{compressed: true}]},
        {dets: [{auto_save, 60_000}]}
      ]
    ]) do
      {:atomic, :ok} ->
        Logger.info("Created cold storage table")
        
      {:aborted, {:already_exists, :metrics_cold}} ->
        # Add this node to table copies if not already there
        case :mnesia.add_table_copy(:metrics_cold, node(), :disc_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, _, _}} -> :ok
          error -> Logger.error("Failed to add table copy: #{inspect(error)}")
        end
        
      error ->
        Logger.error("Failed to create cold storage: #{inspect(error)}")
    end
  end
  
  defp ensure_mnesia_started do
    case :mnesia.system_info(:is_running) do
      :yes -> :ok
      _ ->
        :mnesia.start()
        :mnesia.wait_for_tables([:schema], 5000)
    end
  end
  
  defp perform_rotation(state) do
    Logger.debug("Performing tier rotation...")
    
    # Rotate hot → warm
    hot_count = rotate_hot_to_warm(state)
    
    # Rotate warm → cold
    warm_count = rotate_warm_to_cold(state)
    
    # Clean up old data
    cold_count = cleanup_cold_tier(state)
    
    Logger.info("Rotated #{hot_count} hot, #{warm_count} warm, cleaned #{cold_count} cold")
    
    update_stats(state, {:rotations, hot_count + warm_count})
  end
  
  defp rotate_hot_to_warm(state) do
    cutoff = System.os_time(:microsecond) - @hot_retention
    
    # Find old entries
    old_entries = :ets.select(state.hot_table, [
      {
        {{{:"$1", :"$2", :"$3"}}, :"$4"},
        [{:<, :"$3", cutoff}],
        [{{{{:"$1", :"$2", :"$3"}}, :"$4"}}]
      }
    ])
    
    # Move to warm tier
    Enum.each(old_entries, fn {key, value} ->
      :dets.insert(state.warm_table, {key, value})
      :ets.delete(state.hot_table, key)
    end)
    
    length(old_entries)
  end
  
  defp rotate_warm_to_cold(state) do
    cutoff = System.os_time(:microsecond) - @warm_retention
    
    # Use dets:foldl to process entries and count rotations
    count = :dets.foldl(
      fn {key, value}, acc ->
        {_metric, _tags, ts} = key
        
        if ts < cutoff do
          # Move to cold storage
          write_to_mnesia(key, value)
          :dets.delete(state.warm_table, key)
          acc + 1
        else
          acc
        end
      end,
      0,
      state.warm_table
    )
    
    count
  end
  
  defp cleanup_cold_tier(_state) do
    cutoff = System.os_time(:microsecond) - @cold_retention
    
    # Delete old entries from Mnesia
    pattern = {:metrics_cold, :"$1", :"$2", :"$3", :"$4"}
    guard = [{:<, :"$4", cutoff}]
    
    case :mnesia.transaction(fn ->
      :mnesia.select(:metrics_cold, [{pattern, guard, [:"$_"]}])
      |> Enum.each(&:mnesia.delete_object/1)
    end) do
      {:atomic, count} -> count
      {:aborted, reason} ->
        Logger.error("Failed to cleanup cold tier: #{inspect(reason)}")
        0
    end
  end
  
  defp write_to_mnesia({metric, tags, ts} = key, value) do
    :mnesia.dirty_write({
      :metrics_cold,
      key,
      value,
      node(),
      ts
    })
  end
  
  defp parallel_query(metric_name, start_time, end_time, opts, state) do
    # Convert times to microseconds
    start_us = to_microseconds(start_time)
    end_us = to_microseconds(end_time)
    
    # Determine which tiers to query based on time range
    current_time = System.os_time(:microsecond)
    
    tasks = []
    
    # Query hot tier if time range overlaps
    tasks = if end_us > current_time - @hot_retention do
      [Task.async(fn -> query_hot(state.hot_table, metric_name, start_us, end_us, opts) end) | tasks]
    else
      tasks
    end
    
    # Query warm tier if time range overlaps
    tasks = if end_us > current_time - @warm_retention and start_us < current_time - @hot_retention do
      [Task.async(fn -> query_warm(state.warm_table, metric_name, start_us, end_us, opts) end) | tasks]
    else
      tasks
    end
    
    # Query cold tier if time range overlaps
    tasks = if start_us < current_time - @warm_retention do
      [Task.async(fn -> query_cold(state.cold_table, metric_name, start_us, end_us, opts) end) | tasks]
    else
      tasks
    end
    
    # Await all queries
    results = Task.yield_many(tasks, 5000)
    |> Enum.flat_map(fn {task, result} ->
      case result do
        {:ok, data} -> data
        nil -> 
          Task.shutdown(task)
          []
        {:exit, _reason} -> []
      end
    end)
    
    # Sort by timestamp and apply downsampling if needed
    results
    |> Enum.sort_by(fn {{_metric, _tags, ts}, _value} -> ts end)
    |> maybe_downsample(opts)
  end
  
  defp query_hot(table, metric_name, start_time, end_time, _opts) do
    :ets.select(table, [
      {
        {{{:"$1", :"$2", :"$3"}}, :"$4"},
        [
          {:==, :"$1", metric_name},
          {:>=, :"$3", start_time},
          {:"=<", :"$3", end_time}
        ],
        [{{{{:"$1", :"$2", :"$3"}}, :"$4"}}]
      }
    ])
  end
  
  defp query_warm(table, metric_name, start_time, end_time, _opts) do
    # DETS doesn't support complex matching, so we need to filter manually
    :dets.foldl(fn {key, value}, acc ->
      {metric, _tags, ts} = key
      
      if metric == metric_name and ts >= start_time and ts <= end_time do
        [{key, value} | acc]
      else
        acc
      end
    end, [], table)
  end
  
  defp query_cold(table, metric_name, start_time, end_time, _opts) do
    # Use Mnesia index on timestamp for efficiency
    case :mnesia.transaction(fn ->
      :mnesia.index_read(table, metric_name, 2)
      |> Enum.filter(fn {_table, key, _value, _node, ts} ->
        {metric, _tags, _} = key
        metric == metric_name and ts >= start_time and ts <= end_time
      end)
      |> Enum.map(fn {_table, key, value, _node, _ts} ->
        {key, value}
      end)
    end) do
      {:atomic, results} -> results
      {:aborted, _reason} -> []
    end
  end
  
  defp maybe_downsample(data, opts) do
    case opts[:downsample] do
      nil -> data
      
      {:avg, points} when length(data) > points ->
        # Downsample to requested number of points
        downsample_average(data, points)
        
      {:max, points} when length(data) > points ->
        # Downsample keeping max values
        downsample_max(data, points)
        
      _ -> data
    end
  end
  
  defp downsample_average(data, target_points) do
    # Guard against edge cases
    cond do
      target_points <= 0 or length(data) == 0 ->
        data
      length(data) <= target_points ->
        data
      true ->
        # Calculate bucket size
        bucket_size = max(1, div(length(data), target_points))
        
        data
        |> Enum.chunk_every(bucket_size)
        |> Enum.map(fn bucket ->
          # Average timestamp and value for each bucket
          {sum_ts, sum_val, count} = Enum.reduce(bucket, {0, 0, 0}, fn
            {{{metric, tags, ts}, value}, {acc_ts, acc_val, acc_count}} ->
              {acc_ts + ts, acc_val + to_number(value), acc_count + 1}
          end)
          
          # Guard against empty buckets
          if count > 0 do
            avg_ts = div(sum_ts, count)
            avg_val = sum_val / count
            
            {{{List.first(bucket) |> elem(0) |> elem(0), 
               List.first(bucket) |> elem(0) |> elem(1), 
               avg_ts}, avg_val}}
          else
            # Return first element if bucket is somehow empty
            List.first(bucket)
          end
        end)
        |> Enum.filter(&(&1 != nil))
    end
  end
  
  defp downsample_max(data, target_points) do
    # Guard against edge cases
    cond do
      target_points <= 0 or length(data) == 0 ->
        data
      length(data) <= target_points ->
        data
      true ->
        bucket_size = max(1, div(length(data), target_points))
        
        data
        |> Enum.chunk_every(bucket_size)
        |> Enum.map(fn bucket ->
          # Find max value in bucket
          Enum.max_by(bucket, fn {_key, value} -> to_number(value) end)
        end)
    end
  end
  
  defp to_microseconds(%DateTime{} = dt), do: DateTime.to_unix(dt, :microsecond)
  defp to_microseconds(ms) when is_integer(ms), do: ms * 1000
  defp to_microseconds(us), do: us
  
  defp to_number(n) when is_number(n), do: n
  defp to_number(_), do: 0
  
  defp update_stats(state, stat) when is_atom(stat) do
    %{state | stats: Map.update(state.stats, stat, 1, &(&1 + 1))}
  end
  
  defp update_stats(state, {stat, count}) do
    %{state | stats: Map.update(state.stats, stat, count, &(&1 + count))}
  end
  
  defp schedule_rotation do
    Process.send_after(self(), :rotate_tiers, @rotation_interval)
  end
  
  defp get_dets_size(table) do
    case :dets.info(table, :size) do
      {:ok, size} -> size
      _ -> 0
    end
  end
  
  defp get_mnesia_size(table) do
    try do
      :mnesia.table_info(table, :size)
    catch
      :exit, _ -> 0
    end
  end
end