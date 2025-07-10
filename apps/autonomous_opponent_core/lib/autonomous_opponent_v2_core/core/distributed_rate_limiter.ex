defmodule AutonomousOpponentV2Core.Core.DistributedRateLimiter do
  @moduledoc """
  Distributed rate limiter using Redis for cluster-wide rate limiting.
  
  This allows rate limiting across multiple nodes in a cluster, ensuring
  consistent rate limits even when the application is scaled horizontally.
  
  Features:
  - Redis-based distributed storage with connection pooling
  - Lua scripts for atomic operations
  - Circuit breaker protection
  - Graceful fallback to local rate limiting
  - VSM integration with algedonic signals
  - Comprehensive telemetry and audit logging
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Core.{CircuitBreaker, RateLimiter}
  alias AutonomousOpponentV2Core.Connections.RedisPool
  
  @lua_script_check_and_increment """
  local key = KEYS[1]
  local window = tonumber(ARGV[1])
  local max_requests = tonumber(ARGV[2])
  local now = tonumber(ARGV[3])
  local cost = tonumber(ARGV[4])
  
  -- Clean old entries
  redis.call('ZREMRANGEBYSCORE', key, '-inf', now - window)
  
  -- Count current requests
  local current = redis.call('ZCARD', key)
  
  if current + cost <= max_requests then
    -- Add the new request
    redis.call('ZADD', key, now, now .. ':' .. math.random())
    redis.call('EXPIRE', key, window / 1000)
    return {1, current + cost, max_requests}
  else
    return {0, current, max_requests}
  end
  """
  
  @lua_script_batch_usage """
  local results = {}
  local window = tonumber(ARGV[1])
  local now = tonumber(ARGV[2])
  
  for i = 1, #KEYS do
    local key = KEYS[i]
    -- Clean old entries
    redis.call('ZREMRANGEBYSCORE', key, '-inf', now - window)
    -- Count current
    local count = redis.call('ZCARD', key)
    table.insert(results, count)
  end
  
  return results
  """
  
  @fallback_table :distributed_rate_limiter_fallback
  @sync_interval 5_000
  @max_identifier_length 100
  @max_key_length 250
  
  # Client API
  
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Check if request is allowed and track it atomically
  """
  def check_and_track(server, identifier, rule_name, cost \\ 1) do
    GenServer.call(server, {:check_and_track, identifier, rule_name, cost})
  end
  
  @doc """
  Get current usage across the cluster
  """
  def get_usage(server, identifier, rule_name) do
    GenServer.call(server, {:get_usage, identifier, rule_name})
  end
  
  @doc """
  Get usage for multiple identifiers in batch
  """
  def get_usage_batch(server, identifiers, rule_name) do
    GenServer.call(server, {:get_usage_batch, identifiers, rule_name})
  end
  
  @doc """
  Clear all rate limit data for an identifier
  """
  def clear(server, identifier) do
    GenServer.call(server, {:clear, identifier})
  end
  
  @doc """
  Health check for Redis connection
  """
  def health_check(server) do
    GenServer.call(server, :health_check)
  end
  
  # Server Implementation
  
  defstruct [
    :name,
    :rules,
    :lua_sha_check,
    :lua_sha_batch,
    :node_id,
    :redis_enabled,
    :fallback_mode,
    :sync_timer,
    :stats
  ]
  
  @impl true
  def init(opts) do
    # Generate unique node ID
    node_id = "#{node()}_#{System.unique_integer([:positive])}"
    
    # Ensure fallback table exists
    ensure_fallback_table()
    
    # Check if Redis is enabled
    redis_enabled = redis_enabled?()
    
    state = %__MODULE__{
      name: opts[:name],
      rules: opts[:rules] || default_rules(),
      lua_sha_check: nil,
      lua_sha_batch: nil,
      node_id: node_id,
      redis_enabled: redis_enabled,
      fallback_mode: opts[:fallback_mode] || :local,
      stats: %{
        redis_calls: 0,
        fallback_calls: 0,
        circuit_opens: 0
      }
    }
    
    # Load Lua scripts if Redis is enabled
    state = if redis_enabled do
      load_lua_scripts(state)
    else
      Logger.warning("Distributed rate limiter #{opts[:name]} starting in local mode (Redis disabled)")
      state
    end
    
    # Start sync timer for stats
    {:ok, timer} = :timer.send_interval(@sync_interval, :sync_stats)
    
    # Subscribe to relevant events
    EventBus.subscribe(:redis_circuit_open)
    EventBus.subscribe(:redis_circuit_closed)
    
    {:ok, %{state | sync_timer: timer}}
  end
  
  @impl true
  def handle_call({:check_and_track, identifier, rule_name, cost}, from, state) do
    # Validate inputs
    identifier = sanitize_identifier(identifier)
    
    case Map.get(state.rules, rule_name) do
      {window_ms, max_requests} ->
        # Determine execution mode
        if state.redis_enabled and not circuit_open?() do
          # Redis mode
          handle_redis_check_and_track(identifier, rule_name, window_ms, max_requests, cost, from, state)
        else
          # Fallback mode
          handle_fallback_check_and_track(identifier, rule_name, window_ms, max_requests, cost, from, state)
        end
        
      nil ->
        {:reply, {:error, :unknown_rule}, state}
    end
  end
  
  @impl true
  def handle_call({:get_usage, identifier, rule_name}, _from, state) do
    identifier = sanitize_identifier(identifier)
    
    case Map.get(state.rules, rule_name) do
      {window_ms, max_requests} ->
        usage = if state.redis_enabled and not circuit_open?() do
          get_redis_usage(identifier, rule_name, window_ms, max_requests, state)
        else
          get_fallback_usage(identifier, rule_name, window_ms, max_requests)
        end
        
        {:reply, usage, state}
        
      nil ->
        {:reply, {:error, :unknown_rule}, state}
    end
  end
  
  @impl true
  def handle_call({:get_usage_batch, identifiers, rule_name}, _from, state) do
    case Map.get(state.rules, rule_name) do
      {window_ms, max_requests} ->
        usages = if state.redis_enabled and not circuit_open?() do
          get_redis_usage_batch(identifiers, rule_name, window_ms, max_requests, state)
        else
          # Fallback to individual queries
          Enum.map(identifiers, fn id ->
            {id, get_fallback_usage(id, rule_name, window_ms, max_requests)}
          end)
          |> Map.new()
        end
        
        {:reply, {:ok, usages}, state}
        
      nil ->
        {:reply, {:error, :unknown_rule}, state}
    end
  end
  
  @impl true
  def handle_call({:clear, identifier}, _from, state) do
    identifier = sanitize_identifier(identifier)
    
    # Clear from Redis if available
    redis_result = if state.redis_enabled and not circuit_open?() do
      Enum.map(state.rules, fn {rule_name, _} ->
        key = build_redis_key(identifier, rule_name)
        RedisPool.command(["DEL", key])
      end)
    else
      []
    end
    
    # Clear from fallback
    clear_fallback(identifier)
    
    {:reply, {:ok, length(redis_result)}, state}
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    health = if state.redis_enabled do
      case RedisPool.health_check() do
        :ok -> :healthy
        {:error, reason} -> {:unhealthy, reason}
      end
    else
      {:disabled, :redis_not_enabled}
    end
    
    {:reply, health, state}
  end
  
  @impl true
  def handle_info(:sync_stats, state) do
    # Emit telemetry
    :telemetry.execute(
      [:distributed_rate_limiter, :stats],
      Map.put(state.stats, :mode, if(state.redis_enabled, do: :redis, else: :fallback)),
      %{name: state.name, node: state.node_id}
    )
    
    # Reset stats
    {:noreply, %{state | stats: %{redis_calls: 0, fallback_calls: 0, circuit_opens: 0}}}
  end
  
  @impl true
  def handle_info({:event_bus, %{type: :redis_circuit_open}}, state) do
    Logger.warning("Redis circuit opened, switching to fallback mode")
    state = update_in(state.stats.circuit_opens, &(&1 + 1))
    
    # Emit algedonic pain signal
    EventBus.publish(:algedonic_pain, %{
      source: :distributed_rate_limiter,
      name: state.name,
      severity: :high,
      reason: :redis_circuit_open,
      timestamp: DateTime.utc_now(),
      impact: :degraded_to_local_limiting
    })
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event_bus, %{type: :redis_circuit_closed}}, state) do
    Logger.info("Redis circuit closed, resuming distributed mode")
    
    # Reload Lua scripts
    state = load_lua_scripts(state)
    
    # Emit algedonic pleasure signal
    EventBus.publish(:algedonic_pleasure, %{
      source: :distributed_rate_limiter,
      name: state.name,
      reason: :redis_recovered,
      timestamp: DateTime.utc_now(),
      improvement: :distributed_limiting_restored
    })
    
    {:noreply, state}
  end
  
  # Private Redis functions
  
  defp handle_redis_check_and_track(identifier, rule_name, window_ms, max_requests, cost, _from, state) do
    key = build_redis_key(identifier, rule_name)
    now = System.system_time(:millisecond)
    
    result = if state.lua_sha_check do
      # Use cached script
      RedisPool.evalsha(state.lua_sha_check, [key], [window_ms, max_requests, now, cost])
    else
      # Fallback to EVAL
      RedisPool.eval_script(@lua_script_check_and_increment, [key], [window_ms, max_requests, now, cost])
    end
    
    response = case result do
      {:ok, [1, current, max]} ->
        usage = %{current: current, max: max, remaining: max - current}
        publish_allowed_event(state, identifier, rule_name, usage)
        {:ok, usage}
        
      {:ok, [0, current, max]} ->
        usage = %{current: current, max: max, remaining: 0}
        publish_limited_event(state, identifier, rule_name, usage)
        audit_rate_limit_violation(identifier, rule_name, %{usage: usage})
        {:error, :rate_limited, usage}
        
      {:error, %Redix.Error{message: "NOSCRIPT" <> _}} ->
        # Script was evicted, reload it
        new_state = load_lua_scripts(state)
        {:reply, {:error, :script_reloading}, new_state}
        
      {:error, reason} ->
        Logger.error("Redis error in rate limiter: #{inspect(reason)}")
        # Fallback to local
        handle_fallback_check_and_track(identifier, rule_name, window_ms, max_requests, cost, nil, state)
    end
    
    state = update_in(state.stats.redis_calls, &(&1 + 1))
    {:reply, response, state}
  end
  
  defp handle_fallback_check_and_track(identifier, rule_name, window_ms, max_requests, cost, _from, state) do
    # Use local ETS-based rate limiting
    key = {identifier, rule_name}
    now = System.system_time(:millisecond)
    cutoff = now - window_ms
    
    # Atomic ETS operation
    result = :ets.lookup(@fallback_table, key)
    entries = case result do
      [{^key, entries}] -> entries
      [] -> []
    end
    
    # Filter old entries
    valid_entries = Enum.filter(entries, fn {timestamp, _cost} -> timestamp > cutoff end)
    current_cost = Enum.reduce(valid_entries, 0, fn {_ts, c}, acc -> acc + c end)
    
    response = if current_cost + cost <= max_requests do
      # Add new entry
      new_entries = [{now, cost} | valid_entries]
      :ets.insert(@fallback_table, {key, new_entries})
      
      usage = %{current: current_cost + cost, max: max_requests, remaining: max_requests - current_cost - cost}
      publish_allowed_event(state, identifier, rule_name, Map.put(usage, :fallback, true))
      {:ok, usage}
    else
      usage = %{current: current_cost, max: max_requests, remaining: 0}
      publish_limited_event(state, identifier, rule_name, Map.put(usage, :fallback, true))
      audit_rate_limit_violation(identifier, rule_name, %{usage: usage, fallback: true})
      {:error, :rate_limited, usage}
    end
    
    state = update_in(state.stats.fallback_calls, &(&1 + 1))
    {:reply, response, state}
  end
  
  defp get_redis_usage(identifier, rule_name, window_ms, max_requests, _state) do
    key = build_redis_key(identifier, rule_name)
    now = System.system_time(:millisecond)
    cutoff = now - window_ms
    
    with {:ok, _} <- RedisPool.command(["ZREMRANGEBYSCORE", key, "-inf", cutoff]),
         {:ok, count} <- RedisPool.command(["ZCARD", key]) do
      {:ok, %{current: count, max: max_requests, remaining: max_requests - count}}
    else
      error ->
        Logger.error("Failed to get Redis usage: #{inspect(error)}")
        {:error, :redis_error}
    end
  end
  
  defp get_redis_usage_batch(identifiers, rule_name, window_ms, max_requests, state) do
    now = System.system_time(:millisecond)
    keys = Enum.map(identifiers, &build_redis_key(&1, rule_name))
    
    result = if state.lua_sha_batch do
      RedisPool.evalsha(state.lua_sha_batch, keys, [window_ms, now])
    else
      RedisPool.eval_script(@lua_script_batch_usage, keys, [window_ms, now])
    end
    
    case result do
      {:ok, counts} ->
        Enum.zip(identifiers, counts)
        |> Enum.map(fn {id, count} ->
          {id, %{current: count, max: max_requests, remaining: max_requests - count}}
        end)
        |> Map.new()
        
      error ->
        Logger.error("Failed to get batch usage: #{inspect(error)}")
        %{}
    end
  end
  
  defp get_fallback_usage(identifier, rule_name, window_ms, max_requests) do
    key = {identifier, rule_name}
    now = System.system_time(:millisecond)
    cutoff = now - window_ms
    
    case :ets.lookup(@fallback_table, key) do
      [{^key, entries}] ->
        valid_entries = Enum.filter(entries, fn {timestamp, _cost} -> timestamp > cutoff end)
        current = Enum.reduce(valid_entries, 0, fn {_ts, cost}, acc -> acc + cost end)
        {:ok, %{current: current, max: max_requests, remaining: max_requests - current}}
        
      [] ->
        {:ok, %{current: 0, max: max_requests, remaining: max_requests}}
    end
  end
  
  defp clear_fallback(identifier) do
    # Clear all rules for this identifier
    :ets.match_delete(@fallback_table, {{identifier, :_}, :_})
  end
  
  # Helper functions
  
  defp load_lua_scripts(state) do
    check_sha = case RedisPool.load_script(@lua_script_check_and_increment) do
      {:ok, sha} -> sha
      _ -> nil
    end
    
    batch_sha = case RedisPool.load_script(@lua_script_batch_usage) do
      {:ok, sha} -> sha
      _ -> nil
    end
    
    %{state | lua_sha_check: check_sha, lua_sha_batch: batch_sha}
  end
  
  defp build_redis_key(identifier, rule_name) do
    safe_id = sanitize_identifier(identifier)
    safe_rule = sanitize_rule_name(rule_name)
    
    key = "rate_limit:#{safe_rule}:#{safe_id}"
    
    # Prevent excessively long keys
    if String.length(key) > @max_key_length do
      hash = :crypto.hash(:sha256, identifier)
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)
      
      "rate_limit:#{safe_rule}:#{hash}"
    else
      key
    end
  end
  
  defp sanitize_identifier(identifier) do
    identifier
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9:_.-]/, "")
    |> String.slice(0, @max_identifier_length)
  end
  
  defp sanitize_rule_name(rule_name) do
    rule_name
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "")
  end
  
  defp ensure_fallback_table do
    case :ets.whereis(@fallback_table) do
      :undefined ->
        :ets.new(@fallback_table, [:set, :public, :named_table, {:write_concurrency, true}])
      _ ->
        :ok
    end
  end
  
  defp redis_enabled? do
    Application.get_env(:autonomous_opponent_core, :distributed_rate_limiting_enabled, true) and
    Application.get_env(:autonomous_opponent_core, :redis_enabled, true)
  end
  
  defp circuit_open? do
    case Process.whereis(:redis_circuit) do
      nil -> false  # Circuit doesn't exist, treat as closed
      _pid ->
        case CircuitBreaker.get_state(:redis_circuit) do
          {:ok, %{state: :open}} -> true
          _ -> false
        end
    end
  end
  
  defp publish_allowed_event(state, identifier, rule_name, usage) do
    EventBus.publish(:distributed_rate_limit_allowed, %{
      node: state.node_id,
      identifier: identifier,
      rule: rule_name,
      usage: usage,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp publish_limited_event(state, identifier, rule_name, usage) do
    EventBus.publish(:distributed_rate_limited, %{
      node: state.node_id,
      identifier: identifier,
      rule: rule_name,
      usage: usage,
      timestamp: DateTime.utc_now()
    })
    
    # VSM integration - emit pain signal for rate limiting
    EventBus.publish(:algedonic_pain, %{
      source: :distributed_rate_limiter,
      name: state.name,
      severity: :medium,
      reason: {:rate_limited, identifier},
      metric: usage,
      intensity: calculate_pain_intensity(usage)
    })
  end
  
  defp calculate_pain_intensity(%{current: current, max: max}) do
    # Higher intensity as we approach the limit
    min(1.0, current / max * 1.2)
  end
  
  defp audit_rate_limit_violation(identifier, rule, context) do
    # Hash identifier for GDPR compliance
    hashed_id = :crypto.hash(:sha256, identifier)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
    
    # Log the rate limit violation
    Logger.warning("Rate limit violation: rule=#{rule}, identifier_hash=#{hashed_id}, context=#{inspect(context)}")
    
    # Publish audit event
    EventBus.publish(:audit_log, %{
      type: :rate_limit_violation,
      identifier_hash: hashed_id,
      rule: rule,
      timestamp: DateTime.utc_now(),
      node: node(),
      context: context
    })
  end
  
  defp default_rules do
    %{
      # VSM subsystem-specific rules
      s1_operations: {1_000, 100},      # S1 gets highest capacity
      s2_coordination: {1_000, 50},     # S2 moderate capacity
      s3_control: {1_000, 20},          # S3 lower capacity
      s4_intelligence: {60_000, 100},   # S4 longer window
      s5_policy: {300_000, 50},         # S5 very long window
      
      # General API rules
      per_second: {1_000, 10},
      per_minute: {60_000, 100},
      per_hour: {3_600_000, 1000}
    }
  end
end