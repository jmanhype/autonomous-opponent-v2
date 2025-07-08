defmodule AutonomousOpponentV2Core.VSM.Channels.VarietyChannel do
  @moduledoc """
  The nervous system of the VSM - channels that carry variety between subsystems.
  
  This is NOT just message passing. This is variety engineering:
  - Amplification: Enhancing control signals
  - Attenuation: Reducing environmental noise
  - Transformation: Converting between subsystem languages
  
  Without these channels, subsystems are isolated islands.
  With them, we have a living, breathing viable system.
  """
  
  use GenServer
  require Logger
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Clock
  
  # Channel types define variety transformation rules
  @channel_types %{
    s1_to_s2: %{
      source: :s1_operations,
      target: :s2_coordination,
      transformation: :aggregate_variety,
      capacity: 1000  # Maximum variety units per second
    },
    s2_to_s3: %{
      source: :s2_coordination,
      target: :s3_control,
      transformation: :coordinate_to_control,
      capacity: 500
    },
    s3_to_s4: %{
      source: :s3_control,
      target: :s4_intelligence,
      transformation: :audit_to_learning,
      capacity: 200
    },
    s4_to_s5: %{
      source: :s4_intelligence,
      target: :s5_policy,
      transformation: :intelligence_to_policy,
      capacity: 100
    },
    s3_to_s1: %{  # THE CRITICAL CONTROL LOOP
      source: :s3_control,
      target: :s1_operations,
      transformation: :control_commands,
      capacity: 1000
    },
    s5_to_all: %{  # POLICY BROADCAST
      source: :s5_policy,
      target: :all_subsystems,
      transformation: :policy_constraints,
      capacity: 50
    }
  }
  
  defstruct [
    :channel_type,
    :buffer,
    :capacity,
    :current_flow,
    :transformation_fn,
    :metrics
  ]
  
  # Client API
  
  def start_link(opts) do
    channel_type = Keyword.fetch!(opts, :channel_type)
    GenServer.start_link(__MODULE__, {channel_type, opts}, name: channel_name(channel_type))
  end
  
  def transmit(channel_type, variety_data) do
    channel = channel_name(channel_type)
    
    case Process.whereis(channel) do
      nil ->
        # Channel not ready yet, log and continue
        Logger.debug("Variety channel #{channel_type} not ready, skipping transmission")
        :ok
        
      pid when is_pid(pid) ->
        try do
          GenServer.call(channel, {:transmit, variety_data})
        catch
          :exit, _ ->
            Logger.warning("Variety channel #{channel_type} unavailable")
            :ok
        end
    end
  end
  
  def get_flow_metrics(channel_type) do
    GenServer.call(channel_name(channel_type), :get_metrics)
  end
  
  def get_channel_stats(channel_type) do
    GenServer.call(channel_name(channel_type), :get_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init({channel_type, _opts}) do
    config = Map.fetch!(@channel_types, channel_type)
    
    # Subscribe to source events
    EventBus.subscribe(config.source)
    
    state = %__MODULE__{
      channel_type: channel_type,
      buffer: :queue.new(),
      capacity: config.capacity,
      current_flow: 0,
      transformation_fn: config.transformation,
      metrics: %{
        total_transmitted: 0,
        total_dropped: 0,
        total_transformed: 0,
        average_latency: 0
      }
    }
    
    # Start flow monitoring
    Process.send_after(self(), :monitor_flow, 1000)
    
    Logger.info("VSM Channel #{channel_type} established: #{config.source} → #{config.target}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:transmit, variety_data}, _from, state) do
    start_time = System.monotonic_time()
    
    # Atomic capacity check and increment to prevent race conditions
    if state.current_flow < state.capacity do
      new_flow = state.current_flow + 1
      
      # Create HLC event for variety transmission ordering
      transmission_event = case safe_create_event(:variety_channel, :variety_transmission, %{
        channel: state.channel_type,
        data: variety_data,
        flow_sequence: new_flow
      }) do
        {:ok, event} -> event
        {:error, _reason} ->
          # Fallback event structure when HLC is unavailable
          timestamp = System.system_time(:millisecond)
          %{
            id: "variety_fallback_#{timestamp}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}",
            subsystem: :variety_channel,
            type: :variety_transmission,
            data: %{
              channel: state.channel_type,
              data: variety_data,
              flow_sequence: new_flow
            },
            timestamp: %{physical: timestamp, logical: 0, node_id: "fallback"},
            created_at: DateTime.to_iso8601(DateTime.from_unix!(timestamp, :millisecond))
          }
      end
      
      # Transform variety according to channel rules with HLC timestamp
      transformed = apply_transformation(variety_data, state.transformation_fn, transmission_event)
      
      # Emit to target with causally-ordered data
      config = Map.fetch!(@channel_types, state.channel_type)
      EventBus.publish(config.target, transformed)
      
      # Update metrics
      latency = System.monotonic_time() - start_time
      new_metrics = update_metrics(state.metrics, :success, latency)
      
      {:reply, :ok, %{state | 
        current_flow: new_flow,  # Use atomically incremented value
        metrics: new_metrics
      }}
    else
      # Capacity exceeded - attenuate with HLC timestamp for debugging
      drop_event = case safe_create_event(:variety_channel, :variety_dropped, %{
        channel: state.channel_type,
        reason: :capacity_exceeded,
        current_flow: state.current_flow,
        capacity: state.capacity
      }) do
        {:ok, event} -> event
        {:error, _reason} ->
          # Fallback event for drop tracking
          timestamp = System.system_time(:millisecond)
          %{
            id: "drop_fallback_#{timestamp}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}",
            subsystem: :variety_channel,
            type: :variety_dropped,
            data: %{
              channel: state.channel_type,
              reason: :capacity_exceeded,
              current_flow: state.current_flow,
              capacity: state.capacity
            },
            timestamp: %{physical: timestamp, logical: 0, node_id: "fallback"},
            created_at: DateTime.to_iso8601(DateTime.from_unix!(timestamp, :millisecond))
          }
      end
      
      Logger.warning("Variety channel capacity exceeded", 
        channel: state.channel_type, event_id: drop_event.id)
      
      new_metrics = update_metrics(state.metrics, :dropped, 0)
      {:reply, {:error, :capacity_exceeded}, %{state | metrics: new_metrics}}
    end
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      channel_type: state.channel_type,
      capacity: state.capacity,
      current_flow: state.current_flow,
      metrics: state.metrics,
      health: calculate_channel_health(state)
    }
    {:reply, stats, state}
  end
  
  @impl true
  # Handle new HLC event format from EventBus
  def handle_info({:event_bus_hlc, event}, state) do
    # Extract event data and forward to existing handler
    handle_info({:event, event.type, event.data}, state)
  end
  
  @impl true
  def handle_info({:event, _source, variety_data}, state) do
    # Handle async variety flow from EventBus
    handle_call({:transmit, variety_data}, nil, state)
    |> elem(2)  # Extract new state
    |> then(&{:noreply, &1})
  end
  
  @impl true
  def handle_info(:monitor_flow, state) do
    # Reset flow counter every second
    Process.send_after(self(), :monitor_flow, 1000)
    {:noreply, %{state | current_flow: 0}}
  end
  
  # Private Functions
  
  # Safe HLC helper with retry and exponential backoff
  defp safe_create_event(subsystem, event_type, data, retries \\ 3) do
    try do
      Clock.create_event(subsystem, event_type, data)
    catch
      :exit, {:noproc, _} when retries > 0 ->
        # HLC process not available yet, wait with exponential backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 50)
        Logger.debug("HLC not available for variety event, retrying in #{backoff_ms}ms (#{retries} retries left)")
        Process.sleep(backoff_ms)
        safe_create_event(subsystem, event_type, data, retries - 1)
      
      :exit, {:timeout, _} when retries > 0 ->
        # Timeout, retry with exponential backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 100)
        Logger.debug("HLC timeout for variety event, retrying in #{backoff_ms}ms (#{retries} retries left)")
        Process.sleep(backoff_ms)
        safe_create_event(subsystem, event_type, data, retries - 1)
      
      :exit, {:killed, _} when retries > 0 ->
        # Process was killed, retry with backoff
        backoff_ms = round(:math.pow(2, 4 - retries) * 75)
        Logger.debug("HLC process killed for variety event, retrying in #{backoff_ms}ms (#{retries} retries left)")
        Process.sleep(backoff_ms)
        safe_create_event(subsystem, event_type, data, retries - 1)
      
      :exit, reason ->
        Logger.warning("HLC unavailable for variety event after all retries: #{inspect(reason)}")
        {:error, {:hlc_unavailable, reason}}
      
      error ->
        Logger.error("Unexpected error calling HLC for variety event: #{inspect(error)}")
        {:error, {:hlc_error, error}}
    end
  end
  
  defp channel_name(channel_type) do
    :"vsm_channel_#{channel_type}"
  end
  
  defp apply_transformation(data, :aggregate_variety, event) do
    # S1 → S2: Aggregate operational variety into coordination patterns
    %{
      variety_type: :operational,
      unit_id: Map.get(data, :unit_id, :unknown_unit),  # Preserve unit_id for S2
      patterns: extract_patterns(data),
      volume: calculate_variety_volume(data),
      hlc_timestamp: event.timestamp,
      transmission_id: event.id
    }
  end
  
  # Legacy function for backward compatibility
  defp apply_transformation(data, transformation_type) do
    event = get_or_create_transformation_event(transformation_type)
    apply_transformation(data, transformation_type, event)
  end
  
  # Fallback 2-arg variants that create HLC events
  defp apply_transformation(data, :coordinate_to_control) do
    event = get_or_create_transformation_event(:coordinate_to_control)
    apply_transformation(data, :coordinate_to_control, event)
  end
  
  defp apply_transformation(data, :audit_to_learning) do
    event = get_or_create_transformation_event(:audit_to_learning)
    apply_transformation(data, :audit_to_learning, event)
  end
  
  defp apply_transformation(data, :intelligence_to_policy) do
    event = get_or_create_transformation_event(:intelligence_to_policy)
    apply_transformation(data, :intelligence_to_policy, event)
  end
  
  defp apply_transformation(data, :control_commands) do
    event = get_or_create_transformation_event(:control_commands)
    apply_transformation(data, :control_commands, event)
  end
  
  defp apply_transformation(data, :policy_constraints) do
    event = get_or_create_transformation_event(:policy_constraints)
    apply_transformation(data, :policy_constraints, event)
  end
  
  defp apply_transformation(data, :coordinate_to_control, event) do
    # S2 → S3: Convert coordination into control decisions
    %{
      variety_type: :coordinated,
      resource_requirements: data.patterns |> analyze_resource_needs(),
      intervention_needed: detect_intervention_need(data),
      hlc_timestamp: event.timestamp,
      transmission_id: event.id
    }
  end
  
  defp apply_transformation(data, :audit_to_learning, event) do
    # S3 → S4: Transform audit data into learning material
    %{
      variety_type: :audit,
      decisions_made: data,
      outcomes: nil,  # To be filled by S4
      patterns_to_learn: extract_learning_patterns(data),
      hlc_timestamp: event.timestamp,
      transmission_id: event.id
    }
  end
  
  defp apply_transformation(data, :intelligence_to_policy, event) do
    # S4 → S5: Convert intelligence into policy recommendations
    %{
      variety_type: :intelligence,
      environmental_model: data,
      policy_violations: detect_policy_violations(data),
      recommended_adjustments: generate_policy_recommendations(data),
      hlc_timestamp: event.timestamp,
      transmission_id: event.id
    }
  end
  
  defp apply_transformation(data, :control_commands, event) do
    # S3 → S1: Direct control commands (CLOSES THE LOOP!)
    %{
      variety_type: :control,
      commands: data.commands,
      priority: :high,
      bypass_buffers: data[:emergency] || false,
      unit_id: Map.get(data, :unit_id, :default_unit),  # Add unit_id for S2 coordination
      hlc_timestamp: event.timestamp,
      transmission_id: event.id
    }
  end
  
  defp apply_transformation(data, :policy_constraints, event) do
    # S5 → All: Policy constraints that shape all subsystems
    %{
      variety_type: :policy,
      constraints: Map.get(data, :constraints, %{}),
      values: Map.get(data, :values, %{}),
      enforcement: Map.get(data, :enforcement, :mandatory),
      environmental_model: Map.get(data, :environmental_model),
      policy_violations: Map.get(data, :policy_violations, []),
      recommended_adjustments: Map.get(data, :recommended_adjustments, []),
      hlc_timestamp: event.timestamp,
      transmission_id: event.id
    }
  end
  
  defp extract_patterns(data) do
    # Real pattern extraction would use your HNSW/Quantizer
    # This is simplified for now
    [data]
  end
  
  defp calculate_variety_volume(_data) do
    # Ashby's variety calculation
    # V = log2(number of possible states)
    1
  end
  
  defp analyze_resource_needs(_patterns) do
    %{cpu: :medium, memory: :low, io: :high}
  end
  
  defp detect_intervention_need(data) do
    data[:volume] > 100
  end
  
  defp extract_learning_patterns(data) do
    [data]
  end
  
  defp detect_policy_violations(_data) do
    []
  end
  
  defp generate_policy_recommendations(_data) do
    []
  end
  
  defp update_metrics(metrics, :success, latency) do
    %{metrics |
      total_transmitted: metrics.total_transmitted + 1,
      total_transformed: metrics.total_transformed + 1,
      average_latency: calculate_moving_average(metrics.average_latency, latency)
    }
  end
  
  defp update_metrics(metrics, :dropped, _latency) do
    %{metrics | total_dropped: metrics.total_dropped + 1}
  end
  
  defp calculate_moving_average(current, new_value) do
    # Simple moving average
    (current * 0.9) + (new_value * 0.1)
  end
  
  defp calculate_channel_health(state) do
    # Calculate channel health based on metrics
    drop_rate = if state.metrics.total_transmitted > 0 do
      state.metrics.total_dropped / state.metrics.total_transmitted
    else
      0
    end
    
    capacity_utilization = state.current_flow / state.capacity
    
    # Health decreases with drop rate and high utilization
    base_health = 1.0 - drop_rate
    utilization_penalty = if capacity_utilization > 0.8, do: 0.2, else: 0
    
    max(0.0, base_health - utilization_penalty)
  end
  
  # Safe HLC helper for getting transformation events
  defp get_or_create_transformation_event(transformation_type) do
    case safe_create_event(:variety_channel, :variety_transformation, %{type: transformation_type}) do
      {:ok, event} -> event
      {:error, _reason} ->
        # Fallback event for transformations
        timestamp = System.system_time(:millisecond)
        %{
          id: "transform_fallback_#{timestamp}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}",
          subsystem: :variety_channel,
          type: :variety_transformation,
          data: %{type: transformation_type},
          timestamp: %{physical: timestamp, logical: 0, node_id: "fallback"},
          created_at: DateTime.to_iso8601(DateTime.from_unix!(timestamp, :millisecond))
        }
    end
  end
end