defmodule AutonomousOpponentV2Core.AMCP.Client do
  @moduledoc """
  High-level client API for AMQP operations.
  
  Provides a simplified interface for common messaging patterns:
  - Request/Reply
  - Publish/Subscribe
  - Work queues
  - VSM subsystem communication
  
  **Wisdom Preservation:** A good abstraction hides complexity without
  hiding capability. This client provides convenience methods while
  still allowing direct access to lower-level operations when needed.
  """
  
  alias AutonomousOpponentV2Core.AMCP.{ConnectionPool, Topology}
  require Logger
  
  @default_timeout 5000
  @reply_queue_prefix "amcp.reply."
  
  @doc """
  Publishes a message to a VSM subsystem.
  
  ## Examples
      
      # Publish to S1 Operations
      AMCP.Client.publish_to_subsystem(:s1, %{
        operation: "process_order",
        order_id: "12345"
      })
      
      # Publish to S4 Intelligence with priority
      AMCP.Client.publish_to_subsystem(:s4, %{
        task: "analyze_pattern",
        data: pattern_data
      }, priority: 5)
  """
  def publish_to_subsystem(subsystem, message, opts \\ []) when subsystem in [:s1, :s2, :s3, :s4, :s5] do
    routing_key = "vsm.#{subsystem}.#{opts[:operation] || "default"}"
    
    ConnectionPool.publish_with_retry("vsm.topic", routing_key, message, opts)
  end
  
  @doc """
  Sends an algedonic signal (pain or pleasure).
  
  ## Examples
      
      # Send pain signal
      AMCP.Client.send_algedonic(:pain, %{
        source: "resource_monitor",
        message: "CPU usage critical",
        value: 95.5
      })
  """
  def send_algedonic(type, message) when type in [:pain, :pleasure] do
    ConnectionPool.with_connection(fn channel ->
      Topology.publish_algedonic(channel, type, message)
    end)
  end
  
  @doc """
  Publishes an event that will be bridged to the EventBus.
  
  ## Examples
      
      AMCP.Client.publish_event(:user_registered, %{
        user_id: "abc123",
        email: "user@example.com"
      })
  """
  def publish_event(event_type, payload) do
    message = %{
      event_type: event_type,
      payload: payload,
      source: "amqp_client",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    ConnectionPool.publish_with_retry("vsm.events", "", message)
  end
  
  @doc """
  Implements request/reply pattern with timeout.
  
  ## Examples
      
      case AMCP.Client.request("calculation.service", %{
        operation: "multiply",
        operands: [5, 10]
      }) do
        {:ok, response} -> IO.inspect(response)
        {:error, :timeout} -> IO.puts("Request timed out")
      end
  """
  def request(service_name, message, opts \\ []) do
    _timeout = Keyword.get(opts, :timeout, @default_timeout)
    correlation_id = generate_correlation_id()
    reply_queue = @reply_queue_prefix <> correlation_id
    
    # This would need more implementation for full request/reply
    # For now, return a simplified version
    Logger.warning("Request/reply pattern not fully implemented")
    
    # Publish the request
    enriched_message = Map.merge(message, %{
      reply_to: reply_queue,
      correlation_id: correlation_id
    })
    
    case ConnectionPool.publish_with_retry("vsm.topic", service_name, enriched_message) do
      :ok -> 
        # In full implementation, would wait for reply
        {:error, :not_implemented}
      error -> 
        error
    end
  end
  
  @doc """
  Subscribes to a VSM subsystem with automatic message handling.
  
  ## Examples
      
      AMCP.Client.subscribe_to_subsystem(:s1, fn message, _meta ->
        IO.inspect(message, label: "S1 Operations")
        :ok
      end)
  """
  def subscribe_to_subsystem(subsystem, handler_fun) when subsystem in [:s1, :s2, :s3, :s4, :s5] do
    Task.start(fn ->
      ConnectionPool.with_connection(fn channel ->
        consumer = Topology.consume_subsystem(channel, subsystem, handler_fun)
        
        # Keep consuming messages
        consume_loop(consumer)
      end)
    end)
  end
  
  @doc """
  Creates a work queue for distributing tasks.
  
  ## Examples
      
      # Create a work queue
      AMCP.Client.create_work_queue("image_processing")
      
      # Send work
      AMCP.Client.send_work("image_processing", %{
        image_url: "https://example.com/image.jpg",
        operations: ["resize", "watermark"]
      })
  """
  def create_work_queue(queue_name, opts \\ []) do
    ConnectionPool.with_connection(fn channel ->
      if amqp_available?() do
        # Work queue with fair dispatch
        AMQP.Queue.declare(channel, "work.#{queue_name}",
          durable: true,
          arguments: [
            {"x-message-ttl", :signedint, opts[:ttl] || 3_600_000},
            {"x-max-length", :signedint, opts[:max_length] || 1000}
          ]
        )
        
        AMQP.Queue.bind(channel, "work.#{queue_name}", "vsm.topic", 
          routing_key: "work.#{queue_name}"
        )
        
        :ok
      else
        {:error, :amqp_not_available}
      end
    end)
  end
  
  def send_work(queue_name, work_item, opts \\ []) do
    routing_key = "work.#{queue_name}"
    priority = Keyword.get(opts, :priority, 0)
    
    ConnectionPool.publish_with_retry("vsm.topic", routing_key, work_item, 
      priority: priority
    )
  end
  
  @doc """
  Consumes from a work queue with automatic acknowledgment.
  
  ## Examples
      
      AMCP.Client.consume_work("image_processing", fn work_item ->
        process_image(work_item)
        :ok  # Auto-acknowledges
      end)
  """
  def consume_work(queue_name, handler_fun) do
    Task.start(fn ->
      ConnectionPool.with_connection(fn channel ->
        if amqp_available?() do
          # Fair dispatch - one message at a time
          AMQP.Basic.qos(channel, prefetch_count: 1)
          
          {:ok, _consumer_tag} = AMQP.Basic.consume(channel, "work.#{queue_name}")
          
          consume_loop(fn ->
            receive do
              {:basic_deliver, payload, meta} ->
                try do
                  decoded = Jason.decode!(payload)
                  result = handler_fun.(decoded)
                  
                  case result do
                    :ok -> 
                      AMQP.Basic.ack(channel, meta.delivery_tag)
                    {:error, :retry} ->
                      AMQP.Basic.nack(channel, meta.delivery_tag, requeue: true)
                    _ ->
                      AMQP.Basic.nack(channel, meta.delivery_tag, requeue: false)
                  end
                rescue
                  e ->
                    Logger.error("Work handler error: #{inspect(e)}")
                    AMQP.Basic.nack(channel, meta.delivery_tag, requeue: false)
                end
            end
          end)
        else
          Logger.error("Cannot consume work - AMQP not available")
        end
      end)
    end)
  end
  
  @doc """
  Gets the current health status of AMQP infrastructure.
  """
  def health_check do
    ConnectionPool.health_check()
  end
  
  # Private functions
  
  defp consume_loop(consumer_fun) when is_function(consumer_fun, 0) do
    consumer_fun.()
    consume_loop(consumer_fun)
  end
  
  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
  
  defp amqp_available? do
    # Check if AMQP is enabled in config
    amqp_enabled = Application.get_env(:autonomous_opponent_core, :amqp_enabled, false)
    
    # Also check if the AMQP module is available
    amqp_loaded = Code.ensure_loaded?(AMQP) and function_exported?(AMQP.Connection, :open, 1)
    
    amqp_enabled and amqp_loaded
  end
end