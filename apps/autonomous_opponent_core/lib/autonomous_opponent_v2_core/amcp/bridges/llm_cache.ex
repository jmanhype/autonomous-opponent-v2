defmodule AutonomousOpponentV2Core.AMCP.Bridges.LLMCache do
  @moduledoc """
  Production-ready caching system for LLM responses.
  
  Features:
  - ETS-based in-memory storage with TTL support
  - Disk persistence for cache warming
  - Cache statistics and telemetry
  - Configurable size limits and eviction
  - Thread-safe operations
  """

  use GenServer
  require Logger

  @table_name :llm_response_cache
  @stats_table :llm_cache_stats
  @default_ttl :timer.hours(1)
  @default_max_size 1000
  @cache_dir "priv/llm_cache"
  @persistence_file "cache_dump.etf"

  defmodule Entry do
    @moduledoc "Cache entry structure"
    defstruct [:key, :prompt, :response, :metadata, :expires_at, :created_at, :access_count]
  end

  defmodule Stats do
    @moduledoc "Cache statistics"
    defstruct hits: 0, misses: 0, evictions: 0, errors: 0
  end

  # Client API

  @doc """
  Starts the cache GenServer
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a cached response for the given prompt
  """
  def get(prompt, opts \\ []) do
    key = generate_key(prompt, opts)
    GenServer.call(__MODULE__, {:get, key})
  end

  @doc """
  Stores a response in the cache
  """
  def put(prompt, response, opts \\ []) do
    key = generate_key(prompt, opts)
    metadata = Keyword.get(opts, :metadata, %{})
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    
    GenServer.cast(__MODULE__, {:put, key, prompt, response, metadata, ttl})
  end

  @doc """
  Clears the entire cache
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Gets cache statistics
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Warms the cache from disk
  """
  def warm_cache do
    GenServer.call(__MODULE__, :warm_cache)
  end

  @doc """
  Persists the cache to disk
  """
  def persist do
    GenServer.call(__MODULE__, :persist)
  end

  @doc """
  Gets the current cache size
  """
  def size do
    GenServer.call(__MODULE__, :size)
  end

  @doc """
  Prunes expired entries
  """
  def prune_expired do
    GenServer.cast(__MODULE__, :prune_expired)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(@table_name, [:set, :public, :named_table, {:read_concurrency, true}])
    :ets.new(@stats_table, [:set, :public, :named_table])
    :ets.insert(@stats_table, {:stats, %Stats{}})

    # Get configuration from application config
    app_config = Application.get_env(:autonomous_opponent_core, :llm_cache_config, [])
    merged_opts = Keyword.merge(app_config, opts)

    # Ensure cache directory exists
    cache_dir = Path.join(:code.priv_dir(:autonomous_opponent_core), "../../../#{@cache_dir}")
    File.mkdir_p!(cache_dir)

    # Schedule periodic tasks
    schedule_prune()
    
    # Schedule persistence based on config
    persist_interval = Keyword.get(merged_opts, :persist_interval, :timer.minutes(5))
    if persist_interval != :infinity do
      schedule_persist(persist_interval)
    end

    # Warm cache if enabled
    if Keyword.get(merged_opts, :warm_on_start, true) do
      send(self(), :warm_cache)
    end

    state = %{
      max_size: Keyword.get(merged_opts, :max_size, @default_max_size),
      ttl: Keyword.get(merged_opts, :ttl, @default_ttl),
      cache_dir: cache_dir,
      persist_interval: persist_interval
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        if expired?(entry) do
          :ets.delete(@table_name, key)
          increment_stat(:misses)
          emit_telemetry(:miss, %{reason: :expired})
          {:reply, {:miss, :expired}, state}
        else
          # Update access count and timestamp
          updated_entry = %{entry | access_count: entry.access_count + 1}
          :ets.insert(@table_name, {key, updated_entry})
          
          increment_stat(:hits)
          emit_telemetry(:hit, %{key: key, age: age_ms(entry)})
          {:reply, {:hit, entry.response, entry.metadata}, state}
        end
      
      [] ->
        increment_stat(:misses)
        emit_telemetry(:miss, %{reason: :not_found})
        {:reply, {:miss, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    count = :ets.info(@table_name, :size)
    :ets.delete_all_objects(@table_name)
    
    emit_telemetry(:clear, %{entries: count})
    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    [{:stats, stats}] = :ets.lookup(@stats_table, :stats)
    cache_size = :ets.info(@table_name, :size)
    
    detailed_stats = Map.merge(Map.from_struct(stats), %{
      size: cache_size,
      hit_rate: calculate_hit_rate(stats),
      memory_used: :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
    })
    
    {:reply, detailed_stats, state}
  end

  @impl true
  def handle_call(:warm_cache, _from, state) do
    result = load_from_disk(state.cache_dir)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:persist, _from, state) do
    result = save_to_disk(state.cache_dir)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:size, _from, state) do
    {:reply, :ets.info(@table_name, :size), state}
  end

  @impl true
  def handle_cast({:put, key, prompt, response, metadata, ttl}, state) do
    # Check size limit and evict if necessary
    current_size = :ets.info(@table_name, :size)
    if current_size >= state.max_size do
      evict_lru()
    end

    entry = %Entry{
      key: key,
      prompt: prompt,
      response: response,
      metadata: metadata,
      expires_at: DateTime.add(DateTime.utc_now(), ttl, :millisecond),
      created_at: DateTime.utc_now(),
      access_count: 0
    }

    :ets.insert(@table_name, {key, entry})
    emit_telemetry(:put, %{key: key, ttl: ttl})
    
    {:noreply, state}
  end

  @impl true
  def handle_cast(:prune_expired, state) do
    pruned = prune_expired_entries()
    if pruned > 0 do
      emit_telemetry(:prune, %{count: pruned})
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(:prune, state) do
    GenServer.cast(self(), :prune_expired)
    schedule_prune()
    {:noreply, state}
  end

  @impl true
  def handle_info(:persist, state) do
    # Persist cache directly without self-call to avoid deadlock
    save_to_disk(state.cache_dir)
    
    if state.persist_interval != :infinity do
      schedule_persist(state.persist_interval)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(:warm_cache, state) do
    # Warm cache directly without GenServer.call to avoid deadlock
    try do
      warm_cache_from_disk(state)
    rescue
      error ->
        Logger.warning("Failed to warm cache from disk: #{inspect(error)}")
    end
    {:noreply, state}
  end

  # Private Functions

  defp generate_key(prompt, opts) do
    # Include model and other options in the key
    model = Keyword.get(opts, :model, "default")
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)
    
    content = "#{model}:#{temperature}:#{max_tokens}:#{prompt}"
    :crypto.hash(:sha256, content) |> Base.encode16()
  end

  defp expired?(%Entry{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp age_ms(%Entry{created_at: created_at}) do
    DateTime.diff(DateTime.utc_now(), created_at, :millisecond)
  end

  defp increment_stat(stat) do
    # Get current stats, increment the field, and update
    [{:stats, current_stats}] = :ets.lookup(@stats_table, :stats)
    
    updated_stats = case stat do
      :hits -> %{current_stats | hits: current_stats.hits + 1}
      :misses -> %{current_stats | misses: current_stats.misses + 1}
      :evictions -> %{current_stats | evictions: current_stats.evictions + 1}
      :errors -> %{current_stats | errors: current_stats.errors + 1}
    end
    
    :ets.insert(@stats_table, {:stats, updated_stats})
  end

  defp calculate_hit_rate(%Stats{hits: hits, misses: misses}) when hits + misses > 0 do
    Float.round(hits / (hits + misses) * 100, 2)
  end
  defp calculate_hit_rate(_), do: 0.0

  defp evict_lru do
    # Find least recently used entry
    case :ets.tab2list(@table_name) do
      [] -> :ok
      entries ->
        {key, _entry} = 
          entries
          |> Enum.min_by(fn {_k, e} -> {e.access_count, e.created_at} end)
        
        :ets.delete(@table_name, key)
        increment_stat(:evictions)
        emit_telemetry(:evict, %{key: key, reason: :size_limit})
    end
  end

  defp prune_expired_entries do
    now = DateTime.utc_now()
    
    expired_keys = 
      :ets.foldl(
        fn {key, entry}, acc ->
          if DateTime.compare(now, entry.expires_at) == :gt do
            [key | acc]
          else
            acc
          end
        end,
        [],
        @table_name
      )

    Enum.each(expired_keys, &:ets.delete(@table_name, &1))
    length(expired_keys)
  end

  defp save_to_disk(cache_dir) do
    try do
      entries = :ets.tab2list(@table_name)
      file_path = Path.join(cache_dir, @persistence_file)
      
      # Filter out expired entries before saving
      valid_entries = 
        entries
        |> Enum.reject(fn {_key, entry} -> expired?(entry) end)
        |> Enum.map(fn {key, entry} -> {key, Map.from_struct(entry)} end)
      
      binary = :erlang.term_to_binary(valid_entries)
      File.write!(file_path, binary)
      
      Logger.info("Persisted #{length(valid_entries)} cache entries to disk")
      {:ok, length(valid_entries)}
    rescue
      e ->
        Logger.error("Failed to persist cache: #{inspect(e)}")
        {:error, e}
    end
  end

  defp load_from_disk(cache_dir) do
    file_path = Path.join(cache_dir, @persistence_file)
    
    if File.exists?(file_path) do
      try do
        binary = File.read!(file_path)
        entries = :erlang.binary_to_term(binary)
        
        # Load non-expired entries
        loaded_count = 
          entries
          |> Enum.map(fn {key, map} -> 
            entry = struct(Entry, map)
            {key, entry}
          end)
          |> Enum.reject(fn {_key, entry} -> expired?(entry) end)
          |> Enum.each(fn {key, entry} -> :ets.insert(@table_name, {key, entry}) end)
          |> length()
        
        Logger.info("Loaded #{loaded_count} cache entries from disk")
        {:ok, loaded_count}
      rescue
        e ->
          Logger.error("Failed to load cache: #{inspect(e)}")
          {:error, e}
      end
    else
      {:ok, 0}
    end
  end

  defp warm_cache_from_disk(state) do
    case load_from_disk(state.cache_dir) do
      {:ok, count} ->
        Logger.info("Warmed cache with #{count} entries from disk")
        emit_telemetry(:warmed, %{entries_loaded: count})
      {:error, reason} ->
        Logger.warning("Failed to warm cache from disk: #{inspect(reason)}")
    end
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:autonomous_opponent, :llm_cache, event],
      %{count: 1},
      metadata
    )
  end

  defp schedule_prune do
    Process.send_after(self(), :prune, :timer.minutes(1))
  end

  defp schedule_persist(interval \\ :timer.minutes(5)) do
    Process.send_after(self(), :persist, interval)
  end
end