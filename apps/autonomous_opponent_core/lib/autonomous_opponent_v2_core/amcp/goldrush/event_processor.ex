defmodule AutonomousOpponentV2Core.AMCP.Goldrush.EventProcessor do
  @moduledoc """
  Goldrush Event Stream Processor for aMCP.
  
  High-performance event stream processing engine that:
  - Processes live event streams with microsecond latency
  - Applies user-defined pattern matchers in real-time
  - Broadcasts structured event contexts to subscribers
  - Triggers workflows from matching events
  - Maintains event causality chains
  
  Built on Elixir's GenStage for backpressure-aware streaming.
  """
  
  use GenStage
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.AMCP.Goldrush.PatternMatcher
  alias AutonomousOpponentV2Core.AMCP.Context.SemanticFusion
  
  defstruct [
    :event_buffer,
    :pattern_matchers,
    :subscribers,
    :metrics,
    :processing_state
  ]
  
  @buffer_size 10_000
  @batch_size 100
  @processing_timeout 5_000
  
  # Public API
  
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a pattern matcher for real-time event filtering.
  
  Pattern examples:
  - %{type: :temperature, value: %{gt: 90}}
  - %{source: :vsm_s1, urgency: %{gte: 0.8}}
  - %{and: [%{cpu_util: %{gt: 80}}, %{memory_util: %{gt: 70}}]}
  """
  def register_pattern(pattern_id, pattern_spec, callback) do
    GenStage.call(__MODULE__, {:register_pattern, pattern_id, pattern_spec, callback})
  end
  
  @doc """
  Unregisters a pattern matcher.
  """
  def unregister_pattern(pattern_id) do
    GenStage.call(__MODULE__, {:unregister_pattern, pattern_id})
  end
  
  @doc """
  Gets current processing metrics.
  """
  def get_metrics do
    GenStage.call(__MODULE__, :get_metrics)
  end
  
  @doc """
  Processes a batch of events immediately (for testing).
  """
  def process_events(events) when is_list(events) do
    GenStage.cast(__MODULE__, {:process_batch, events})
  end
  
  # GenStage Callbacks
  
  @impl true
  def init(opts) do
    # Subscribe to all EventBus events for stream processing
    EventBus.subscribe(:all)
    
    # Subscribe to AMCP transport events
    EventBus.subscribe(:amcp_message_received)
    EventBus.subscribe(:amcp_context_enriched)
    
    state = %__MODULE__{
      event_buffer: :queue.new(),
      pattern_matchers: %{},
      subscribers: %{},
      metrics: init_metrics(),
      processing_state: :active
    }
    
    Logger.info("Goldrush EventProcessor started")
    {:producer, state}
  end
  
  @impl true
  def handle_call({:register_pattern, pattern_id, pattern_spec, callback}, _from, state) do
    case PatternMatcher.compile_pattern(pattern_spec) do
      {:ok, compiled_pattern} ->
        new_matchers = Map.put(state.pattern_matchers, pattern_id, %{
          pattern: compiled_pattern,
          callback: callback,
          matches: 0,
          registered_at: DateTime.utc_now()
        })
        
        state = %{state | pattern_matchers: new_matchers}
        Logger.info("Registered pattern matcher: #{pattern_id}")
        {:reply, :ok, [], state}
        
      {:error, reason} ->
        Logger.error("Failed to compile pattern #{pattern_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, [], state}
    end
  end
  
  @impl true
  def handle_call({:unregister_pattern, pattern_id}, _from, state) do
    new_matchers = Map.delete(state.pattern_matchers, pattern_id)
    state = %{state | pattern_matchers: new_matchers}
    Logger.info("Unregistered pattern matcher: #{pattern_id}")
    {:reply, :ok, [], state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, [], state}
  end
  
  @impl true
  def handle_cast({:process_batch, events}, state) do
    {processed_events, state} = process_event_batch(events, state)
    {:noreply, processed_events, state}
  end
  
  @impl true
  def handle_info({:event, event_name, data}, state) do
    # Convert EventBus events to stream events
    stream_event = %{
      id: generate_event_id(),
      name: event_name,
      data: data,
      timestamp: DateTime.utc_now(),
      source: :event_bus,
      causality_id: extract_causality_id(data)
    }
    
    state = add_to_buffer(stream_event, state)
    
    # Check if buffer should be flushed
    if :queue.len(state.event_buffer) >= @batch_size do
      {events_to_process, state} = flush_buffer(state)
      {processed_events, state} = process_event_batch(events_to_process, state)
      {:noreply, processed_events, state}
    else
      {:noreply, [], state}
    end
  end
  
  @impl true
  def handle_info(:flush_buffer, state) do
    {events_to_process, state} = flush_buffer(state)
    {processed_events, state} = process_event_batch(events_to_process, state)
    
    # Schedule next flush
    Process.send_after(self(), :flush_buffer, 100)
    
    {:noreply, processed_events, state}
  end
  
  @impl true
  def handle_demand(demand, state) when demand > 0 do
    # GenStage consumer is requesting events
    if :queue.len(state.event_buffer) > 0 do
      {events_to_send, state} = take_from_buffer(min(demand, @batch_size), state)
      {:noreply, events_to_send, state}
    else
      {:noreply, [], state}
    end
  end
  
  # Private Functions
  
  defp init_metrics do
    %{
      events_processed: 0,
      events_matched: 0,
      patterns_triggered: 0,
      processing_time_avg: 0,
      last_processed_at: nil,
      buffer_size: 0,
      active_patterns: 0
    }
  end
  
  defp add_to_buffer(event, state) do
    if :queue.len(state.event_buffer) >= @buffer_size do
      # Buffer full, drop oldest event
      {_, buffer} = :queue.out(state.event_buffer)
      buffer = :queue.in(event, buffer)
      %{state | event_buffer: buffer}
    else
      buffer = :queue.in(event, state.event_buffer)
      %{state | event_buffer: buffer}
    end
  end
  
  defp flush_buffer(state) do
    events = :queue.to_list(state.event_buffer)
    state = %{state | event_buffer: :queue.new()}
    {events, state}
  end
  
  defp take_from_buffer(count, state) do
    {events, remaining_buffer} = split_queue(state.event_buffer, count)
    state = %{state | event_buffer: remaining_buffer}
    {events, state}
  end
  
  defp split_queue(queue, count) do
    split_queue(queue, count, [])
  end
  
  defp split_queue(queue, 0, acc) do
    {Enum.reverse(acc), queue}
  end
  
  defp split_queue(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, item}, remaining} ->
        split_queue(remaining, count - 1, [item | acc])
      {:empty, queue} ->
        {Enum.reverse(acc), queue}
    end
  end
  
  defp process_event_batch(events, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Apply semantic enrichment to events
    enriched_events = Enum.map(events, &enrich_event/1)
    
    # Apply pattern matching
    {matched_events, state} = apply_pattern_matching(enriched_events, state)
    
    # Update metrics
    processing_time = System.monotonic_time(:microsecond) - start_time
    state = update_metrics(state, length(events), length(matched_events), processing_time)
    
    # Return events for downstream consumers
    {enriched_events, state}
  end
  
  defp enrich_event(event) do
    # Apply semantic fusion to extract additional context
    semantic_context = SemanticFusion.analyze_event(event)
    
    Map.merge(event, %{
      semantic_context: semantic_context,
      enriched_at: DateTime.utc_now(),
      processing_stage: :goldrush
    })
  end
  
  defp apply_pattern_matching(events, state) do
    matched_events = []
    
    {matched_events, updated_matchers} = Enum.reduce(events, {matched_events, state.pattern_matchers}, fn event, {matches, matchers} ->
      {event_matches, updated_matchers} = Enum.reduce(matchers, {matches, matchers}, fn {pattern_id, matcher_info}, {acc_matches, acc_matchers} ->
        case PatternMatcher.match_event(matcher_info.pattern, event) do
          {:match, context} ->
            # Pattern matched, trigger callback
            trigger_pattern_callback(pattern_id, event, context, matcher_info.callback)
            
            # Update matcher stats
            updated_matcher = %{matcher_info | matches: matcher_info.matches + 1}
            updated_matchers = Map.put(acc_matchers, pattern_id, updated_matcher)
            
            # Add to matched events
            matched_event = Map.put(event, :pattern_matches, [{pattern_id, context}])
            {[matched_event | acc_matches], updated_matchers}
            
          :no_match ->
            {acc_matches, acc_matchers}
        end
      end)
      
      {event_matches, updated_matchers}
    end)
    
    state = %{state | pattern_matchers: updated_matchers}
    {matched_events, state}
  end
  
  defp trigger_pattern_callback(pattern_id, event, context, callback) do
    try do
      case callback do
        {module, function, args} ->
          apply(module, function, [pattern_id, event, context | args])
          
        fun when is_function(fun, 3) ->
          fun.(pattern_id, event, context)
          
        event_name when is_atom(event_name) ->
          # Publish as EventBus event
          EventBus.publish(event_name, %{
            pattern_id: pattern_id,
            matched_event: event,
            match_context: context,
            triggered_at: DateTime.utc_now()
          })
      end
      
      Logger.debug("Pattern #{pattern_id} triggered for event #{event.id}")
      
    rescue
      error ->
        Logger.error("Pattern callback failed for #{pattern_id}: #{inspect(error)}")
    end
  end
  
  defp update_metrics(state, events_count, matches_count, processing_time) do
    metrics = state.metrics
    
    new_total = metrics.events_processed + events_count
    new_avg_time = if new_total > 0 do
      (metrics.processing_time_avg * metrics.events_processed + processing_time) / new_total
    else
      processing_time
    end
    
    new_metrics = %{
      events_processed: new_total,
      events_matched: metrics.events_matched + matches_count,
      patterns_triggered: metrics.patterns_triggered + matches_count,
      processing_time_avg: round(new_avg_time),
      last_processed_at: DateTime.utc_now(),
      buffer_size: :queue.len(state.event_buffer),
      active_patterns: map_size(state.pattern_matchers)
    }
    
    %{state | metrics: new_metrics}
  end
  
  defp generate_event_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp extract_causality_id(data) when is_map(data) do
    data[:causality_id] || data["causality_id"] || generate_event_id()
  end
  
  defp extract_causality_id(_data), do: generate_event_id()
end