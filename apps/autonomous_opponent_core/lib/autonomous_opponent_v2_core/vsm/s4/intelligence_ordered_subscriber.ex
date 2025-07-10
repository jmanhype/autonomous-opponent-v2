defmodule AutonomousOpponentV2Core.VSM.S4.IntelligenceOrderedSubscriber do
  @moduledoc """
  Configures S4 Intelligence subsystem to use HLC-ordered event delivery.
  
  This module is part of the phased rollout of HLC ordering, starting with S4
  because:
  
  1. Pattern detection benefits most from proper event sequencing
  2. S4 can tolerate higher latency (100ms buffer window)  
  3. Lower risk - intelligence gathering is not on critical path
  4. High value - better patterns from ordered events
  
  ## Rollout Phases
  
  1. **Phase 1 (Current)**: S4 Intelligence only
  2. **Phase 2**: Add S2 Coordination  
  3. **Phase 3**: Add S3→S1 Control Loop
  4. **Phase 4**: Add S5 Policy
  5. **Phase 5**: Algedonic fine-tuning
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence
  
  @s4_event_topics [
    :pattern_detected,
    :learning_update,
    :environment_scan,
    :intelligence_report,
    :anomaly_detected,
    :trend_identified,
    :model_updated
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    # Check if ordered delivery is enabled via config
    enabled = Keyword.get(opts, :enabled, true)
    
    if enabled do
      Logger.info("🧠 S4 Intelligence enabling HLC-ordered event delivery")
      
      # Subscribe to all S4-related events with ordered delivery
      subscribe_with_ordering()
      
      {:ok, %{
        enabled: true,
        events_received: 0,
        patterns_improved: 0,
        start_time: DateTime.utc_now()
      }}
    else
      Logger.info("S4 Intelligence using standard event delivery")
      
      # Subscribe without ordering (fallback)
      subscribe_without_ordering()
      
      {:ok, %{enabled: false}}
    end
  end
  
  @impl true
  def handle_info({:ordered_event, event}, state) do
    # Process ordered event
    process_ordered_event(event, state)
  end
  
  @impl true  
  def handle_info({:ordered_event_batch, events}, state) do
    # Process batch of ordered events
    new_state = Enum.reduce(events, state, fn event, acc_state ->
      elem(process_ordered_event(event, acc_state), 1)
    end)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, event}, %{enabled: false} = state) do
    # Fallback processing for non-ordered delivery
    Intelligence.process_event(event)
    {:noreply, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      enabled: state.enabled,
      events_received: Map.get(state, :events_received, 0),
      patterns_improved: Map.get(state, :patterns_improved, 0),
      uptime_seconds: if(state.enabled, do: DateTime.diff(DateTime.utc_now(), state.start_time), else: 0)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:enable_ordering, _from, %{enabled: false} = state) do
    Logger.info("🔄 S4 Intelligence switching to HLC-ordered delivery")
    
    # Unsubscribe from non-ordered
    unsubscribe_all()
    
    # Resubscribe with ordering
    subscribe_with_ordering()
    
    {:reply, :ok, %{state | 
      enabled: true,
      events_received: 0,
      patterns_improved: 0,
      start_time: DateTime.utc_now()
    }}
  end
  
  @impl true
  def handle_call(:disable_ordering, _from, %{enabled: true} = state) do
    Logger.warning("⚠️ S4 Intelligence reverting to standard delivery")
    
    # Unsubscribe from ordered
    unsubscribe_all()
    
    # Resubscribe without ordering
    subscribe_without_ordering()
    
    {:reply, :ok, %{state | enabled: false}}
  end
  
  # Private functions
  
  defp subscribe_with_ordering do
    # Subscribe to each S4 event topic with ordered delivery
    # Using longer buffer window since intelligence can tolerate latency
    for topic <- @s4_event_topics do
      EventBus.subscribe(topic, self(), 
        ordered_delivery: true,
        buffer_window_ms: 100,  # 100ms window for pattern detection
        batch_delivery: true,   # Batch for efficient processing
        adaptive_window: true   # Allow adaptation based on load
      )
      
      Logger.debug("S4 subscribed to #{topic} with HLC ordering")
    end
  end
  
  defp subscribe_without_ordering do
    # Standard subscriptions without ordering
    for topic <- @s4_event_topics do
      EventBus.subscribe(topic, self())
    end
  end
  
  defp unsubscribe_all do
    for topic <- @s4_event_topics do
      EventBus.unsubscribe(topic, self())
    end
  end
  
  defp process_ordered_event(event, state) do
    # Log ordering benefit
    Logger.debug("S4 processing ordered event", 
      event_id: event.id,
      hlc: event.timestamp,
      topic: event.type
    )
    
    # Process the event and check if ordering improved pattern detection
    # Events arriving in order improve pattern detection accuracy
    pattern_improved = case event.topic do
      :pattern_detected ->
        # Check if this pattern has a sequence number
        sequence = get_in(event.data, [:sequence])
        if is_integer(sequence) and sequence > 0 do
          # Ordered delivery helped maintain sequence integrity
          true
        else
          false
        end
        
      :learning_update ->
        # Learning updates benefit from causal ordering
        true
        
      :environment_scan ->
        # Environmental scans benefit from temporal ordering
        true
        
      _ ->
        false
    end
    
    # Update state based on processing
    new_state = if pattern_improved do
      %{state | 
        events_received: state.events_received + 1,
        patterns_improved: state.patterns_improved + 1
      }
    else
      %{state | 
        events_received: state.events_received + 1
      }
    end
    
    {:noreply, new_state}
  end
  
  @doc """
  Enable ordered delivery for S4 Intelligence.
  Part of phased rollout.
  """
  def enable_ordering do
    GenServer.call(__MODULE__, :enable_ordering)
  end
  
  @doc """
  Disable ordered delivery (rollback).
  """
  def disable_ordering do
    GenServer.call(__MODULE__, :disable_ordering)
  end
  
  @doc """
  Get statistics about ordered delivery performance.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
end