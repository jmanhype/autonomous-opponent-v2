defmodule AutonomousOpponentV2Core.Core.SlidingWindowRateLimiter do
  @moduledoc """
  Sliding window rate limiter for more accurate rate limiting.
  
  This implementation uses a sliding window algorithm that provides:
  - More accurate rate limiting than token bucket
  - Better burst prevention
  - Configurable window sizes
  - Support for multiple time windows (e.g., per-second AND per-minute limits)
  
  ## Algorithm
  
  The sliding window algorithm tracks requests in time buckets and calculates
  the request count over a sliding time window. This prevents the "boundary
  problem" of fixed windows where a burst at the window boundary could allow
  2x the limit.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  
  @default_cleanup_interval :timer.minutes(5)
  @max_window_size :timer.hours(1)
  
  # Client API
  
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Check if a request is allowed and track it if so.
  
  Options:
    - identifier: The client/IP/key to track (default: :global)
    - cost: The cost of this request (default: 1)
  """
  def check_and_track(server, identifier \\ :global, cost \\ 1) do
    GenServer.call(server, {:check_and_track, identifier, cost})
  end
  
  @doc """
  Get current usage for an identifier
  """
  def get_usage(server, identifier \\ :global) do
    GenServer.call(server, {:get_usage, identifier})
  end
  
  @doc """
  Add a new rate limit rule
  """
  def add_rule(server, rule_name, window_ms, max_requests) do
    GenServer.call(server, {:add_rule, rule_name, window_ms, max_requests})
  end
  
  @doc """
  Get rate limit headers for HTTP responses
  """
  def get_rate_limit_headers(server, identifier \\ :global) do
    GenServer.call(server, {:get_headers, identifier})
  end
  
  # Server Implementation
  
  defstruct [
    :name,
    :rules,
    :request_log,
    :cleanup_timer,
    :distributed_adapter
  ]
  
  @impl true
  def init(opts) do
    # Initialize ETS table for request tracking
    table_name = :"#{opts[:name]}_requests"
    :ets.new(table_name, [:named_table, :public, :ordered_set, {:write_concurrency, true}])
    
    # Default rules
    default_rules = opts[:rules] || %{
      per_second: {1_000, 10},        # 10 requests per second
      per_minute: {60_000, 100},      # 100 requests per minute  
      per_hour: {3_600_000, 1000}     # 1000 requests per hour
    }
    
    state = %__MODULE__{
      name: opts[:name],
      rules: default_rules,
      request_log: table_name,
      distributed_adapter: opts[:distributed_adapter]
    }
    
    # Schedule periodic cleanup
    {:ok, schedule_cleanup(state)}
  end
  
  @impl true
  def handle_call({:check_and_track, identifier, cost}, _from, state) do
    now = System.monotonic_time(:millisecond)
    
    # Check all rules
    results = Enum.map(state.rules, fn {rule_name, {window_ms, max_requests}} ->
      requests_in_window = count_requests_in_window(state.request_log, identifier, now, window_ms)
      
      if requests_in_window + cost <= max_requests do
        {:ok, rule_name, requests_in_window + cost, max_requests}
      else
        {:error, rule_name, requests_in_window, max_requests}
      end
    end)
    
    # If all rules pass, track the request
    if Enum.all?(results, &match?({:ok, _, _, _}, &1)) do
      track_request(state.request_log, identifier, now, cost)
      
      # Publish success event
      EventBus.publish(:rate_limit_allowed, %{
        limiter: state.name,
        identifier: identifier,
        cost: cost,
        timestamp: now
      })
      
      {:reply, {:ok, build_usage_info(results)}, state}
    else
      # Find the most restrictive rule that failed
      failed_rule = Enum.find(results, &match?({:error, _, _, _}, &1))
      {:error, rule_name, current, max} = failed_rule
      
      # Publish rate limited event
      EventBus.publish(:rate_limited, %{
        limiter: state.name,
        identifier: identifier,
        rule: rule_name,
        current: current,
        max: max,
        timestamp: now
      })
      
      {:reply, {:error, :rate_limited, build_usage_info(results)}, state}
    end
  end
  
  @impl true
  def handle_call({:get_usage, identifier}, _from, state) do
    now = System.monotonic_time(:millisecond)
    
    usage = Enum.map(state.rules, fn {rule_name, {window_ms, max_requests}} ->
      count = count_requests_in_window(state.request_log, identifier, now, window_ms)
      {rule_name, %{current: count, max: max_requests, window_ms: window_ms}}
    end)
    |> Map.new()
    
    {:reply, {:ok, usage}, state}
  end
  
  @impl true
  def handle_call({:add_rule, rule_name, window_ms, max_requests}, _from, state) do
    if window_ms > 0 and window_ms <= @max_window_size and max_requests > 0 do
      new_rules = Map.put(state.rules, rule_name, {window_ms, max_requests})
      {:reply, :ok, %{state | rules: new_rules}}
    else
      {:reply, {:error, :invalid_rule}, state}
    end
  end
  
  @impl true
  def handle_call({:get_headers, identifier}, _from, state) do
    now = System.monotonic_time(:millisecond)
    
    # Use the most restrictive rule for headers
    {rule_name, {window_ms, max_requests}} = 
      Enum.min_by(state.rules, fn {_, {window_ms, max}} -> max / window_ms end)
    
    current = count_requests_in_window(state.request_log, identifier, now, window_ms)
    remaining = max(0, max_requests - current)
    
    # Calculate reset time (end of current window)
    reset_time = div(now + window_ms, window_ms) * window_ms
    reset_timestamp = System.os_time(:second) + div(reset_time - now, 1000)
    
    headers = [
      {"x-ratelimit-limit", Integer.to_string(max_requests)},
      {"x-ratelimit-remaining", Integer.to_string(remaining)},
      {"x-ratelimit-reset", Integer.to_string(reset_timestamp)},
      {"x-ratelimit-window", rule_name |> Atom.to_string()}
    ]
    
    {:reply, {:ok, headers}, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Clean up old entries
    now = System.monotonic_time(:millisecond)
    oldest_window = Enum.map(state.rules, fn {_, {window_ms, _}} -> window_ms end) |> Enum.max()
    cutoff = now - oldest_window - :timer.minutes(1)
    
    # Delete old entries
    :ets.foldl(
      fn
        {{_identifier, timestamp}, _cost} = entry, acc when timestamp < cutoff ->
          :ets.delete_object(state.request_log, entry)
          acc + 1
        _, acc ->
          acc
      end,
      0,
      state.request_log
    )
    
    {:noreply, schedule_cleanup(state)}
  end
  
  # Private Functions
  
  defp count_requests_in_window(table, identifier, now, window_ms) do
    cutoff = now - window_ms
    
    # Count requests within the window
    # We need to match all entries for this identifier where timestamp > cutoff
    :ets.foldl(
      fn
        {{^identifier, timestamp}, cost}, acc when timestamp > cutoff ->
          acc + cost
        _, acc ->
          acc
      end,
      0,
      table
    )
  end
  
  defp track_request(table, identifier, timestamp, cost) do
    # Use timestamp as part of the key to handle multiple requests at same time
    key = {identifier, timestamp}
    
    # Try to update existing entry or insert new one
    case :ets.lookup(table, key) do
      [] ->
        :ets.insert(table, {key, cost})
      [{^key, existing_cost}] ->
        :ets.insert(table, {key, existing_cost + cost})
    end
  end
  
  defp build_usage_info(results) do
    Enum.map(results, fn
      {:ok, rule_name, current, max} ->
        {rule_name, %{current: current, max: max, remaining: max - current}}
      {:error, rule_name, current, max} ->
        {rule_name, %{current: current, max: max, remaining: 0}}
    end)
    |> Map.new()
  end
  
  defp schedule_cleanup(state) do
    timer = Process.send_after(self(), :cleanup, @default_cleanup_interval)
    %{state | cleanup_timer: timer}
  end
end