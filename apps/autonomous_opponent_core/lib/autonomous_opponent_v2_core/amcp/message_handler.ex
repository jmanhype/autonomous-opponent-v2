# This module is conditionally compiled based on AMQP availability
if Code.ensure_loaded?(AMQP) do
  defmodule AutonomousOpponentV2Core.AMCP.MessageHandler do
    @moduledoc """
    Provides an abstraction layer for AMQP message operations with
    comprehensive error handling, retry logic, and circuit breaker integration.
    
    **Wisdom Preservation:** Abstracting message operations enables switching
    between transports, provides consistent error handling, and centralizes
    retry logic. This prevents cascade failures and enables graceful degradation.
    """
    use GenServer
    require Logger
    
    alias AMQP.Basic
    alias AutonomousOpponentV2Core.AMCP.{ConnectionPool, VSMTopology}
    alias AutonomousOpponentV2Core.EventBus
    # alias AutonomousOpponentV2Core.Core.{CircuitBreaker, RateLimiter}
    
    @max_retries 3
    @retry_backoff_base 1_000
    @publish_timeout 5_000
    
    defmodule State do
      @moduledoc false
      defstruct [
        publish_stats: %{success: 0, failure: 0},
        consume_stats: %{success: 0, failure: 0},
        retry_queue: :queue.new(),
        processing_retries: false
      ]
    end
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    @impl true
    def init(_opts) do
      # Schedule periodic retry processing
      Process.send_after(self(), :process_retries, 5_000)
      
      # Subscribe to EventBus for metrics requests
      EventBus.subscribe(:metrics_request)
      
      {:ok, %State{}}
    end
    
    @impl true
    def handle_call({:publish, exchange, routing_key, payload, opts}, from, state) do
      # Check rate limit
      # For now, skip rate limiting until we set up specific AMQP rate limiters
      # TODO: Add AMQP-specific rate limiters in application supervision tree
      case :ok do
        :ok ->
          Task.start(fn ->
            result = do_publish(exchange, routing_key, payload, opts)
            GenServer.reply(from, result)
          end)
          
          {:noreply, state}
          
        {:error, :rate_limit_exceeded} ->
          {:reply, {:error, :rate_limit_exceeded}, state}
      end
    end
    
    @impl true
    def handle_call({:consume, queue, handler_fun, opts}, _from, state) do
      result = setup_consumer(queue, handler_fun, opts)
      {:reply, result, state}
    end
    
    @impl true
    def handle_call(:get_stats, _from, state) do
      stats = %{
        publish: state.publish_stats,
        consume: state.consume_stats,
        retry_queue_size: :queue.len(state.retry_queue)
      }
      {:reply, stats, state}
    end
    
    @impl true
    def handle_info(:process_retries, state) do
      state = if not state.processing_retries and :queue.len(state.retry_queue) > 0 do
        process_retry_queue(state)
      else
        state
      end
      
      Process.send_after(self(), :process_retries, 5_000)
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:event, :metrics_request, _data}, state) do
      EventBus.publish(:metrics_response, %{
        component: :amqp_message_handler,
        stats: %{
          publish: state.publish_stats,
          consume: state.consume_stats,
          retry_queue_size: :queue.len(state.retry_queue)
        }
      })
      
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:publish_result, :success}, state) do
      state = update_in(state.publish_stats.success, &(&1 + 1))
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:publish_result, :failure}, state) do
      state = update_in(state.publish_stats.failure, &(&1 + 1))
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:retry_publish, message}, state) do
      state = update_in(state.retry_queue, &:queue.in(message, &1))
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
      Logger.debug("Consumer registered with tag: #{consumer_tag}")
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
      Logger.warning("Consumer cancelled with tag: #{consumer_tag}")
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
      Logger.debug("Consumer cancel confirmed for tag: #{consumer_tag}")
      {:noreply, state}
    end
    
    @impl true
    def handle_info({:basic_deliver, _payload, meta}, state) do
      Logger.debug("Received message: #{inspect(meta)}")
      # Message delivery is handled by the consumer callback
      {:noreply, state}
    end
    
    # Private functions
    
    defp do_publish(exchange, routing_key, payload, opts, retry_count \\ 0) do
      # TODO: Add circuit breaker with proper name registration
      result = ConnectionPool.with_connection(fn channel ->
        with {:ok, encoded} <- encode_payload(payload),
             :ok <- Basic.publish(
               channel,
               exchange,
               routing_key,
               encoded,
               build_publish_opts(opts)
             ) do
          send(self(), {:publish_result, :success})
          :ok
        end
      end)
      
      case result do
        :ok ->
          :ok
          
        {:error, :circuit_open} ->
          Logger.warning("Circuit breaker open for AMQP publish")
          handle_publish_failure(exchange, routing_key, payload, opts, retry_count, :circuit_open)
          
        {:error, reason} = _error ->
          Logger.error("Failed to publish message: #{inspect(reason)}")
          send(self(), {:publish_result, :failure})
          handle_publish_failure(exchange, routing_key, payload, opts, retry_count, reason)
      end
    end
    
    defp handle_publish_failure(exchange, routing_key, payload, opts, retry_count, reason) do
      if retry_count < @max_retries do
        # Schedule retry with exponential backoff
        backoff = @retry_backoff_base * :math.pow(2, retry_count)
        
        Process.send_after(
          self(),
          {:retry_publish, {exchange, routing_key, payload, opts, retry_count + 1}},
          round(backoff)
        )
        
        {:error, {:retrying, reason}}
      else
        # Max retries exceeded, send to DLQ or EventBus
        EventBus.publish(:amqp_publish_failed, %{
          exchange: exchange,
          routing_key: routing_key,
          payload: payload,
          error: reason,
          retry_count: retry_count
        })
        
        {:error, {:max_retries_exceeded, reason}}
      end
    end
    
    defp setup_consumer(queue, handler_fun, opts) do
      ConnectionPool.with_connection(fn channel ->
          # Wrap handler with error handling and acknowledgment
          wrapped_handler = create_wrapped_handler(channel, handler_fun, opts)
          
          # Set up consumer with QoS
          prefetch_count = Keyword.get(opts, :prefetch_count, 10)
          :ok = Basic.qos(channel, prefetch_count: prefetch_count)
          
          # Start consuming
          case Basic.consume(channel, queue, nil, opts) do
            {:ok, consumer_tag} ->
              # Start consumer process
              {:ok, pid} = start_consumer_process(channel, wrapped_handler, consumer_tag)
              {:ok, %{consumer_tag: consumer_tag, pid: pid}}
              
            {:error, reason} = error ->
              Logger.error("Failed to start consumer: #{inspect(reason)}")
              error
          end
          
      end)
    end
    
    defp create_wrapped_handler(channel, handler_fun, _opts) do
      fn payload, metadata ->
        try do
          # Decode payload if needed
          decoded = case decode_payload(payload) do
            {:ok, decoded} -> decoded
            {:error, _} -> payload
          end
          
          # Call handler directly for now
          # TODO: Add circuit breaker with proper name registration  
          case handler_fun.(decoded, metadata) do
            :ok ->
              # Acknowledge message
              Basic.ack(channel, metadata.delivery_tag)
              send(self(), {:consume_result, :success})
              
            {:error, :retry} ->
              # Requeue for retry
              Basic.reject(channel, metadata.delivery_tag, requeue: true)
              
            {:error, _reason} ->
              # Send to DLQ by rejecting without requeue
              Basic.reject(channel, metadata.delivery_tag, requeue: false)
              send(self(), {:consume_result, :failure})
          end
        rescue
          error ->
            Logger.error("Consumer handler error: #{inspect(error)}")
            # Reject without requeue to send to DLQ
            Basic.reject(channel, metadata.delivery_tag, requeue: false)
            send(self(), {:consume_result, :failure})
        end
      end
    end
    
    defp start_consumer_process(channel, handler, _consumer_tag) do
      Task.start_link(fn ->
        consume_loop(channel, handler)
      end)
    end
    
    defp consume_loop(channel, handler) do
      receive do
        {:basic_deliver, payload, metadata} ->
          handler.(payload, metadata)
          consume_loop(channel, handler)
          
        {:basic_cancel, _} ->
          Logger.info("Consumer cancelled")
          :ok
          
        {:basic_cancel_ok, _} ->
          :ok
      end
    end
    
    defp encode_payload(payload) when is_binary(payload), do: {:ok, payload}
    defp encode_payload(payload) do
      case Jason.encode(payload) do
        {:ok, encoded} -> {:ok, encoded}
        {:error, reason} -> {:error, {:encoding_failed, reason}}
      end
    end
    
    defp decode_payload(payload) when is_binary(payload) do
      case Jason.decode(payload) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, reason} -> {:error, reason}
      end
    end
    
    defp decode_payload(payload) do
      {:ok, payload}
    end
    
    defp build_publish_opts(opts) do
      defaults = [
        persistent: true,
        content_type: "application/json",
        timestamp: DateTime.utc_now() |> DateTime.to_unix()
      ]
      
      Keyword.merge(defaults, opts)
    end
    
    defp process_retry_queue(state) do
      case :queue.out(state.retry_queue) do
        {{:value, {exchange, routing_key, payload, opts, retry_count}}, new_queue} ->
          Task.start(fn ->
            do_publish(exchange, routing_key, payload, opts, retry_count)
          end)
          
          %{state | retry_queue: new_queue}
          
        {:empty, _} ->
          state
      end
    end
    
    # Public API
    
    @doc """
    Publishes a message with automatic retry and error handling.
    """
    def publish(exchange, routing_key, payload, opts \\ []) do
      GenServer.call(__MODULE__, {:publish, exchange, routing_key, payload, opts}, @publish_timeout)
    end
    
    @doc """
    Sets up a consumer with wrapped error handling.
    """
    def consume(queue, handler_fun, opts \\ []) do
      GenServer.call(__MODULE__, {:consume, queue, handler_fun, opts})
    end
    
    @doc """
    Gets current message handling statistics.
    """
    def get_stats do
      GenServer.call(__MODULE__, :get_stats)
    end
    
    @doc """
    Publishes a VSM event through the abstraction layer.
    """
    def publish_vsm_event(subsystem, event_type, payload) do
      VSMTopology.publish_event(subsystem, event_type, payload)
    end
    
    @doc """
    Publishes an algedonic signal through the abstraction layer.
    """
    def publish_algedonic(severity, payload) do
      VSMTopology.publish_algedonic(severity, payload)
    end
  end
else
  # Stub implementation when AMQP is not available
  defmodule AutonomousOpponentV2Core.AMCP.MessageHandler do
    @moduledoc """
    Stub implementation routing messages through EventBus when AMQP is not available.
    """
    use GenServer
    require Logger
    
    alias AutonomousOpponentV2Core.EventBus
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    @impl true
    def init(_opts) do
      Logger.warning("AMQP MessageHandler running in stub mode - using EventBus")
      {:ok, %{stats: %{publish: 0, consume: 0}}}
    end
    
    @impl true
    def handle_call({:publish, _exchange, routing_key, payload, _opts}, _from, state) do
      # Route through EventBus
      EventBus.publish(:"amqp_stub_#{routing_key}", payload)
      state = update_in(state.stats.publish, &(&1 + 1))
      {:reply, :ok, state}
    end
    
    @impl true
    def handle_call({:consume, queue, handler_fun, _opts}, _from, state) do
      # Subscribe to EventBus instead
      event_name = :"amqp_stub_#{queue}"
      EventBus.subscribe(event_name)
      
      # Store handler (in real implementation would process events)
      {:reply, {:ok, %{consumer_tag: event_name, mode: :eventbus}}, state}
    end
    
    @impl true
    def handle_call(:get_stats, _from, state) do
      {:reply, state.stats, state}
    end
    
    def publish(exchange, routing_key, payload, opts \\ []) do
      GenServer.call(__MODULE__, {:publish, exchange, routing_key, payload, opts})
    end
    
    def consume(queue, handler_fun, opts \\ []) do
      GenServer.call(__MODULE__, {:consume, queue, handler_fun, opts})
    end
    
    def get_stats do
      GenServer.call(__MODULE__, :get_stats)
    end
    
    def publish_vsm_event(subsystem, event_type, payload) do
      EventBus.publish(:"vsm_#{subsystem}_#{event_type}", payload)
    end
    
    def publish_algedonic(severity, payload) do
      EventBus.publish(:algedonic_signal, %{severity: severity, payload: payload})
    end
  end
end