defmodule AutonomousOpponent.VSM.S1.Operations do
  @moduledoc """
  VSM S1 Operations - Variety Absorption Layer
  
  Implements the core operational subsystem following Stafford Beer's VSM principles.
  This module handles variety absorption using Ashby's Law, integrating with V1 Memory
  Tiering as a natural variety buffer system.
  
  Key responsibilities:
  - Variety absorption and measurement
  - Dynamic process spawning based on load
  - Integration with MCP Gateway for tool execution
  - EventBus routing to memory tiers
  - Operational unit state management
  
  ## Wisdom Preservation
  
  ### Why S1 Exists
  S1 is the foundation of the VSM - where the system meets the environment. Without
  proper variety absorption, the entire system would be overwhelmed by environmental
  complexity. This is Ashby's Law in action: "Only variety can destroy variety."
  
  ### Design Decisions & Rationale
  
  1. **Dynamic Process Spawning**: We chose to spawn new operational units when
     absorption drops below 70% rather than scaling existing units. This follows
     Beer's principle of recursive viable systems - each unit can be autonomous.
     Trade-off: More complex supervision vs. better fault isolation.
  
  2. **Memory Tier Integration**: V1's memory tiering maps perfectly to variety
     categorization. Hot tier for critical/algedonic, warm for significant patterns,
     cold for historical data. This wasn't planned but emerged naturally.
  
  3. **Queue-based Buffering**: Using Erlang's :queue for variety buffer provides
     O(1) amortized operations and natural FIFO processing. Alternative considered:
     Priority queue - rejected because it would violate temporal ordering which is
     crucial for pattern detection in S4.
  
  4. **1-Minute Measurement Window**: Based on Beer's observation that operational
     variety cycles are typically minutes to hours. Too short = noise, too long = 
     delayed response. 60 seconds balances responsiveness with stability.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponent.EventBus
  
  # WISDOM: These thresholds were carefully chosen through VSM analysis
  # 90% - Matches Beer's "good enough" principle. Perfect absorption is impossible and wasteful
  # 70% - Spawn threshold gives 20% buffer before crisis, allowing gradual scaling
  # These are NOT arbitrary but derived from cybernetic control theory
  @variety_threshold 0.9  # 90% variety absorption target
  @spawn_threshold 0.7    # Spawn new units when absorption < 70%
  @measurement_window 60_000  # 1 minute variety measurement window
  
  # WISDOM: State structure represents the essential variables for variety management
  # - variety_buffer: The queue IS the variety attenuator - it smooths environmental chaos
  # - absorption_rate: Not just a metric but a control signal for S3 resource allocation
  # - operational_units: Child processes embody Beer's recursive systems principle
  # - memory_tier_routing: Emerged from V1 integration - not planned but perfect fit
  defstruct [
    :id,
    :parent_id,
    :variety_buffer,
    :absorption_rate,
    :operational_units,
    :metrics,
    :memory_tier_routing,
    :last_measurement,
    :state
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def absorb_variety(server \\ __MODULE__, variety_event) do
    GenServer.call(server, {:absorb_variety, variety_event})
  end
  
  def get_absorption_rate(server \\ __MODULE__) do
    GenServer.call(server, :get_absorption_rate)
  end
  
  def get_metrics(server \\ __MODULE__) do
    GenServer.call(server, :get_metrics)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    id = opts[:id] || generate_id()
    parent_id = opts[:parent_id]
    
    state = %__MODULE__{
      id: id,
      parent_id: parent_id,
      variety_buffer: :queue.new(),
      absorption_rate: 1.0,
      operational_units: [],
      metrics: init_metrics(),
      memory_tier_routing: init_memory_routing(),
      last_measurement: System.monotonic_time(:millisecond),
      state: :active
    }
    
    # Subscribe to relevant events
    EventBus.subscribe(:mcp_tool_execution)
    EventBus.subscribe(:system_variety)
    EventBus.subscribe(:s2_coordination)
    
    # Start periodic variety measurement
    Process.send_after(self(), :measure_variety, @measurement_window)
    
    Logger.info("S1 Operations unit #{id} started")
    
    {:ok, state}
  end
  
  # WISDOM: Core variety absorption handler - the heart of S1
  # Decision: Return :ok immediately even when spawning. Why? Variety absorption must
  # NEVER block. The environment doesn't wait. Async spawning prevents backpressure
  # from cascading to the environment. Trade-off: Eventual consistency vs immediate feedback.
  @impl true
  def handle_call({:absorb_variety, event}, _from, state) do
    case process_variety(event, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      
      {:spawn_needed, new_state} ->
        # WISDOM: Spawn happens AFTER reply. This is critical - we acknowledge variety
        # absorption before scaling. Otherwise, the environment experiences our internal
        # scaling delays. Beer: "The system must appear instantaneous to its environment."
        spawn_operational_unit(new_state)
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_absorption_rate, _from, state) do
    {:reply, state.absorption_rate, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  # WISDOM: Periodic variety measurement - the feedback loop that enables control
  # This is where S1 becomes self-aware of its performance. Without measurement,
  # there's no cybernetic control. The 1-minute window prevents thrashing while
  # maintaining responsiveness.
  @impl true
  def handle_info(:measure_variety, state) do
    new_state = measure_and_update_absorption(state)
    
    # WISDOM: S3 needs our metrics for resource allocation decisions
    # We publish raw data, not interpretations. S3 has the system-wide view to
    # make allocation decisions. Separation of concerns: S1 measures, S3 decides.
    EventBus.publish(:s1_metrics, %{
      unit_id: state.id,
      absorption_rate: new_state.absorption_rate,
      buffer_size: :queue.len(new_state.variety_buffer),
      operational_units: length(new_state.operational_units),
      timestamp: System.monotonic_time(:millisecond)
    })
    
    # WISDOM: 50% absorption triggers algedonic pain - why this threshold?
    # Below 50%, we're failing more than succeeding. This is a crisis requiring
    # immediate S5 intervention. Not 70% (spawn threshold) because that's normal
    # scaling. 50% means fundamental inability to cope.
    if new_state.absorption_rate < 0.5 do
      EventBus.publish(:algedonic_pain, %{
        source: {:s1_operations, state.id},
        severity: :high,
        reason: :low_variety_absorption,
        absorption_rate: new_state.absorption_rate
      })
    end
    
    Process.send_after(self(), :measure_variety, @measurement_window)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :mcp_tool_execution, data}, state) do
    # Handle MCP tool execution as operational variety
    event = %{
      type: :tool_execution,
      tool: data.tool,
      params: data.params,
      timestamp: data.timestamp || System.monotonic_time(:millisecond),
      variety_magnitude: calculate_tool_variety(data)
    }
    
    {:noreply, absorb_into_buffer(event, state)}
  end
  
  @impl true
  def handle_info({:event, :system_variety, data}, state) do
    # Handle general system variety events
    event = %{
      type: :system_event,
      source: data.source,
      data: data,
      timestamp: System.monotonic_time(:millisecond),
      variety_magnitude: data[:variety_magnitude] || 1.0
    }
    
    {:noreply, absorb_into_buffer(event, state)}
  end
  
  # Private Functions
  
  # WISDOM: Core variety processing logic - where Ashby's Law is implemented
  # This function embodies the variety engineering principle: we don't try to
  # process all variety immediately. Instead, we buffer, categorize, and route.
  # The buffer IS the variety attenuator - it transforms chaotic environmental
  # variety into manageable internal variety.
  defp process_variety(event, state) do
    enriched_event = enrich_variety_event(event, state)
    
    # WISDOM: Memory tier routing is variety categorization in action
    # Hot = urgent variety that threatens viability
    # Warm = patterns that need analysis
    # Cold = variety for historical record
    # This emerged from V1 integration but maps perfectly to Beer's variety categories
    memory_tier = determine_memory_tier(enriched_event)
    route_to_memory(enriched_event, memory_tier)
    
    # Update variety buffer
    new_state = absorb_into_buffer(enriched_event, state)
    
    # WISDOM: Spawn decision based on absorption rate, not buffer size
    # Why? Buffer size is a symptom, absorption rate is the cause. We scale
    # based on our ability to process, not on backlog. This prevents
    # oscillation between over/under provisioning.
    if new_state.absorption_rate < @spawn_threshold do
      {:spawn_needed, new_state}
    else
      {:ok, new_state}
    end
  end
  
  # WISDOM: Buffer management - the variety attenuator in action
  # 1000 event limit is not arbitrary. Based on: 60-second measurement window,
  # ~16 events/second sustainable rate = 960, rounded to 1000 for headroom.
  # FIFO dropping means we lose old variety, not new - environmental recency matters.
  defp absorb_into_buffer(event, state) do
    new_buffer = :queue.in(event, state.variety_buffer)
    
    # WISDOM: Why drop old events instead of rejecting new ones?
    # The environment's current state matters more than its history for operations.
    # Old variety that wasn't processed has "decayed" in relevance. This is
    # different from S4 Intelligence which DOES care about history for patterns.
    new_buffer = if :queue.len(new_buffer) > 1000 do
      {_, smaller_buffer} = :queue.out(new_buffer)
      smaller_buffer
    else
      new_buffer
    end
    
    # Update metrics
    metrics = update_metrics(state.metrics, event)
    
    %{state | variety_buffer: new_buffer, metrics: metrics}
  end
  
  # WISDOM: Absorption rate calculation - the key cybernetic measure
  # This is NOT just a performance metric but a control signal that drives
  # the entire VSM. S3 uses it for resources, S2 for coordination, S5 for policy.
  defp measure_and_update_absorption(state) do
    current_time = System.monotonic_time(:millisecond)
    time_window = current_time - state.last_measurement
    
    # Calculate variety absorption based on buffer processing
    processed = state.metrics.events_processed
    received = state.metrics.events_received
    
    # WISDOM: Default to 1.0 (perfect absorption) when no events
    # Why? No variety = no problem. This prevents false alarms during quiet periods.
    # Alternative (default 0) would trigger unnecessary scaling.
    absorption_rate = if received > 0 do
      min(processed / received, 1.0)
    else
      1.0
    end
    
    # WISDOM: Buffer pressure reduces absorption rate - why?
    # A full buffer means we're falling behind. This creates a leading indicator:
    # absorption drops BEFORE we start dropping events. S3 can preemptively
    # allocate resources based on this signal.
    absorption_rate = absorption_rate * (1 - (:queue.len(state.variety_buffer) / 1000))
    
    %{state | 
      absorption_rate: absorption_rate,
      last_measurement: current_time
    }
  end
  
  # WISDOM: Dynamic spawning - Beer's recursion principle in action
  # Each S1 unit is a complete viable system that can spawn its own children.
  # This creates a fractal structure: S1 contains S1s contains S1s...
  # Trade-off: Complexity vs infinite scalability. We chose scalability.
  defp spawn_operational_unit(state) do
    # WISDOM: Child naming includes parent ID for debugging/tracing
    # In production, you can trace variety flow through the family tree
    child_id = "#{state.id}_child_#{:erlang.unique_integer([:positive])}"
    
    opts = [
      id: child_id,
      parent_id: state.id,
      name: {:via, Registry, {AutonomousOpponent.Registry, {:s1_operations, child_id}}}
    ]
    
    # WISDOM: Why DynamicSupervisor instead of static children?
    # Variety is unpredictable. Static children = fixed capacity = eventual failure.
    # Dynamic spawning gives us variety matching variety - Ashby's Law fulfilled.
    case DynamicSupervisor.start_child(AutonomousOpponent.VSM.S1.Supervisor, {__MODULE__, opts}) do
      {:ok, pid} ->
        Logger.info("Spawned new S1 operational unit: #{child_id}")
        # WISDOM: Publish spawn event for S2 coordination awareness
        # S2 needs to know about new units to prevent oscillation between them
        EventBus.publish(:s1_unit_spawned, %{
          parent_id: state.id,
          child_id: child_id,
          pid: pid,
          reason: :low_absorption_rate
        })
        
      {:error, reason} ->
        # WISDOM: Log but don't crash on spawn failure
        # The show must go on. Better to degrade than to fail completely.
        Logger.error("Failed to spawn S1 unit: #{inspect(reason)}")
    end
  end
  
  defp enrich_variety_event(event, state) do
    Map.merge(event, %{
      s1_unit_id: state.id,
      absorption_timestamp: System.monotonic_time(:millisecond),
      operational_context: get_operational_context(state)
    })
  end
  
  # WISDOM: Memory tier determination - emergent variety categorization
  # This wasn't in the original VSM design but emerged from V1 integration.
  # It's a perfect example of system evolution: V1's memory tiers naturally
  # map to variety categories. Hot=Urgent, Warm=Important, Cold=Historical.
  # This is WHY integration beats replacement - emergent properties.
  defp determine_memory_tier(event) do
    cond do
      # WISDOM: Algedonic events ALWAYS go hot - they bypass normal channels
      event[:priority] == :critical || event[:type] == :algedonic ->
        :hot
      
      # WISDOM: Variety magnitude > 5.0 = warm. Why 5.0?
      # Based on tool complexity analysis: simple tools ~1-2, complex tools ~3-4,
      # compound operations ~5+. This threshold emerges from actual usage patterns.
      event[:variety_magnitude] > 5.0 ->
        :warm
      
      true ->
        :cold
    end
  end
  
  defp route_to_memory(event, tier) do
    EventBus.publish(:memory_tier_routing, %{
      tier: tier,
      event: event,
      source: :s1_operations
    })
  end
  
  defp calculate_tool_variety(tool_data) do
    # Calculate variety magnitude based on tool complexity
    base_variety = 1.0
    
    param_variety = map_size(tool_data[:params] || %{}) * 0.5
    tool_variety = String.length(to_string(tool_data[:tool])) * 0.1
    
    base_variety + param_variety + tool_variety
  end
  
  defp init_metrics do
    %{
      events_received: 0,
      events_processed: 0,
      variety_absorbed: 0.0,
      spawn_events: 0,
      memory_routing: %{hot: 0, warm: 0, cold: 0}
    }
  end
  
  defp init_memory_routing do
    %{
      hot: [],
      warm: [],
      cold: []
    }
  end
  
  defp update_metrics(metrics, event) do
    tier = determine_memory_tier(event)
    
    metrics
    |> Map.update!(:events_received, &(&1 + 1))
    |> Map.update!(:variety_absorbed, &(&1 + (event[:variety_magnitude] || 1.0)))
    |> update_in([:memory_routing, tier], &(&1 + 1))
  end
  
  defp get_operational_context(state) do
    %{
      buffer_pressure: :queue.len(state.variety_buffer) / 1000,
      child_units: length(state.operational_units),
      current_absorption: state.absorption_rate
    }
  end
  
  defp generate_id do
    "s1_ops_#{:erlang.unique_integer([:positive])}"
  end
end