defmodule AutonomousOpponent.Core.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for variety flow control in VSM subsystems.
  Implements per-client and global rate limiting with burst handling.

  The rate limiter uses a token bucket algorithm where:
  - Tokens are consumed when requests are made
  - Tokens are refilled at a constant rate
  - Burst capacity allows temporary spikes
  - Graceful degradation when limits are exceeded

  Integrates with VSM S1-S5 subsystems for variety flow management.

  ## Wisdom Preservation

  ### Why Token Bucket Algorithm
  The token bucket provides flexibility that pure rate limiting lacks. It allows
  bursts while maintaining long-term rate limits - like a dam that can handle
  flash floods without breaking. This matches real-world traffic patterns where
  requests come in bursts, not steady streams.

  ### Design Decisions & Rationale

  1. **Token Bucket over Sliding Window**: Token buckets handle bursts naturally.
     Sliding windows are more precise but less forgiving. In VSM, variety demands
     flexibility - rigid precision kills adaptation.

  2. **ETS for Token Storage**: Tokens must be accessed FAST and concurrently.
     ETS provides sub-microsecond lookups with concurrent access. GenServer state
     would bottleneck under load.

  3. **Per-Client AND Global Limits**: Defense in depth. Per-client prevents one
     bad actor from consuming all resources. Global limits protect the system as
     a whole. It's individual responsibility within collective boundaries.

  4. **Automatic Refill via Timer**: Tokens refill continuously, not on-demand.
     This prevents refill computation from adding latency to the hot path. The
     system breathes naturally, inhaling tokens at a steady rate.

  5. **VSM Integration**: Each subsystem (S1-S5) gets its own variety flow metrics.
     This allows the system to throttle different types of variety independently.
     S1 operational variety differs from S5 policy variety - they need different
     flow rates.
  """
  use GenServer
  require Logger

  alias AutonomousOpponentV2.EventBus

  # Client API

  @doc """
  Starts a rate limiter with the given options.

  Options:
    - name: The registered name for the rate limiter
    - bucket_size: Maximum tokens in bucket (default: 100)
    - refill_rate: Tokens added per second (default: 10)
    - refill_interval_ms: How often to add tokens (default: 100ms)
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Attempt to consume tokens for a request.
  Returns {:ok, tokens_remaining} or {:error, :rate_limited}
  """
  def consume(name, tokens \\ 1) when is_integer(tokens) and tokens > 0 do
    GenServer.call(name, {:consume, tokens, :global})
  end

  @doc """
  Attempt to consume tokens for a specific client.
  Returns {:ok, tokens_remaining} or {:error, :rate_limited}
  """
  def consume_for_client(name, client_id, tokens \\ 1)
      when is_integer(tokens) and tokens > 0 do
    GenServer.call(name, {:consume, tokens, {:client, client_id}})
  end

  @doc """
  Attempt to consume tokens for a VSM subsystem.
  Subsystem should be one of: :s1, :s2, :s3, :s4, :s5
  """
  def consume_for_subsystem(name, subsystem, tokens \\ 1)
      when subsystem in [:s1, :s2, :s3, :s4, :s5] and is_integer(tokens) and tokens > 0 do
    GenServer.call(name, {:consume, tokens, {:subsystem, subsystem}})
  end

  @doc """
  Get current rate limiter state and metrics
  """
  def get_state(name) do
    GenServer.call(name, :get_state)
  end

  @doc """
  Get variety flow metrics for VSM subsystems
  """
  def get_variety_metrics(name) do
    GenServer.call(name, :get_variety_metrics)
  end

  @doc """
  Reset rate limiter buckets
  """
  def reset(name) do
    GenServer.call(name, :reset)
  end

  # Server callbacks

  defstruct [
    :name,
    :bucket_size,
    :refill_rate,
    :refill_interval_ms,
    :tokens_per_interval,
    :token_table,
    :metrics_table,
    :refill_timer
  ]

  @impl true
  def init(opts) do
    # Create ETS tables for tokens and metrics
    token_table = :"#{opts[:name]}_tokens"
    metrics_table = :"#{opts[:name]}_metrics"

    :ets.new(token_table, [:named_table, :public, :set, {:write_concurrency, true}])
    :ets.new(metrics_table, [:named_table, :public, :set, {:write_concurrency, true}])

    # Initialize configuration
    bucket_size = opts[:bucket_size] || 100
    refill_rate = opts[:refill_rate] || 10
    refill_interval_ms = opts[:refill_interval_ms] || 100

    # Calculate tokens to add per interval
    tokens_per_interval = refill_rate * refill_interval_ms / 1000.0

    # Initialize global bucket
    :ets.insert(token_table, {:global, bucket_size})

    # Initialize VSM subsystem buckets with different sizes based on variety needs
    # S1 (Operations) needs high throughput
    :ets.insert(token_table, {{:subsystem, :s1}, bucket_size * 2})
    # S2 (Coordination) moderate throughput
    :ets.insert(token_table, {{:subsystem, :s2}, bucket_size})
    # S3 (Control) moderate throughput
    :ets.insert(token_table, {{:subsystem, :s3}, bucket_size})
    # S4 (Intelligence) can be slower, more deliberate
    :ets.insert(token_table, {{:subsystem, :s4}, div(bucket_size, 2)})
    # S5 (Policy) slowest, most deliberate
    :ets.insert(token_table, {{:subsystem, :s5}, div(bucket_size, 4)})

    # Initialize metrics
    :ets.insert(metrics_table, {:total_requests, 0})
    :ets.insert(metrics_table, {:total_allowed, 0})
    :ets.insert(metrics_table, {:total_limited, 0})
    :ets.insert(metrics_table, {:variety_flow, %{s1: 0, s2: 0, s3: 0, s4: 0, s5: 0}})

    state = %__MODULE__{
      name: opts[:name],
      bucket_size: bucket_size,
      refill_rate: refill_rate,
      refill_interval_ms: refill_interval_ms,
      tokens_per_interval: tokens_per_interval,
      token_table: token_table,
      metrics_table: metrics_table
    }

    # Start refill timer
    timer_ref = Process.send_after(self(), :refill, refill_interval_ms)
    state = %{state | refill_timer: timer_ref}

    # Publish initialization event
    EventBus.publish(:rate_limiter_initialized, %{
      name: state.name,
      config: %{
        bucket_size: state.bucket_size,
        refill_rate: state.refill_rate,
        refill_interval_ms: state.refill_interval_ms
      }
    })

    {:ok, state}
  end

  @impl true
  def handle_call({:consume, tokens, scope}, _from, state) do
    # Update request metrics
    :ets.update_counter(state.metrics_table, :total_requests, 1)

    # Determine bucket key and max size
    {bucket_key, max_size} = get_bucket_info(scope, state)

    # Attempt to consume tokens atomically
    case consume_tokens(state.token_table, bucket_key, tokens, max_size) do
      {:ok, remaining} ->
        # Success - tokens consumed
        :ets.update_counter(state.metrics_table, :total_allowed, 1)
        update_variety_metrics(state, scope, :allowed)

        # Publish success event for normal requests
        if tokens == 1 do
          EventBus.publish(:rate_limit_allowed, %{
            name: state.name,
            scope: scope,
            tokens_remaining: remaining
          })
        end

        {:reply, {:ok, remaining}, state}

      {:error, :insufficient_tokens} ->
        # Rate limited - not enough tokens
        :ets.update_counter(state.metrics_table, :total_limited, 1)
        update_variety_metrics(state, scope, :limited)

        # WISDOM: Rate limiting as algedonic pain
        # When we limit requests, it's a pain signal. The system is telling us
        # it's overwhelmed. This pain should propagate to trigger adaptation.
        EventBus.publish(:algedonic_pain, %{
          source: :rate_limiter,
          name: state.name,
          severity: :medium,
          reason: {:rate_limited, scope},
          requested_tokens: tokens,
          timestamp: System.monotonic_time(:millisecond)
        })

        {:reply, {:error, :rate_limited}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    # Gather current token counts
    global_tokens = get_token_count(state.token_table, :global)

    subsystem_tokens =
      Enum.map([:s1, :s2, :s3, :s4, :s5], fn subsystem ->
        {subsystem, get_token_count(state.token_table, {:subsystem, subsystem})}
      end)
      |> Map.new()

    # Get metrics
    metrics = %{
      total_requests: :ets.lookup_element(state.metrics_table, :total_requests, 2),
      total_allowed: :ets.lookup_element(state.metrics_table, :total_allowed, 2),
      total_limited: :ets.lookup_element(state.metrics_table, :total_limited, 2)
    }

    reply = %{
      global_tokens: global_tokens,
      subsystem_tokens: subsystem_tokens,
      bucket_size: state.bucket_size,
      refill_rate: state.refill_rate,
      metrics: metrics
    }

    {:reply, reply, state}
  end

  def handle_call(:get_variety_metrics, _from, state) do
    variety_flow = :ets.lookup_element(state.metrics_table, :variety_flow, 2)
    {:reply, variety_flow, state}
  end

  def handle_call(:reset, _from, state) do
    # Reset all buckets to full
    :ets.insert(state.token_table, {:global, state.bucket_size})

    # Reset VSM subsystem buckets
    :ets.insert(state.token_table, {{:subsystem, :s1}, state.bucket_size * 2})
    :ets.insert(state.token_table, {{:subsystem, :s2}, state.bucket_size})
    :ets.insert(state.token_table, {{:subsystem, :s3}, state.bucket_size})
    :ets.insert(state.token_table, {{:subsystem, :s4}, div(state.bucket_size, 2)})
    :ets.insert(state.token_table, {{:subsystem, :s5}, div(state.bucket_size, 4)})

    # Clear client buckets
    :ets.match_delete(state.token_table, {{:client, :_}, :_})

    # Publish reset event
    EventBus.publish(:rate_limiter_reset, %{name: state.name})

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:refill, state) do
    refill_all_buckets(state)

    # Schedule next refill
    timer_ref = Process.send_after(self(), :refill, state.refill_interval_ms)
    {:noreply, %{state | refill_timer: timer_ref}}
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel refill timer
    if state.refill_timer do
      Process.cancel_timer(state.refill_timer)
    end

    :ok
  end

  # Private functions

  # WISDOM: Bucket info mapping - organizing variety flows
  # Different scopes have different bucket sizes because variety isn't uniform.
  # Global scope protects the whole system. Client scope prevents one actor from
  # monopolizing resources. Subsystem scope recognizes that S1 operational variety
  # differs fundamentally from S5 policy variety.
  defp get_bucket_info(scope, state) do
    case scope do
      :global ->
        {:global, state.bucket_size}

      {:client, client_id} ->
        # Clients get 1/10th of global bucket by default
        {{:client, client_id}, div(state.bucket_size, 10)}

      {:subsystem, :s1} ->
        {{:subsystem, :s1}, state.bucket_size * 2}

      {:subsystem, :s2} ->
        {{:subsystem, :s2}, state.bucket_size}

      {:subsystem, :s3} ->
        {{:subsystem, :s3}, state.bucket_size}

      {:subsystem, :s4} ->
        {{:subsystem, :s4}, div(state.bucket_size, 2)}

      {:subsystem, :s5} ->
        {{:subsystem, :s5}, div(state.bucket_size, 4)}
    end
  end

  # WISDOM: Atomic token consumption - the critical section
  # This function is the heart of rate limiting. It must be atomic to prevent
  # race conditions. Two requests arriving simultaneously must not both succeed
  # if only one token remains. ETS atomic operations ensure this without locks.
  defp consume_tokens(table, key, tokens, max_size) do
    # Initialize bucket if it doesn't exist (lazy initialization for clients)
    case :ets.lookup(table, key) do
      [] ->
        # New bucket starts full
        :ets.insert(table, {key, max_size})
        consume_tokens(table, key, tokens, max_size)

      [{^key, current}] when current >= tokens ->
        # Sufficient tokens - consume them atomically
        new_count = :ets.update_counter(table, key, -tokens)
        {:ok, new_count}

      [{^key, _current}] ->
        # Insufficient tokens
        {:error, :insufficient_tokens}
    end
  end

  defp refill_bucket(table, key, tokens_to_add, max_tokens) do
    case :ets.lookup(table, key) do
      [] ->
        # Bucket doesn't exist, skip
        :ok

      [{^key, current}] ->
        # Add tokens but don't exceed max
        new_count = min(current + tokens_to_add, max_tokens)
        :ets.insert(table, {key, new_count})
    end
  end

  # WISDOM: Client bucket refilling - fairness in regeneration
  # All clients get refilled equally, preventing starvation. A client that
  # consumed all tokens gets the same refill as one that consumed none.
  # This encourages steady usage over burst-and-wait patterns.
  defp refill_client_buckets(state) do
    client_buckets = :ets.match(state.token_table, {{:client, :"$1"}, :"$2"})

    Enum.each(client_buckets, fn [client_id, _current_tokens] ->
      # All clients get 1/10th of the global refill rate
      client_refill = state.tokens_per_interval / 10.0
      client_max = div(state.bucket_size, 10)

      refill_bucket(
        state.token_table,
        {:client, client_id},
        client_refill,
        client_max
      )
    end)
  end

  defp get_token_count(table, key) do
    case :ets.lookup(table, key) do
      [] -> 0
      [{^key, count}] -> count
    end
  end

  # WISDOM: Variety metrics - measuring the flow of change
  # VSM needs variety to adapt, but too much variety causes chaos. These metrics
  # let us see variety flow through each subsystem. S1 handling high variety?
  # Good - operations need flexibility. S5 handling high variety? Concerning -
  # policy should be stable. The metrics reveal systemic patterns.
  defp update_variety_metrics(state, {:subsystem, subsystem}, result) do
    current_flow = :ets.lookup_element(state.metrics_table, :variety_flow, 2)

    updated_flow =
      Map.update(current_flow, subsystem, 0, fn count ->
        case result do
          :allowed -> count + 1
          :limited -> count
        end
      end)

    :ets.insert(state.metrics_table, {:variety_flow, updated_flow})
  end

  defp update_variety_metrics(_state, _scope, _result), do: :ok

  defp refill_all_buckets(state) do
    # Refill global bucket
    refill_bucket(state.token_table, :global, state.tokens_per_interval, state.bucket_size)

    # Refill VSM subsystem buckets
    refill_vsm_buckets(state)

    # Refill client buckets (if any exist)
    refill_client_buckets(state)
  end

  defp refill_vsm_buckets(state) do
    # S1 gets double refill rate (high variety flow)
    refill_bucket(
      state.token_table,
      {:subsystem, :s1},
      state.tokens_per_interval * 2,
      state.bucket_size * 2
    )

    # S2-S3 get normal refill rate
    for subsystem <- [:s2, :s3] do
      refill_bucket(
        state.token_table,
        {:subsystem, subsystem},
        state.tokens_per_interval,
        state.bucket_size
      )
    end

    # S4 gets half refill rate
    refill_bucket(
      state.token_table,
      {:subsystem, :s4},
      state.tokens_per_interval / 2.0,
      div(state.bucket_size, 2)
    )

    # S5 gets quarter refill rate (most deliberate)
    refill_bucket(
      state.token_table,
      {:subsystem, :s5},
      state.tokens_per_interval / 4.0,
      div(state.bucket_size, 4)
    )
  end
end