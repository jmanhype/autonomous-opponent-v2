defmodule AutonomousOpponentV2Core.EventBus.Cluster.VarietyManager do
  @moduledoc """
  Variety Manager - Cybernetic Channel Capacity Control
  
  Implements Ashby's Law of Requisite Variety for the distributed EventBus.
  This module manages the variety (information) flow between VSM nodes to prevent
  overload while ensuring critical signals pass through.
  
  ## Cybernetic Principles
  
  1. **Channel Capacity**: Each VSM channel (S1-S5) has limited capacity
  2. **Variety Absorption**: Higher levels absorb variety from lower levels
  3. **Semantic Compression**: Similar events are aggregated to reduce variety
  4. **Algedonic Bypass**: Pain/pleasure signals bypass all constraints
  
  ## Implementation
  
  Uses token bucket algorithm with VSM-specific enhancements:
  - Separate buckets per event class
  - Semantic similarity detection
  - Adaptive rate adjustment based on system health
  - Priority inversion for critical events
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Telemetry
  
  defstruct [
    :quotas,
    :buckets,
    :compression_config,
    :event_cache,
    :stats,
    :pressure_gauges
  ]
  
  @token_refill_interval 100  # ms
  @cache_ttl 5_000  # 5 seconds
  @similarity_threshold 0.8
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Check if an outbound event can be transmitted based on variety constraints.
  Returns :allowed, :throttled, or :compressed
  """
  def check_outbound(server \\ __MODULE__, event_class) do
    GenServer.call(server, {:check_outbound, event_class})
  end
  
  @doc """
  Record an inbound event for variety accounting
  """
  def record_inbound(server \\ __MODULE__, event_class) do
    GenServer.cast(server, {:record_inbound, event_class})
  end
  
  @doc """
  Apply semantic compression to reduce variety
  """
  def compress(server \\ __MODULE__, event, event_class) do
    GenServer.call(server, {:compress, event, event_class})
  end
  
  @doc """
  Get current variety pressure (0.0 to 1.0)
  """
  def pressure(server \\ __MODULE__) do
    GenServer.call(server, :get_pressure)
  end
  
  @doc """
  Get variety flow statistics
  """
  def get_stats(server \\ __MODULE__) do
    GenServer.call(server, :get_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Initialize token buckets for each channel
    quotas = opts[:quotas] || default_quotas()
    
    buckets = Enum.reduce(quotas, %{}, fn {class, quota}, acc ->
      Map.put(acc, class, init_bucket(quota))
    end)
    
    # Initialize compression configuration
    compression_config = opts[:compression] || default_compression_config()
    
    state = %__MODULE__{
      quotas: quotas,
      buckets: buckets,
      compression_config: compression_config,
      event_cache: %{},
      stats: init_stats(),
      pressure_gauges: init_pressure_gauges()
    }
    
    # Schedule token refill
    schedule_token_refill()
    
    # Schedule cache cleanup
    schedule_cache_cleanup()
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:check_outbound, event_class}, _from, state) do
    # Algedonic always passes
    if event_class == :algedonic do
      {:reply, :allowed, state}
    else
      # Check token bucket
      case consume_token(event_class, state) do
        {:ok, new_state} ->
          {:reply, :allowed, new_state}
          
        {:error, :no_tokens} ->
          # Try compression if enabled
          if state.compression_config.enabled do
            {:reply, :throttled, record_throttle(event_class, state)}
          else
            {:reply, :throttled, record_throttle(event_class, state)}
          end
      end
    end
  end
  
  @impl true
  def handle_call({:compress, event, event_class}, _from, state) do
    case attempt_compression(event, event_class, state) do
      {:compressed, compressed_event, new_state} ->
        {:reply, {:compressed, compressed_event}, new_state}
        
      {:dropped, new_state} ->
        {:reply, :dropped, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_pressure, _from, state) do
    pressure = calculate_overall_pressure(state)
    {:reply, pressure, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = compile_stats(state)
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:record_inbound, event_class}, state) do
    new_stats = update_inbound_stats(event_class, state.stats)
    new_pressure = update_pressure_gauge(event_class, :inbound, state.pressure_gauges)
    
    {:noreply, %{state | stats: new_stats, pressure_gauges: new_pressure}}
  end
  
  @impl true
  def handle_info(:refill_tokens, state) do
    # Refill token buckets based on quotas
    new_buckets = Enum.reduce(state.buckets, %{}, fn {class, bucket}, acc ->
      refilled = refill_bucket(bucket, state.quotas[class])
      Map.put(acc, class, refilled)
    end)
    
    # Calculate adaptive adjustments based on pressure
    adjusted_buckets = apply_adaptive_rates(new_buckets, state)
    
    schedule_token_refill()
    
    {:noreply, %{state | buckets: adjusted_buckets}}
  end
  
  @impl true
  def handle_info(:cleanup_cache, state) do
    # Remove old cached events
    now = System.monotonic_time(:millisecond)
    
    new_cache = Map.filter(state.event_cache, fn {_key, entry} ->
      now - entry.timestamp < @cache_ttl
    end)
    
    schedule_cache_cleanup()
    
    {:noreply, %{state | event_cache: new_cache}}
  end
  
  # Private Functions
  
  defp default_quotas do
    %{
      algedonic: :unlimited,
      s5_policy: 50,         # Events per second
      s4_intelligence: 100,
      s3_control: 200,
      s2_coordination: 500,
      s1_operational: 1000,
      general: 100
    }
  end
  
  defp default_compression_config do
    %{
      enabled: true,
      similarity_threshold: @similarity_threshold,
      aggregation_window: 100,  # ms
      max_cache_size: 10_000
    }
  end
  
  defp init_bucket(:unlimited) do
    %{
      tokens: :unlimited,
      max_tokens: :unlimited,
      last_refill: System.monotonic_time(:millisecond)
    }
  end
  
  defp init_bucket(quota) when is_integer(quota) do
    %{
      tokens: quota,
      max_tokens: quota * 2,  # Allow burst
      refill_rate: quota / 10,  # Tokens per 100ms
      last_refill: System.monotonic_time(:millisecond)
    }
  end
  
  defp init_stats do
    %{
      events_allowed: %{},
      events_throttled: %{},
      events_compressed: %{},
      compression_ratio: 0.0,
      total_variety_reduced: 0
    }
  end
  
  defp init_pressure_gauges do
    %{
      s1_operational: %{inbound: 0, outbound: 0, capacity: 1000},
      s2_coordination: %{inbound: 0, outbound: 0, capacity: 500},
      s3_control: %{inbound: 0, outbound: 0, capacity: 200},
      s4_intelligence: %{inbound: 0, outbound: 0, capacity: 100},
      s5_policy: %{inbound: 0, outbound: 0, capacity: 50},
      general: %{inbound: 0, outbound: 0, capacity: 100}
    }
  end
  
  defp consume_token(:algedonic, state), do: {:ok, state}
  
  defp consume_token(event_class, state) do
    bucket = Map.get(state.buckets, event_class)
    
    case bucket do
      nil ->
        # Unknown class - use general bucket
        consume_token(:general, state)
        
      %{tokens: :unlimited} ->
        {:ok, state}
        
      %{tokens: tokens} when tokens > 0 ->
        # Consume token
        new_bucket = %{bucket | tokens: tokens - 1}
        new_buckets = Map.put(state.buckets, event_class, new_bucket)
        new_stats = update_allowed_stats(event_class, state.stats)
        
        {:ok, %{state | buckets: new_buckets, stats: new_stats}}
        
      _ ->
        # No tokens available
        {:error, :no_tokens}
    end
  end
  
  defp refill_bucket(%{tokens: :unlimited} = bucket, _quota), do: bucket
  
  defp refill_bucket(bucket, _quota) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - bucket.last_refill
    
    # Calculate tokens to add
    tokens_to_add = trunc(bucket.refill_rate * (elapsed / 100))
    
    # Refill up to max
    new_tokens = min(bucket.tokens + tokens_to_add, bucket.max_tokens)
    
    %{bucket | 
      tokens: new_tokens,
      last_refill: now
    }
  end
  
  defp apply_adaptive_rates(buckets, state) do
    # Adjust rates based on overall system pressure
    pressure = calculate_overall_pressure(state)
    
    if pressure > 0.8 do
      # High pressure - reduce lower priority rates
      buckets
      |> Map.update!(:s1_operational, &reduce_rate(&1, 0.5))
      |> Map.update!(:general, &reduce_rate(&1, 0.3))
    else
      buckets
    end
  end
  
  defp reduce_rate(%{tokens: :unlimited} = bucket, _factor), do: bucket
  defp reduce_rate(bucket, factor) do
    %{bucket | 
      tokens: trunc(bucket.tokens * factor),
      refill_rate: bucket.refill_rate * factor
    }
  end
  
  defp attempt_compression(event, event_class, state) do
    # Generate event signature for similarity detection
    signature = generate_event_signature(event)
    
    # Look for similar recent events
    similar_events = find_similar_events(signature, event_class, state.event_cache)
    
    if length(similar_events) >= 3 do
      # Compress by creating aggregate event
      compressed = create_compressed_event(event, similar_events)
      
      # Update stats
      new_stats = state.stats
      |> update_compressed_stats(event_class)
      |> Map.update!(:total_variety_reduced, &(&1 + length(similar_events)))
      
      {:compressed, compressed, %{state | stats: new_stats}}
    else
      # Cache this event for future compression
      new_cache = cache_event(event, signature, event_class, state.event_cache)
      
      # Drop if cache is full
      if map_size(new_cache) > state.compression_config.max_cache_size do
        {:dropped, state}
      else
        {:dropped, %{state | event_cache: new_cache}}
      end
    end
  end
  
  defp generate_event_signature(event) do
    # Create a signature for similarity comparison
    %{
      event_name: event[:event_name],
      data_keys: event[:data] |> Map.keys() |> Enum.sort(),
      data_hash: :erlang.phash2(event[:data], 1_000_000)
    }
  end
  
  defp find_similar_events(signature, event_class, cache) do
    now = System.monotonic_time(:millisecond)
    window = 100  # ms
    
    cache
    |> Map.values()
    |> Enum.filter(fn entry ->
      entry.event_class == event_class and
      now - entry.timestamp < window and
      similar_signatures?(signature, entry.signature)
    end)
  end
  
  defp similar_signatures?(sig1, sig2) do
    sig1.event_name == sig2.event_name and
    sig1.data_keys == sig2.data_keys and
    abs(sig1.data_hash - sig2.data_hash) < 100_000  # Similar hash values
  end
  
  defp create_compressed_event(event, similar_events) do
    count = length(similar_events) + 1
    
    %{event |
      event_name: :"#{event.event_name}_compressed",
      data: Map.merge(event.data, %{
        compression_count: count,
        time_window_ms: 100,
        original_events: [event | Enum.map(similar_events, & &1.event)]
      }),
      metadata: Map.put(event[:metadata] || %{}, :compressed, true)
    }
  end
  
  defp cache_event(event, signature, event_class, cache) do
    key = {event_class, signature.data_hash}
    
    entry = %{
      event: event,
      signature: signature,
      event_class: event_class,
      timestamp: System.monotonic_time(:millisecond)
    }
    
    Map.put(cache, key, entry)
  end
  
  defp calculate_overall_pressure(state) do
    # Calculate pressure as ratio of current flow to capacity
    total_flow = Enum.reduce(state.pressure_gauges, 0, fn {_class, gauge}, acc ->
      acc + gauge.inbound + gauge.outbound
    end)
    
    total_capacity = Enum.reduce(state.pressure_gauges, 0, fn {_class, gauge}, acc ->
      acc + gauge.capacity * 2  # Inbound + outbound
    end)
    
    min(total_flow / total_capacity, 1.0)
  end
  
  defp record_throttle(event_class, state) do
    new_stats = update_throttled_stats(event_class, state.stats)
    new_pressure = update_pressure_gauge(event_class, :throttled, state.pressure_gauges)
    
    # Report high pressure if crossing threshold
    if calculate_overall_pressure(%{state | pressure_gauges: new_pressure}) > 0.8 do
      report_variety_pressure(event_class)
    end
    
    %{state | stats: new_stats, pressure_gauges: new_pressure}
  end
  
  defp update_allowed_stats(event_class, stats) do
    Map.update(stats, :events_allowed, %{event_class => 1}, fn allowed ->
      Map.update(allowed, event_class, 1, &(&1 + 1))
    end)
  end
  
  defp update_throttled_stats(event_class, stats) do
    Map.update(stats, :events_throttled, %{event_class => 1}, fn throttled ->
      Map.update(throttled, event_class, 1, &(&1 + 1))
    end)
  end
  
  defp update_compressed_stats(event_class, stats) do
    Map.update(stats, :events_compressed, %{event_class => 1}, fn compressed ->
      Map.update(compressed, event_class, 1, &(&1 + 1))
    end)
  end
  
  defp update_inbound_stats(event_class, stats) do
    # For now, just count as allowed
    update_allowed_stats(event_class, stats)
  end
  
  defp update_pressure_gauge(event_class, direction, gauges) do
    if Map.has_key?(gauges, event_class) do
      Map.update!(gauges, event_class, fn gauge ->
        case direction do
          :inbound -> %{gauge | inbound: gauge.inbound + 1}
          :outbound -> %{gauge | outbound: gauge.outbound + 1}
          :throttled -> gauge  # Don't count throttled in pressure
        end
      end)
    else
      # Use general gauge
      update_pressure_gauge(:general, direction, gauges)
    end
  end
  
  defp compile_stats(state) do
    %{
      quotas: state.quotas,
      current_tokens: Map.new(state.buckets, fn {class, bucket} ->
        {class, bucket.tokens}
      end),
      events_allowed: state.stats.events_allowed,
      events_throttled: state.stats.events_throttled,
      events_compressed: state.stats.events_compressed,
      compression_ratio: calculate_compression_ratio(state.stats),
      total_variety_reduced: state.stats.total_variety_reduced,
      current_pressure: calculate_overall_pressure(state),
      pressure_by_channel: Map.new(state.pressure_gauges, fn {class, gauge} ->
        pressure = (gauge.inbound + gauge.outbound) / (gauge.capacity * 2)
        {class, min(pressure, 1.0)}
      end)
    }
  end
  
  defp calculate_compression_ratio(stats) do
    total_compressed = stats.events_compressed
    |> Map.values()
    |> Enum.sum()
    
    total_events = total_compressed + stats.total_variety_reduced
    
    if total_events > 0 do
      stats.total_variety_reduced / total_events
    else
      0.0
    end
  end
  
  defp report_variety_pressure(event_class) do
    Logger.warn("VSM Variety: High pressure detected on channel #{event_class}")
    
    Telemetry.execute(
      [:vsm, :variety, :pressure_high],
      %{pressure: 0.8},
      %{channel: event_class}
    )
  end
  
  defp schedule_token_refill do
    Process.send_after(self(), :refill_tokens, @token_refill_interval)
  end
  
  defp schedule_cache_cleanup do
    Process.send_after(self(), :cleanup_cache, @cache_ttl)
  end
end