defmodule AutonomousOpponentV2Core.AMCP.Topology do
  @moduledoc """
  Defines the RabbitMQ topology for the Advanced Model Context Protocol (aMCP).
  This includes exchanges, queues, and bindings, with a focus on resilience via DLQs.

  **Wisdom Preservation:** Explicitly defining the messaging topology ensures that
  the communication channels are well-understood, auditable, and resilient to failures.
  DLQs are a critical defense against message loss and system instability.
  """
  require Logger
  alias AMQP.{Exchange, Queue, Basic}

  @exchange "amcp.events"
  @dlx_exchange "amcp.events.dlx"
  @queue_prefix "amcp.queue."
  @dlq_queue_prefix "amcp.dlq."

  @doc """
  Declares the necessary RabbitMQ exchanges, queues, and bindings.
  """
  def declare_topology(channel) do
    # Declare main exchange for aMCP events
    Exchange.declare(channel, @exchange, :fanout, durable: true)
    Logger.info("Declared fanout exchange: #{@exchange}")

    # Declare Dead Letter Exchange (DLX)
    Exchange.declare(channel, @dlx_exchange, :fanout, durable: true)
    Logger.info("Declared DLX exchange: #{@dlx_exchange}")

    # Example: Declare a queue for a specific service with DLQ setup
    declare_service_queue(channel, "core_processor")

    :ok
  end

  @doc """
  Declares a service-specific queue and its corresponding Dead Letter Queue (DLQ).
  """
  def declare_service_queue(channel, service_name) do
    queue_name = @queue_prefix <> service_name
    dlq_name = @dlq_queue_prefix <> service_name

    # Declare DLQ
    Queue.declare(channel, dlq_name, durable: true)
    Logger.info("Declared DLQ: #{dlq_name}")
    Queue.bind(channel, dlq_name, @dlx_exchange)
    Logger.info("Bound DLQ #{dlq_name} to DLX #{@dlx_exchange}")

    # Declare main queue with dead-lettering arguments
    Queue.declare(channel, queue_name, durable: true, arguments: [
      {"x-dead-letter-exchange", :longstr, @dlx_exchange},
      {"x-dead-letter-routing-key", :longstr, service_name} # Optional: route to DLQ with original routing key
    ])
    Logger.info("Declared queue: #{queue_name} with DLX arguments")

    # Bind main queue to the main exchange
    Queue.bind(channel, queue_name, @exchange)
    Logger.info("Bound queue #{queue_name} to exchange #{@exchange}")

    :ok
  end

  @doc """
  Publishes an AMCP message to the main exchange.
  """
  def publish_message(channel, message, routing_key \\ "") do
    Basic.publish(channel, @exchange, routing_key, Jason.encode!(message), persistent: true)
    Logger.debug("Published message to #{@exchange} with routing key '#{routing_key}': #{inspect(message)}")
    :ok
  end

  @doc """
  Consumes messages from a specific queue.
  """
  def consume_messages(channel, queue_name, consumer_fun) do
    {:ok, _consumer_tag} = Basic.consume(channel, queue_name)
    
    # Return a function that can be used to handle messages
    fn ->
      receive do
        {:basic_deliver, payload, meta} ->
          Logger.debug("Received message from #{queue_name}: #{inspect(payload)}")
          consumer_fun.(payload)
          Basic.ack(channel, meta.delivery_tag)
      end
    end
  end
end
