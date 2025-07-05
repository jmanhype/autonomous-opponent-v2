defmodule AutonomousOpponentV2Core.AMCP.Topology do
  @moduledoc """
  Defines the RabbitMQ topology for VSM (Viable System Model) communication.
  
  Implements a sophisticated routing topology that supports:
  - VSM subsystem communication (S1-S5)
  - Algedonic signaling for rapid alerts
  - Event broadcasting with topic-based routing
  - Dead Letter Queues (DLQ) for resilience
  - Priority queues for critical messages
  
  **Wisdom Preservation:** The VSM requires specific communication patterns:
  - S1 (Operations) needs high-throughput, low-latency queues
  - S2 (Coordination) requires reliable ordering
  - S3* (Control) needs priority handling
  - S4 (Intelligence) benefits from topic routing
  - S5 (Policy) requires durable, auditable messaging
  - Algedonic channels bypass normal hierarchy for urgent signals
  """
  require Logger

  # Exchange definitions for VSM architecture
  @vsm_exchange "vsm.topic"              # Main topic exchange for VSM routing
  @event_exchange "vsm.events"           # Fanout for system-wide events
  @algedonic_exchange "vsm.algedonic"    # Direct exchange for pain/pleasure signals
  @command_exchange "vsm.commands"       # Topic exchange for control commands
  @dlx_exchange "vsm.dlx"                # Dead Letter Exchange

  # Queue prefixes
  @queue_prefix "vsm."
  @dlq_prefix "vsm.dlq."
  @priority_queue_suffix ".priority"

  @doc """
  Declares the complete VSM topology including all exchanges, queues, and bindings.
  """
  def declare_topology(channel) do
    # Declare all exchanges
    declare_exchanges(channel)
    
    # Declare VSM subsystem queues
    declare_vsm_subsystems(channel)
    
    # Declare algedonic channels
    declare_algedonic_channels(channel)
    
    # Declare event bus integration
    declare_event_bus_bridge(channel)
    
    Logger.info("VSM topology declaration complete")
    :ok
  rescue
    e ->
      Logger.error("Failed to declare topology: #{inspect(e)}")
      {:error, e}
  end

  defp declare_exchanges(channel) do
    if amqp_available?() do
      # Main VSM topic exchange for flexible routing
      AMQP.Exchange.declare(channel, @vsm_exchange, :topic, 
        durable: true,
        arguments: [{"alternate-exchange", :longstr, @dlx_exchange}]
      )
      Logger.info("Declared VSM topic exchange: #{@vsm_exchange}")
      
      # Event fanout exchange
      AMQP.Exchange.declare(channel, @event_exchange, :fanout, durable: true)
      Logger.info("Declared event fanout exchange: #{@event_exchange}")
      
      # Algedonic direct exchange for urgent signals
      AMQP.Exchange.declare(channel, @algedonic_exchange, :direct, 
        durable: true,
        arguments: [{"x-message-ttl", :signedint, 300_000}]  # 5 min TTL
      )
      Logger.info("Declared algedonic exchange: #{@algedonic_exchange}")
      
      # Command exchange for control directives
      AMQP.Exchange.declare(channel, @command_exchange, :topic, durable: true)
      Logger.info("Declared command exchange: #{@command_exchange}")
      
      # Dead Letter Exchange
      AMQP.Exchange.declare(channel, @dlx_exchange, :fanout, durable: true)
      Logger.info("Declared DLX: #{@dlx_exchange}")
    else
      Logger.warning("AMQP not available - exchanges not declared")
    end
  end

  defp declare_vsm_subsystems(channel) do
    # S1: Operations - High throughput
    declare_subsystem_queue(channel, "s1.operations", 
      routing_keys: ["operations.*", "vsm.s1.*"],
      message_ttl: 300_000,  # 5 minutes
      max_length: 10_000
    )
    
    # S2: Coordination - Reliable ordering
    declare_subsystem_queue(channel, "s2.coordination",
      routing_keys: ["coordination.*", "vsm.s2.*"],
      arguments: [{"x-single-active-consumer", :bool, true}]
    )
    
    # S3*: Control - Priority handling
    declare_priority_queue(channel, "s3.control",
      routing_keys: ["control.*", "vsm.s3.*", "vsm.s3star.*"],
      max_priority: 10
    )
    
    # S4: Intelligence - Topic routing for analysis
    declare_subsystem_queue(channel, "s4.intelligence",
      routing_keys: ["intelligence.*", "vsm.s4.*", "analysis.*"],
      message_ttl: 3_600_000  # 1 hour for analysis tasks
    )
    
    # S5: Policy - Durable audit trail
    declare_subsystem_queue(channel, "s5.policy",
      routing_keys: ["policy.*", "vsm.s5.*", "governance.*"],
      arguments: [{"x-queue-mode", :longstr, "lazy"}]  # Optimize for durability
    )
  end

  defp declare_subsystem_queue(channel, name, opts) do
    queue_name = @queue_prefix <> name
    dlq_name = @dlq_prefix <> name
    
    if amqp_available?() do
      # Declare DLQ first
      AMQP.Queue.declare(channel, dlq_name, durable: true)
      AMQP.Queue.bind(channel, dlq_name, @dlx_exchange)
      
      # Build queue arguments
      base_args = [
        {"x-dead-letter-exchange", :longstr, @dlx_exchange}
      ]
      
      ttl_args = if ttl = opts[:message_ttl] do
        [{"x-message-ttl", :signedint, ttl} | base_args]
      else
        base_args
      end
      
      length_args = if max = opts[:max_length] do
        [{"x-max-length", :signedint, max} | ttl_args]
      else
        ttl_args
      end
      
      final_args = length_args ++ (opts[:arguments] || [])
      
      # Declare main queue
      AMQP.Queue.declare(channel, queue_name, 
        durable: true,
        arguments: final_args
      )
      
      # Bind to topic exchange with routing keys
      Enum.each(opts[:routing_keys] || [], fn key ->
        AMQP.Queue.bind(channel, queue_name, @vsm_exchange, routing_key: key)
        Logger.debug("Bound #{queue_name} to #{@vsm_exchange} with key: #{key}")
      end)
      
      # Also bind to events fanout
      AMQP.Queue.bind(channel, queue_name, @event_exchange)
      
      Logger.info("Declared VSM queue: #{queue_name}")
    else
      Logger.warning("Cannot declare queue #{name} - AMQP not available")
    end
  end

  defp declare_priority_queue(channel, name, opts) do
    queue_name = @queue_prefix <> name <> @priority_queue_suffix
    
    if amqp_available?() do
      args = [
        {"x-max-priority", :byte, opts[:max_priority] || 10},
        {"x-dead-letter-exchange", :longstr, @dlx_exchange}
      ]
      
      AMQP.Queue.declare(channel, queue_name, durable: true, arguments: args)
      
      # Bind with routing keys
      Enum.each(opts[:routing_keys] || [], fn key ->
        AMQP.Queue.bind(channel, queue_name, @vsm_exchange, routing_key: key)
      end)
      
      Logger.info("Declared priority queue: #{queue_name}")
    end
  end

  defp declare_algedonic_channels(channel) do
    if amqp_available?() do
      # Pain channel - highest priority
      AMQP.Queue.declare(channel, "vsm.algedonic.pain", 
        durable: true,
        arguments: [
          {"x-max-priority", :byte, 255},
          {"x-message-ttl", :signedint, 60_000}  # 1 minute expiry
        ]
      )
      AMQP.Queue.bind(channel, "vsm.algedonic.pain", @algedonic_exchange, routing_key: "pain")
      
      # Pleasure channel - positive feedback
      AMQP.Queue.declare(channel, "vsm.algedonic.pleasure",
        durable: true,
        arguments: [{"x-max-priority", :byte, 100}]
      )
      AMQP.Queue.bind(channel, "vsm.algedonic.pleasure", @algedonic_exchange, routing_key: "pleasure")
      
      Logger.info("Declared algedonic channels")
    end
  end

  defp declare_event_bus_bridge(channel) do
    # Queue to bridge AMQP events to internal EventBus
    if amqp_available?() do
      AMQP.Queue.declare(channel, "vsm.eventbus.bridge", durable: true)
      AMQP.Queue.bind(channel, "vsm.eventbus.bridge", @event_exchange)
      Logger.info("Declared EventBus bridge queue")
    end
  end

  @doc """
  Publishes a message to the VSM topic exchange with appropriate routing.
  """
  def publish_message(channel, message, routing_key, opts \\ []) do
    exchange = opts[:exchange] || @vsm_exchange
    
    if amqp_available?() do
      # Add VSM metadata
      enriched_message = Map.merge(message, %{
        vsm_timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        vsm_version: "2.0"
      })
      
      publish_opts = [
        persistent: true,
        content_type: "application/json",
        timestamp: :os.system_time(:millisecond)
      ]
      
      # Add priority if specified
      publish_opts = if priority = opts[:priority] do
        Keyword.put(publish_opts, :priority, priority)
      else
        publish_opts
      end
      
      AMQP.Basic.publish(
        channel, 
        exchange, 
        routing_key,
        Jason.encode!(enriched_message),
        publish_opts
      )
      
      Logger.debug("Published to #{exchange}/#{routing_key}: #{inspect(enriched_message)}")
      :ok
    else
      Logger.warning("Cannot publish - AMQP not available")
      {:error, :amqp_not_available}
    end
  rescue
    e ->
      Logger.error("Publish failed: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Publishes an algedonic signal (pain or pleasure) for immediate attention.
  """
  def publish_algedonic(channel, type, message) when type in [:pain, :pleasure] do
    publish_message(channel, message, Atom.to_string(type), 
      exchange: @algedonic_exchange,
      priority: if(type == :pain, do: 255, else: 100)
    )
  end

  @doc """
  Sets up a consumer for a VSM subsystem queue.
  """
  def consume_subsystem(channel, subsystem, consumer_fun) when subsystem in [:s1, :s2, :s3, :s4, :s5] do
    queue_name = case subsystem do
      :s1 -> "vsm.s1.operations"
      :s2 -> "vsm.s2.coordination"
      :s3 -> "vsm.s3.control.priority"
      :s4 -> "vsm.s4.intelligence"
      :s5 -> "vsm.s5.policy"
    end
    
    consume_queue(channel, queue_name, consumer_fun)
  end

  defp consume_queue(channel, queue_name, consumer_fun) do
    if amqp_available?() do
      # Set QoS for fair dispatch
      AMQP.Basic.qos(channel, prefetch_count: 1)
      
      {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue_name)
      
      # Return a function to process messages
      fn ->
        receive do
          {:basic_deliver, payload, meta} ->
            try do
              decoded = Jason.decode!(payload)
              result = consumer_fun.(decoded, meta)
              
              case result do
                :ok -> 
                  AMQP.Basic.ack(channel, meta.delivery_tag)
                {:error, :requeue} ->
                  AMQP.Basic.nack(channel, meta.delivery_tag, requeue: true)
                {:error, _} ->
                  AMQP.Basic.nack(channel, meta.delivery_tag, requeue: false)
              end
            rescue
              e ->
                Logger.error("Consumer error: #{inspect(e)}")
                AMQP.Basic.nack(channel, meta.delivery_tag, requeue: false)
            end
        end
      end
    else
      fn -> {:error, :amqp_not_available} end
    end
  end

  defp amqp_available? do
    # Check if AMQP is enabled in config or environment
    amqp_enabled = case Application.get_env(:autonomous_opponent_core, :amqp_enabled) do
      nil -> System.get_env("AMQP_ENABLED", "true") == "true"
      false -> false
      true -> true
      value when is_binary(value) -> value == "true"
      _ -> true
    end
    
    # Also check if the AMQP module is available
    amqp_loaded = Code.ensure_loaded?(AMQP) and 
      (function_exported?(AMQP.Connection, :open, 0) or 
       function_exported?(AMQP.Connection, :open, 1) or 
       function_exported?(AMQP.Connection, :open, 2))
    
    amqp_enabled and amqp_loaded
  end
end
