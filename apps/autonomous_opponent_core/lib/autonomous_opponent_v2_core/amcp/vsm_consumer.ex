defmodule AutonomousOpponentV2Core.AMCP.VSMConsumer do
  @moduledoc """
  VSM Consumer for handling messages from all VSM queues.
  
  This module sets up consumers for each VSM subsystem queue and routes
  messages to the appropriate handlers. It integrates with the EventBus
  to bridge AMQP messages into the internal event system.
  
  **Wisdom Preservation:** Each subsystem consumer maintains its own
  processing logic and variety absorption patterns, allowing the VSM
  to operate as a truly distributed cognitive system.
  """
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.AMCP.ConnectionPool
  alias AutonomousOpponentV2Core.AMCP.Message
  
  @subsystems [:s1, :s2, :s3, :s4, :s5]
  
  defmodule State do
    @moduledoc false
    defstruct [
      consumers: %{},
      channels: %{},
      processing_stats: %{}
    ]
  end
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    state = %State{}
    
    # Start consumers after a short delay to ensure topology is ready
    Process.send_after(self(), :start_consumers, 3_000)
    
    {:ok, state}
  end
  
  @impl true
  def handle_info(:start_consumers, state) do
    case start_all_consumers() do
      {:ok, consumers} ->
        Logger.info("✅ VSM consumers started successfully")
        {:noreply, %{state | consumers: consumers}}
        
      {:error, reason} ->
        Logger.error("Failed to start VSM consumers: #{inspect(reason)}")
        # Retry after backoff
        Process.send_after(self(), :start_consumers, 10_000)
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:basic_consume_ok, %{consumer_tag: tag}}, state) do
    Logger.debug("Consumer registered: #{tag}")
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:basic_cancel, %{consumer_tag: tag}}, state) do
    Logger.warning("Consumer cancelled: #{tag}")
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:basic_cancel_ok, %{consumer_tag: tag}}, state) do
    Logger.debug("Consumer cancel confirmed: #{tag}")
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:basic_deliver, payload, meta}, state) do
    Task.start(fn ->
      handle_message(payload, meta)
    end)
    
    {:noreply, update_stats(state, meta)}
  end
  
  # Private functions
  
  defp start_all_consumers do
    ConnectionPool.with_connection(fn channel ->
        try do
          
          # Start consumers for each subsystem
          consumers = start_subsystem_consumers(channel)
          
          # Start variety channel consumers
          variety_consumers = start_variety_consumers(channel)
          
          # Start algedonic consumer
          algedonic_consumer = start_algedonic_consumer(channel)
          
          # Start command consumers
          command_consumers = start_command_consumers(channel)
          
          all_consumers = Map.merge(consumers, variety_consumers)
                        |> Map.merge(algedonic_consumer)
                        |> Map.merge(command_consumers)
          
          {:ok, all_consumers}
        rescue
          e ->
            Logger.error("Error starting consumers: #{inspect(e)}")
            {:error, e}
        end
    end)
  end
  
  defp start_subsystem_consumers(channel) do
    Enum.reduce(@subsystems, %{}, fn subsystem, acc ->
      queue_name = "vsm.#{subsystem}.operations"
      
      # Handle the actual queue names
      queue_name = case subsystem do
        :s1 -> "vsm.s1.operations"
        :s2 -> "vsm.s2.coordination"
        :s3 -> "vsm.s3.control"
        :s4 -> "vsm.s4.intelligence"
        :s5 -> "vsm.s5.policy"
      end
      
      case setup_consumer(channel, queue_name, subsystem) do
        {:ok, consumer_tag} ->
          Map.put(acc, subsystem, consumer_tag)
          
        {:error, reason} ->
          Logger.error("Failed to setup consumer for #{subsystem}: #{inspect(reason)}")
          acc
      end
    end)
  end
  
  defp start_variety_consumers(channel) do
    variety_channels = [
      {:s1_to_s2, "vsm.channel.s1_to_s2"},
      {:s2_to_s3, "vsm.channel.s2_to_s3"},
      {:s3_to_s4, "vsm.channel.s3_to_s4"},
      {:s4_to_s5, "vsm.channel.s4_to_s5"},
      {:s3_to_s1, "vsm.channel.s3_to_s1"},
      {:s5_to_all, "vsm.channel.s5_to_all"}
    ]
    
    Enum.reduce(variety_channels, %{}, fn {channel_name, queue_name}, acc ->
      case setup_consumer(channel, queue_name, {:variety, channel_name}) do
        {:ok, consumer_tag} ->
          Map.put(acc, channel_name, consumer_tag)
          
        {:error, reason} ->
          Logger.error("Failed to setup variety consumer #{channel_name}: #{inspect(reason)}")
          acc
      end
    end)
  end
  
  defp start_algedonic_consumer(channel) do
    case setup_consumer(channel, "vsm.algedonic.signals", :algedonic) do
      {:ok, consumer_tag} ->
        %{algedonic: consumer_tag}
        
      {:error, reason} ->
        Logger.error("Failed to setup algedonic consumer: #{inspect(reason)}")
        %{}
    end
  end
  
  defp start_command_consumers(channel) do
    # For now, we'll just consume from the control loop command queue
    case setup_consumer(channel, "vsm.s1.commands", {:command, :s1}) do
      {:ok, consumer_tag} ->
        %{s1_commands: consumer_tag}
        
      {:error, reason} ->
        Logger.error("Failed to setup command consumer: #{inspect(reason)}")
        %{}
    end
  end
  
  defp setup_consumer(channel, queue_name, tag) do
    try do
      # Set QoS for fair dispatch
      :ok = AMQP.Basic.qos(channel, prefetch_count: 10)
      
      # Start consuming
      {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue_name, self())
      
      Logger.info("Started consumer for #{queue_name} (#{inspect(tag)})")
      
      {:ok, consumer_tag}
    rescue
      e ->
        {:error, e}
    end
  end
  
  defp handle_message(payload, meta) do
    queue_name = meta.routing_key || "unknown"
    
    try do
      # Decode the message
      decoded = decode_payload(payload)
      
      # Route based on queue/exchange
      route_message(decoded, meta)
      
      # Log successful processing
      Logger.debug("Processed message from #{queue_name}")
    rescue
      e ->
        Logger.error("Error processing message from #{queue_name}: #{inspect(e)}")
    end
  end
  
  defp decode_payload(payload) do
    case Jason.decode(payload) do
      {:ok, data} -> data
      {:error, _} ->
        # Try erlang term format
        try do
          :erlang.binary_to_term(payload)
        rescue
          _ -> payload  # Return raw payload if all decoding fails
        end
    end
  end
  
  defp route_message(message, %{routing_key: routing_key} = meta) do
    # Determine the event type based on routing key
    event_type = determine_event_type(routing_key)
    
    # Add AMQP metadata to the message
    enriched_message = enrich_message(message, meta)
    
    # Publish to EventBus
    EventBus.publish(event_type, enriched_message)
    
    # Special handling for certain message types
    handle_special_messages(event_type, enriched_message)
  end
  
  defp determine_event_type(routing_key) do
    cond do
      String.starts_with?(routing_key, "operations.") -> :s1_operations
      String.starts_with?(routing_key, "coordination.") -> :s2_coordination
      String.starts_with?(routing_key, "control.") -> :s3_control
      String.starts_with?(routing_key, "intelligence.") -> :s4_intelligence
      String.starts_with?(routing_key, "policy.") -> :s5_policy
      String.starts_with?(routing_key, "variety.") -> :variety_flow
      String.starts_with?(routing_key, "algedonic.") -> :algedonic_signal
      String.starts_with?(routing_key, "pain") -> :algedonic_pain
      String.starts_with?(routing_key, "pleasure") -> :algedonic_pleasure
      String.starts_with?(routing_key, "emergency") -> :emergency_algedonic
      true -> String.to_atom(routing_key)
    end
  end
  
  defp enrich_message(message, meta) do
    Map.merge(message, %{
      "_amqp_metadata" => %{
        routing_key: meta.routing_key,
        exchange: meta.exchange,
        timestamp: meta.timestamp || DateTime.utc_now(),
        delivery_tag: meta.delivery_tag,
        redelivered: meta.redelivered
      }
    })
  end
  
  defp handle_special_messages(:algedonic_pain, message) do
    # Priority handling for pain signals
    Logger.warning("🚨 ALGEDONIC PAIN received via AMQP: #{inspect(message)}")
    
    # Could trigger immediate S3 intervention
    EventBus.publish(:s3_intervention_required, message)
  end
  
  defp handle_special_messages(:emergency_algedonic, message) do
    # Emergency bypass - goes directly to all subsystems
    Logger.error("🚨🚨🚨 EMERGENCY ALGEDONIC via AMQP: #{inspect(message)}")
    
    # Broadcast to all subsystems immediately
    Enum.each(@subsystems, fn subsystem ->
      EventBus.publish(:"#{subsystem}_emergency", message)
    end)
  end
  
  defp handle_special_messages(:variety_flow, %{"_amqp_metadata" => %{routing_key: key}} = message) do
    # Route variety flow messages to specific channels
    case extract_variety_channel(key) do
      {:ok, from, to} ->
        EventBus.publish(:"variety_#{from}_to_#{to}", message)
        
      _ ->
        Logger.debug("Unknown variety flow pattern: #{key}")
    end
  end
  
  defp handle_special_messages(_, _), do: :ok
  
  defp extract_variety_channel(routing_key) do
    case Regex.run(~r/variety\.(.+)_to_(.+)\./, routing_key) do
      [_, from, to] -> {:ok, from, to}
      _ -> :error
    end
  end
  
  defp update_stats(state, %{routing_key: key}) do
    stats = Map.update(state.processing_stats, key, 1, &(&1 + 1))
    %{state | processing_stats: stats}
  end
end