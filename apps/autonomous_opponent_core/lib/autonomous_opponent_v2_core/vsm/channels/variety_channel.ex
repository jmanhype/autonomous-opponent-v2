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
    
    # Check capacity
    if state.current_flow < state.capacity do
      # Transform variety according to channel rules
      transformed = apply_transformation(variety_data, state.transformation_fn)
      
      # Emit to target
      config = Map.fetch!(@channel_types, state.channel_type)
      EventBus.publish(config.target, transformed)
      
      # Update metrics
      latency = System.monotonic_time() - start_time
      new_metrics = update_metrics(state.metrics, :success, latency)
      
      {:reply, :ok, %{state | 
        current_flow: state.current_flow + 1,
        metrics: new_metrics
      }}
    else
      # Capacity exceeded - attenuate
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
  
  defp channel_name(channel_type) do
    :"vsm_channel_#{channel_type}"
  end
  
  defp apply_transformation(data, :aggregate_variety) do
    # S1 → S2: Aggregate operational variety into coordination patterns
    %{
      variety_type: :operational,
      patterns: extract_patterns(data),
      volume: calculate_variety_volume(data),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp apply_transformation(data, :coordinate_to_control) do
    # S2 → S3: Convert coordination into control decisions
    %{
      variety_type: :coordinated,
      resource_requirements: data.patterns |> analyze_resource_needs(),
      intervention_needed: detect_intervention_need(data),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp apply_transformation(data, :audit_to_learning) do
    # S3 → S4: Transform audit data into learning material
    %{
      variety_type: :audit,
      decisions_made: data,
      outcomes: nil,  # To be filled by S4
      patterns_to_learn: extract_learning_patterns(data),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp apply_transformation(data, :intelligence_to_policy) do
    # S4 → S5: Convert intelligence into policy recommendations
    %{
      variety_type: :intelligence,
      environmental_model: data,
      policy_violations: detect_policy_violations(data),
      recommended_adjustments: generate_policy_recommendations(data),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp apply_transformation(data, :control_commands) do
    # S3 → S1: Direct control commands (CLOSES THE LOOP!)
    %{
      variety_type: :control,
      commands: data.commands,
      priority: :high,
      bypass_buffers: data[:emergency] || false,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp apply_transformation(data, :policy_constraints) do
    # S5 → All: Policy constraints that shape all subsystems
    %{
      variety_type: :policy,
      constraints: data.constraints,
      values: data.values,
      enforcement: :mandatory,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp extract_patterns(data) do
    # Real pattern extraction would use your HNSW/Quantizer
    # This is simplified for now
    [data]
  end
  
  defp calculate_variety_volume(data) do
    # Ashby's variety calculation
    # V = log2(number of possible states)
    1
  end
  
  defp analyze_resource_needs(patterns) do
    %{cpu: :medium, memory: :low, io: :high}
  end
  
  defp detect_intervention_need(data) do
    data[:volume] > 100
  end
  
  defp extract_learning_patterns(data) do
    [data]
  end
  
  defp detect_policy_violations(data) do
    []
  end
  
  defp generate_policy_recommendations(data) do
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
end