defmodule AutonomousOpponent.EventBus.OrderedDelivery do
  @moduledoc """
  Provides causal ordering guarantees for EventBus delivery using HLC timestamps.
  
  This GenServer acts as an ordering buffer between EventBus and subscribers,
  ensuring events are delivered in causal order within configurable time windows.
  
  ## Architecture
  
  Each subscriber that opts into ordered delivery gets its own OrderedDelivery
  process. This prevents head-of-line blocking and allows per-subscriber tuning.
  
  ## Ordering Guarantees
  
  - Events are delivered in HLC timestamp order
  - Events within the buffer window are sorted before delivery
  - Late events outside the window are delivered immediately with a warning
  - Duplicate events (same HLC) are deduplicated
  
  ## Performance Characteristics
  
  - O(log n) insertion into priority queue
  - Batched delivery reduces message passing overhead
  - Adaptive windowing minimizes latency during low activity
  - Memory bounded by max_buffer_size
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponent.Telemetry.SystemTelemetry
  
  @type hlc_timestamp :: %{
    physical: non_neg_integer(),
    logical: non_neg_integer(), 
    node_id: String.t()
  }
  
  @type event :: %{
    id: String.t(),
    timestamp: hlc_timestamp(),
    topic: atom(),
    data: any(),
    metadata: map()
  }
  
  @type state :: %{
    subscriber: pid(),
    subscriber_ref: reference(),
    buffer: :gb_trees.tree(),
    buffer_window_ms: non_neg_integer(),
    delivery_timer: reference() | nil,
    stats: stats(),
    config: config(),
    last_delivered_hlc: hlc_timestamp() | nil,
    started_at: DateTime.t()
  }
  
  @type stats :: %{
    events_buffered: non_neg_integer(),
    events_delivered: non_neg_integer(),
    events_reordered: non_neg_integer(),
    events_late: non_neg_integer(),
    events_duplicate: non_neg_integer(),
    buffer_depth_sum: non_neg_integer(),
    buffer_depth_samples: non_neg_integer(),
    last_reorder_ratio: float()
  }
  
  @type config :: %{
    max_buffer_size: non_neg_integer(),
    max_window_ms: non_neg_integer(),
    min_window_ms: non_neg_integer(),
    adaptive_window: boolean(),
    batch_size: non_neg_integer(),
    algedonic_bypass_threshold: float(),
    clock_drift_tolerance_ms: non_neg_integer()
  }
  
  # Default configuration
  @default_config %{
    max_buffer_size: 10_000,
    max_window_ms: 100,
    min_window_ms: 10,
    adaptive_window: true,
    batch_size: 100,
    algedonic_bypass_threshold: 0.95,
    clock_drift_tolerance_ms: 1000  # 1 second default tolerance
  }
  
  @doc """
  Starts an OrderedDelivery process for a subscriber.
  
  ## Options
  
  - `:buffer_window_ms` - Initial buffer window in milliseconds (default: 50)
  - `:max_buffer_size` - Maximum events to buffer before forced flush (default: 10,000)
  - `:adaptive_window` - Enable adaptive window sizing (default: true)
  - `:batch_size` - Events to deliver per batch (default: 100)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  @doc """
  Submits an event for ordered delivery.
  """
  def submit_event(server, event) do
    GenServer.cast(server, {:submit_event, event})
  end
  
  @doc """
  Gets current statistics for monitoring.
  """
  def get_stats(server) do
    GenServer.call(server, :get_stats)
  end
  
  @doc """
  Forces immediate delivery of all buffered events.
  """
  def flush(server) do
    GenServer.call(server, :flush)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    subscriber = Keyword.fetch!(opts, :subscriber)
    
    # Monitor subscriber to clean up if it dies
    subscriber_ref = Process.monitor(subscriber)
    
    config = struct(@default_config, Keyword.get(opts, :config, %{}))
    
    initial_state = %{
      subscriber: subscriber,
      subscriber_ref: subscriber_ref,
      buffer: :gb_trees.empty(),
      buffer_window_ms: Keyword.get(opts, :buffer_window_ms, 50),
      delivery_timer: nil,
      stats: init_stats(),
      config: config,
      last_delivered_hlc: nil,
      started_at: DateTime.utc_now()
    }
    
    Logger.info("OrderedDelivery started for subscriber #{inspect(subscriber)}")
    
    {:ok, initial_state}
  end
  
  @impl true
  def handle_cast({:submit_event, event}, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Check for algedonic bypass
    if should_bypass?(event, state.config) do
      deliver_immediately(event, state)
      
      SystemTelemetry.record(:event_bus_ordered_delivery, %{
        action: :bypass,
        duration_us: System.monotonic_time(:microsecond) - start_time
      })
      
      {:noreply, state}
    else
      new_state = buffer_event(event, state)
      
      SystemTelemetry.record(:event_bus_ordered_delivery, %{
        action: :buffer,
        buffer_size: :gb_trees.size(new_state.buffer),
        duration_us: System.monotonic_time(:microsecond) - start_time
      })
      
      {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = calculate_detailed_stats(state)
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:flush, _from, state) do
    new_state = deliver_all_events(state)
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info(:delivery_timeout, state) do
    new_state = deliver_ready_events(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{subscriber_ref: ref} = state) do
    Logger.warning("Subscriber process terminated, shutting down OrderedDelivery")
    {:stop, :normal, state}
  end
  
  # Private functions
  
  defp init_stats do
    %{
      events_buffered: 0,
      events_delivered: 0,
      events_reordered: 0,
      events_late: 0,
      events_duplicate: 0,
      buffer_depth_sum: 0,
      buffer_depth_samples: 0,
      last_reorder_ratio: 0.0
    }
  end
  
  defp should_bypass?(event, config) do
    # Algedonic signals above threshold bypass ordering
    metadata = Map.get(event, :metadata, %{})
    
    cond do
      get_in(metadata, [:algedonic]) == true and 
        is_number(get_in(metadata, [:intensity])) and
        get_in(metadata, [:intensity]) >= config.algedonic_bypass_threshold -> true
      get_in(metadata, [:bypass_all]) == true -> true
      true -> false
    end
  end
  
  defp deliver_immediately(event, state) do
    try do
      send(state.subscriber, {:ordered_event, event})
      
      SystemTelemetry.record(:event_bus_delivery, %{
        topic: event.topic,
        ordering: :bypassed,
        subscriber: inspect(state.subscriber)
      })
    catch
      :error, :badarg ->
        Logger.warning("Failed to deliver bypassed event to dead subscriber: #{inspect(state.subscriber)}")
    end
  end
  
  defp buffer_event(event, state) do
    # Check if this is a duplicate
    if is_duplicate?(event, state) do
      %{state | stats: %{state.stats | events_duplicate: state.stats.events_duplicate + 1}}
    else
      # Categorize event timing
      case categorize_event(event, state) do
        :future ->
          # Add to buffer
          add_to_buffer(event, state)
          
        :late ->
          # Deliver immediately with warning
          deliver_late_event(event, state)
          
        :in_order ->
          # Add to buffer for batch delivery
          add_to_buffer(event, state)
      end
    end
  end
  
  defp is_duplicate?(event, state) do
    # Check if we've seen this exact HLC before
    case state.last_delivered_hlc do
      nil -> false
      last_hlc -> compare_hlc(event.timestamp, last_hlc) == :eq
    end
  end
  
  defp categorize_event(event, state) do
    now = System.os_time(:millisecond)
    event_time = div(event.timestamp.physical, 1_000_000)  # Convert to milliseconds
    
    cond do
      # Event is from the future (clock drift?)
      event_time > now + state.config.clock_drift_tolerance_ms -> :future
      
      # Event is older than our buffer window
      now - event_time > state.buffer_window_ms -> :late
      
      # Event is within buffer window
      true -> :in_order
    end
  end
  
  defp add_to_buffer(event, state) do
    # Use HLC as key for ordering
    key = hlc_to_key(event.timestamp)
    new_buffer = :gb_trees.enter(key, event, state.buffer)
    
    # Update stats
    new_stats = %{state.stats | 
      events_buffered: state.stats.events_buffered + 1
    }
    
    # Check if we've hit buffer size limit
    new_state = %{state | buffer: new_buffer, stats: new_stats}
    
    if :gb_trees.size(new_buffer) >= state.config.max_buffer_size do
      # Force delivery to prevent unbounded growth
      deliver_all_events(new_state)
    else
      # Schedule delivery if not already scheduled
      schedule_delivery(new_state)
    end
  end
  
  defp deliver_late_event(event, state) do
    Logger.warning("Late event detected: #{inspect(event.id)} is #{state.buffer_window_ms}ms+ old")
    
    deliver_immediately(event, state)
    
    %{state | stats: %{state.stats | 
      events_late: state.stats.events_late + 1,
      events_delivered: state.stats.events_delivered + 1
    }}
  end
  
  defp schedule_delivery(%{delivery_timer: nil} = state) do
    # Schedule first delivery
    timer = Process.send_after(self(), :delivery_timeout, state.buffer_window_ms)
    %{state | delivery_timer: timer}
  end
  defp schedule_delivery(state), do: state  # Already scheduled
  
  defp deliver_ready_events(state) do
    now = System.os_time(:millisecond)
    cutoff_time = now - state.buffer_window_ms
    
    # Find events ready for delivery
    {ready, remaining} = split_ready_events(state.buffer, cutoff_time)
    
    # Deliver events in batches
    {delivered_count, last_hlc} = deliver_events_in_batches(ready, state)
    
    # Update stats
    buffer_size = :gb_trees.size(state.buffer)
    new_stats = %{state.stats |
      events_delivered: state.stats.events_delivered + delivered_count,
      buffer_depth_sum: state.stats.buffer_depth_sum + buffer_size,
      buffer_depth_samples: state.stats.buffer_depth_samples + 1
    }
    
    # Calculate reorder ratio for adaptive windowing
    reorder_ratio = calculate_reorder_ratio(ready)
    new_stats = %{new_stats | last_reorder_ratio: reorder_ratio}
    
    # Adapt window if enabled
    new_window = if state.config.adaptive_window do
      adapt_window(state, new_stats)
    else
      state.buffer_window_ms
    end
    
    # Cancel old timer
    if state.delivery_timer, do: Process.cancel_timer(state.delivery_timer)
    
    # Schedule next delivery if buffer not empty
    new_state = %{state | 
      buffer: remaining,
      stats: new_stats,
      buffer_window_ms: new_window,
      delivery_timer: nil,
      last_delivered_hlc: last_hlc
    }
    
    if :gb_trees.size(remaining) > 0 do
      schedule_delivery(new_state)
    else
      new_state
    end
  end
  
  defp deliver_all_events(state) do
    # Convert tree to list and deliver all
    events = :gb_trees.to_list(state.buffer)
    {delivered_count, last_hlc} = deliver_events_in_batches(events, state)
    
    # Update stats
    new_stats = %{state.stats |
      events_delivered: state.stats.events_delivered + delivered_count
    }
    
    # Cancel timer and clear buffer
    if state.delivery_timer, do: Process.cancel_timer(state.delivery_timer)
    
    %{state | 
      buffer: :gb_trees.empty(),
      stats: new_stats,
      delivery_timer: nil,
      last_delivered_hlc: last_hlc
    }
  end
  
  defp split_ready_events(buffer, cutoff_time) do
    # Split tree into ready and remaining based on physical timestamp
    split_fun = fn {_key, event} ->
      div(event.timestamp.physical, 1_000_000) <= cutoff_time
    end
    
    # Manual split since gb_trees doesn't have built-in split
    events = :gb_trees.to_list(buffer)
    {ready, remaining_list} = Enum.split_with(events, split_fun)
    
    remaining_tree = :gb_trees.from_orddict(remaining_list)
    
    {ready, remaining_tree}
  end
  
  defp deliver_events_in_batches(events, state) do
    # Use Stream for better memory efficiency
    {delivered_count, last_hlc} = events
    |> Stream.chunk_every(state.config.batch_size)
    |> Enum.reduce({0, state.last_delivered_hlc}, fn batch, {count, _last_hlc} ->
      # Extract just the events (not the keys)
      batch_events = Enum.map(batch, fn {_key, event} -> event end)
      
      # Send batch to subscriber with error handling
      try do
        send(state.subscriber, {:ordered_event_batch, batch_events})
      catch
        :error, :badarg ->
          # Subscriber process is dead
          Logger.warning("Failed to deliver batch to dead subscriber: #{inspect(state.subscriber)}")
      end
      
      # Get last HLC from this batch
      last_event_hlc = if last_event = List.last(batch_events) do
        last_event.timestamp
      else
        state.last_delivered_hlc
      end
      
      # Sample telemetry for high-frequency events (record only 10%)
      sample_rate = if length(batch) > 50, do: 0.1, else: 1.0
      
      if :rand.uniform() <= sample_rate do
        # Record batch-level telemetry instead of per-event
        SystemTelemetry.record(:event_bus_delivery_batch, %{
          batch_size: length(batch),
          topics: batch_events |> Enum.map(& &1.topic) |> Enum.uniq(),
          ordering: :ordered,
          subscriber: inspect(state.subscriber),
          sampled: sample_rate < 1.0
        })
      end
      
      {count + length(batch), last_event_hlc}
    end)
    
    {delivered_count, last_hlc}
  end
  
  defp calculate_reorder_ratio(events) do
    # Calculate how many events were out of order
    {_, reordered} = 
      Enum.reduce(events, {nil, 0}, fn {_key, event}, {last_hlc, count} ->
        if last_hlc && compare_hlc(event.timestamp, last_hlc) == :lt do
          {event.timestamp, count + 1}
        else
          {event.timestamp, count}
        end
      end)
    
    if length(events) > 0 do
      reordered / length(events)
    else
      0.0
    end
  end
  
  defp adapt_window(state, stats) do
    # Adaptive window sizing based on event rate and reorder ratio
    avg_buffer_depth = if stats.buffer_depth_samples > 0 do
      stats.buffer_depth_sum / stats.buffer_depth_samples
    else
      0
    end
    
    event_rate = stats.events_buffered / max(1, DateTime.diff(DateTime.utc_now(), state.started_at))
    
    cond do
      # High reorder ratio - increase window
      stats.last_reorder_ratio > 0.1 ->
        min(state.buffer_window_ms * 1.5, state.config.max_window_ms)
        
      # Low event rate - decrease window
      event_rate < 10 ->
        max(state.buffer_window_ms * 0.8, state.config.min_window_ms)
        
      # High event rate with good ordering - decrease window
      event_rate > 100 && stats.last_reorder_ratio < 0.01 ->
        max(state.buffer_window_ms * 0.9, state.config.min_window_ms)
        
      # Default - no change
      true ->
        state.buffer_window_ms
    end
    |> round()
  end
  
  defp calculate_detailed_stats(state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.started_at)
    
    avg_buffer_depth = if state.stats.buffer_depth_samples > 0 do
      state.stats.buffer_depth_sum / state.stats.buffer_depth_samples
    else
      0
    end
    
    %{
      subscriber: state.subscriber,
      uptime_seconds: uptime_seconds,
      current_buffer_size: :gb_trees.size(state.buffer),
      current_window_ms: state.buffer_window_ms,
      events_buffered: state.stats.events_buffered,
      events_delivered: state.stats.events_delivered,
      events_reordered: state.stats.events_reordered,
      events_late: state.stats.events_late,
      events_duplicate: state.stats.events_duplicate,
      avg_buffer_depth: Float.round(avg_buffer_depth, 2),
      last_reorder_ratio: Float.round(state.stats.last_reorder_ratio, 3),
      throughput_per_sec: Float.round(state.stats.events_delivered / max(1, uptime_seconds), 2)
    }
  end
  
  # HLC comparison and conversion utilities
  
  defp hlc_to_key(hlc) do
    # Create sortable key from HLC components
    # Physical time is primary sort, logical is secondary, node_id is tertiary
    {hlc.physical, hlc.logical, hlc.node_id}
  end
  
  defp compare_hlc(hlc1, hlc2) do
    key1 = hlc_to_key(hlc1)
    key2 = hlc_to_key(hlc2)
    
    cond do
      key1 < key2 -> :lt
      key1 > key2 -> :gt
      true -> :eq
    end
  end
end