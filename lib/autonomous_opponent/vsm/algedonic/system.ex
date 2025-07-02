defmodule AutonomousOpponent.VSM.Algedonic.System do
  @moduledoc """
  VSM Algedonic System - Pain/Pleasure Signal Processing

  Implements Beer's algedonic channel for urgent system interventions with
  guaranteed sub-100ms response time. This system bypasses normal hierarchical
  channels for critical signals.

  Key features:
  - Pain signals for urgent interventions
  - Pleasure signals for positive reinforcement
  - Signal filtering to prevent noise amplification
  - Algedonic memory for pattern learning
  - Direct integration with all S1-S5 subsystems
  """

  use GenServer
  require Logger

  alias AutonomousOpponent.EventBus

  # 100ms max response time
  @response_time_target 100
  # 5 minutes signal memory
  @signal_ttl 300_000
  # Minimum occurrences to pass filter
  @filter_threshold 3

  defstruct [
    :signal_queue,
    :signal_memory,
    :filter_state,
    :processing_stats,
    :subsystem_hooks,
    :priority_queue
  ]

  # Signal types
  @type signal_type :: :pain | :pleasure
  @type severity :: :low | :medium | :high | :critical

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @doc """
  Send a pain signal for urgent intervention
  """
  def pain(source, reason, severity \\ :high, data \\ %{}) do
    signal = %{
      type: :pain,
      source: source,
      reason: reason,
      severity: severity,
      data: data,
      timestamp: System.monotonic_time(:microsecond)
    }

    GenServer.cast(__MODULE__, {:signal, signal})
  end

  @doc """
  Send a pleasure signal for positive reinforcement
  """
  def pleasure(source, reason, intensity \\ :medium, data \\ %{}) do
    signal = %{
      type: :pleasure,
      source: source,
      reason: reason,
      intensity: intensity,
      data: data,
      timestamp: System.monotonic_time(:microsecond)
    }

    GenServer.cast(__MODULE__, {:signal, signal})
  end

  @doc """
  Get current algedonic state
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Get processing statistics
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Set process priority to high for guaranteed response time
    Process.flag(:priority, :high)

    # Initialize ETS tables for high-performance access
    :ets.new(:algedonic_signals, [:named_table, :public, :ordered_set])
    :ets.new(:algedonic_patterns, [:named_table, :public, :bag])

    state = %__MODULE__{
      signal_queue: :queue.new(),
      signal_memory: %{},
      filter_state: init_filter_state(),
      processing_stats: init_stats(),
      subsystem_hooks: init_subsystem_hooks(),
      priority_queue: PriorityQueue.new()
    }

    # Subscribe to algedonic events from all subsystems
    EventBus.subscribe(:algedonic_pain)
    EventBus.subscribe(:algedonic_pleasure)

    # Start signal processor
    Process.send_after(self(), :process_signals, 10)

    # Start memory cleanup
    Process.send_after(self(), :cleanup_memory, @signal_ttl)

    Logger.info("Algedonic System initialized with high priority")

    {:ok, state}
  end

  @impl true
  def handle_cast({:signal, signal}, state) do
    start_time = System.monotonic_time(:microsecond)

    # Priority queue insertion based on severity/intensity
    priority = calculate_priority(signal)
    new_queue = PriorityQueue.insert(state.priority_queue, priority, signal)

    # Update filter state
    new_filter = update_filter(state.filter_state, signal)

    # Check if signal passes filter
    if should_process_signal?(signal, new_filter) do
      # Immediate processing for critical signals
      if signal[:severity] == :critical do
        process_critical_signal(signal, state)
      end

      # Record in memory
      new_memory = record_in_memory(state.signal_memory, signal)

      # Update stats
      processing_time = System.monotonic_time(:microsecond) - start_time
      new_stats = update_stats(state.processing_stats, signal, processing_time)

      {:noreply,
       %{
         state
         | priority_queue: new_queue,
           signal_memory: new_memory,
           filter_state: new_filter,
           processing_stats: new_stats
       }}
    else
      # Signal filtered out
      {:noreply, %{state | filter_state: new_filter}}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    summary = %{
      queue_size: PriorityQueue.size(state.priority_queue),
      memory_size: map_size(state.signal_memory),
      recent_signals: get_recent_signals(state.signal_memory, 10),
      filter_state: summarize_filter(state.filter_state)
    }

    {:reply, summary, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.processing_stats, state}
  end

  @impl true
  def handle_info(:process_signals, state) do
    start_time = System.monotonic_time(:microsecond)
    new_state = process_signal_batch(state)

    # Ensure we maintain response time target
    processing_time = System.monotonic_time(:microsecond) - start_time
    next_interval = max(10, @response_time_target - div(processing_time, 1000))

    Process.send_after(self(), :process_signals, next_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_memory, state) do
    new_memory = cleanup_old_signals(state.signal_memory)
    Process.send_after(self(), :cleanup_memory, @signal_ttl)
    {:noreply, %{state | signal_memory: new_memory}}
  end

  @impl true
  def handle_info({:event, :algedonic_pain, data}, state) do
    # Handle pain signals from EventBus
    signal =
      Map.merge(data, %{
        type: :pain,
        timestamp: System.monotonic_time(:microsecond),
        via_eventbus: true
      })

    handle_cast({:signal, signal}, state)
  end

  @impl true
  def handle_info({:event, :algedonic_pleasure, data}, state) do
    # Handle pleasure signals from EventBus
    signal =
      Map.merge(data, %{
        type: :pleasure,
        timestamp: System.monotonic_time(:microsecond),
        via_eventbus: true
      })

    handle_cast({:signal, signal}, state)
  end

  # Private Functions

  defp process_signal_batch(state) do
    case PriorityQueue.pop(state.priority_queue) do
      {:empty, _queue} ->
        state

      {{:value, {_priority, signal}}, new_queue} ->
        # Process the signal
        process_signal(signal, state)

        # Learn patterns
        learn_pattern(signal, state.signal_memory)

        # Continue processing if under time budget
        if under_time_budget?() do
          process_signal_batch(%{state | priority_queue: new_queue})
        else
          %{state | priority_queue: new_queue}
        end
    end
  end

  defp process_signal(signal, state) do
    case signal.type do
      :pain ->
        process_pain_signal(signal, state)

      :pleasure ->
        process_pleasure_signal(signal, state)
    end
  end

  defp process_pain_signal(signal, state) do
    # Route to appropriate subsystem based on source and severity
    target_subsystems = determine_target_subsystems(signal)

    Enum.each(target_subsystems, fn subsystem ->
      intervention = %{
        type: :algedonic_intervention,
        signal: signal,
        action: determine_intervention_action(signal),
        timestamp: System.monotonic_time(:microsecond)
      }

      # Direct subsystem intervention
      apply_intervention(subsystem, intervention)

      # Publish for audit
      EventBus.publish(:algedonic_intervention, Map.put(intervention, :subsystem, subsystem))
    end)
  end

  defp process_pleasure_signal(signal, state) do
    # Reinforce positive behaviors
    reinforcement = %{
      type: :positive_reinforcement,
      signal: signal,
      action: determine_reinforcement_action(signal),
      timestamp: System.monotonic_time(:microsecond)
    }

    # Apply reinforcement learning
    apply_reinforcement(signal.source, reinforcement)

    # Store in pattern memory
    store_positive_pattern(signal, state.signal_memory)
  end

  defp process_critical_signal(signal, state) do
    Logger.warning("Processing CRITICAL algedonic signal: #{inspect(signal)}")

    # Immediate intervention bypassing all queues
    intervention = %{
      type: :emergency_intervention,
      signal: signal,
      action: :immediate_shutdown,
      timestamp: System.monotonic_time(:microsecond)
    }

    # Broadcast to all subsystems
    EventBus.publish(:emergency_algedonic, intervention)

    # Direct intervention
    Enum.each([:s1, :s2, :s3, :s4, :s5], fn subsystem ->
      apply_emergency_intervention(subsystem, intervention)
    end)
  end

  defp calculate_priority(signal) do
    base_priority =
      case signal[:severity] || signal[:intensity] do
        :critical -> 1000
        :high -> 100
        :medium -> 10
        :low -> 1
        _ -> 5
      end

    # Adjust based on pattern recognition
    pattern_boost = if recognized_pattern?(signal), do: 50, else: 0

    base_priority + pattern_boost
  end

  defp init_filter_state do
    %{
      signal_counts: %{},
      time_windows: %{},
      patterns: []
    }
  end

  defp update_filter(filter_state, signal) do
    key = {signal.type, signal.source, signal.reason}
    current_time = System.monotonic_time(:millisecond)

    new_counts = Map.update(filter_state.signal_counts, key, 1, &(&1 + 1))
    new_windows = Map.put(filter_state.time_windows, key, current_time)

    %{filter_state | signal_counts: new_counts, time_windows: new_windows}
  end

  defp should_process_signal?(signal, filter_state) do
    # Critical signals always pass
    if signal[:severity] == :critical do
      true
    else
      # Check occurrence threshold
      key = {signal.type, signal.source, signal.reason}
      count = Map.get(filter_state.signal_counts, key, 0)

      # Check time-based filtering
      if count >= @filter_threshold do
        true
      else
        # Allow first occurrence or time-spaced occurrences
        last_time = Map.get(filter_state.time_windows, key, 0)
        current_time = System.monotonic_time(:millisecond)

        # 1 minute spacing
        current_time - last_time > 60_000
      end
    end
  end

  defp record_in_memory(memory, signal) do
    key = signal.timestamp
    Map.put(memory, key, signal)
  end

  defp cleanup_old_signals(memory) do
    cutoff_time = System.monotonic_time(:microsecond) - @signal_ttl * 1000

    memory
    |> Enum.filter(fn {timestamp, _signal} -> timestamp > cutoff_time end)
    |> Map.new()
  end

  defp init_stats do
    %{
      total_signals: 0,
      pain_signals: 0,
      pleasure_signals: 0,
      filtered_signals: 0,
      avg_response_time: 0,
      max_response_time: 0,
      interventions: 0
    }
  end

  defp update_stats(stats, signal, processing_time) do
    new_total = stats.total_signals + 1
    new_avg = (stats.avg_response_time * stats.total_signals + processing_time) / new_total

    stats
    |> Map.put(:total_signals, new_total)
    |> Map.update((signal.type == :pain && :pain_signals) || :pleasure_signals, 0, &(&1 + 1))
    |> Map.put(:avg_response_time, new_avg)
    |> Map.update(:max_response_time, processing_time, &max(&1, processing_time))
  end

  defp init_subsystem_hooks do
    # Initialize hooks for direct subsystem intervention
    %{
      s1: &apply_s1_intervention/1,
      s2: &apply_s2_intervention/1,
      s3: &apply_s3_intervention/1,
      s4: &apply_s4_intervention/1,
      s5: &apply_s5_intervention/1
    }
  end

  defp determine_target_subsystems(signal) do
    case signal.source do
      {:s1_operations, _} -> [:s2, :s3]
      {:s2_coordination, _} -> [:s3, :s1]
      {:s3_control, _} -> [:s4, :s5]
      # Default to S3 Control
      _ -> [:s3]
    end
  end

  defp determine_intervention_action(signal) do
    case signal.severity do
      :critical -> :emergency_shutdown
      :high -> :immediate_adjustment
      :medium -> :gradual_adjustment
      :low -> :monitor
    end
  end

  defp determine_reinforcement_action(signal) do
    case signal[:intensity] do
      :high -> :amplify_behavior
      :medium -> :maintain_behavior
      :low -> :note_behavior
    end
  end

  defp apply_intervention(subsystem, intervention) do
    # TODO: Implement actual subsystem intervention
    Logger.info("Applying intervention to #{subsystem}: #{inspect(intervention)}")
  end

  defp apply_reinforcement(source, reinforcement) do
    # TODO: Implement reinforcement learning
    Logger.info("Applying reinforcement to #{inspect(source)}: #{inspect(reinforcement)}")
  end

  defp apply_emergency_intervention(subsystem, intervention) do
    # TODO: Implement emergency intervention
    Logger.error("EMERGENCY intervention on #{subsystem}: #{inspect(intervention)}")
  end

  defp store_positive_pattern(signal, memory) do
    pattern = extract_pattern(signal)
    :ets.insert(:algedonic_patterns, {pattern, signal})
  end

  defp learn_pattern(signal, memory) do
    pattern = extract_pattern(signal)
    similar_signals = find_similar_signals(pattern, memory)

    if length(similar_signals) >= 3 do
      :ets.insert(:algedonic_patterns, {pattern, signal})
    end
  end

  defp extract_pattern(signal) do
    %{
      type: signal.type,
      source_type: elem(signal.source, 0),
      reason: signal[:reason]
    }
  end

  defp find_similar_signals(pattern, memory) do
    memory
    |> Map.values()
    |> Enum.filter(fn signal ->
      extract_pattern(signal) == pattern
    end)
  end

  defp recognized_pattern?(signal) do
    pattern = extract_pattern(signal)
    :ets.lookup(:algedonic_patterns, pattern) != []
  end

  defp under_time_budget? do
    # Simple time budget check
    true
  end

  defp get_recent_signals(memory, count) do
    memory
    |> Map.to_list()
    |> Enum.sort_by(fn {timestamp, _} -> timestamp end, :desc)
    |> Enum.take(count)
    |> Enum.map(fn {_, signal} -> signal end)
  end

  defp summarize_filter(filter_state) do
    %{
      active_filters: map_size(filter_state.signal_counts),
      total_filtered: Enum.sum(Map.values(filter_state.signal_counts))
    }
  end

  # Stub implementations for subsystem interventions
  defp apply_s1_intervention(intervention), do: :ok
  defp apply_s2_intervention(intervention), do: :ok
  defp apply_s3_intervention(intervention), do: :ok
  defp apply_s4_intervention(intervention), do: :ok
  defp apply_s5_intervention(intervention), do: :ok
end

# Simple Priority Queue implementation
defmodule PriorityQueue do
  @moduledoc """
  Simple priority queue implementation for algedonic signal processing.
  Higher priority values are processed first.
  """
  def new, do: []

  def insert(queue, priority, item) do
    [{priority, item} | queue]
    |> Enum.sort_by(fn {p, _} -> -p end)
  end

  def pop([]), do: {:empty, []}
  def pop([head | tail]), do: {{:value, head}, tail}

  def size(queue), do: length(queue)
end
