# This module is conditionally compiled based on AMQP availability
if Code.ensure_loaded?(AMQP) do
  defmodule AutonomousOpponentV2Core.AMCP.Router do
    @moduledoc """
    The AMCP Router within the Cybernetic Core.
    Routes messages between EventBus, VSM subsystems, and AMQP with comprehensive
    error handling and resilience patterns.

    **Wisdom Preservation:** This router centralizes message flow, making it easier
    to observe, debug, and evolve the communication patterns of the system. It acts
    as a critical control point for information flow and provides seamless fallback
    to EventBus when AMQP is unavailable.
    """
    use GenServer
    require Logger

    alias AutonomousOpponentV2Core.AMCP.{MessageHandler, Message}
    alias AutonomousOpponentV2Core.EventBus
    import Ecto.Changeset

    defmodule State do
      @moduledoc false
      defstruct [
        consumers: %{},
        event_subscriptions: [],
        routing_stats: %{routed: 0, failed: 0}
      ]
    end

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(_opts) do
      Logger.info("Starting AMCP Router with resilient message handling...")
      
      state = %State{}
      
      # Set up EventBus subscriptions for bidirectional routing
      state = setup_event_subscriptions(state)
      
      # Set up core consumers after a delay to ensure topology is ready
      Process.send_after(self(), :setup_consumers, 3_000)
      
      Logger.info("AMCP Router initialized")
      {:ok, state}
    end

    @impl true
    def handle_info(:setup_consumers, state) do
      state = setup_amqp_consumers(state)
      {:noreply, state}
    end

    @impl true
    def handle_info({:event, event_name, data}, state) do
      # Route EventBus events to AMQP when appropriate
      state = route_event_to_amqp(event_name, data, state)
      {:noreply, state}
    end

    @impl true
    def handle_call({:publish, message_map}, _from, state) do
      # Ensure the message conforms to the AMCP.Message schema
      changeset = Message.changeset(%Message{}, message_map)

      case apply_action(changeset, :insert) do
        {:ok, message} ->
          result = MessageHandler.publish("amcp.events", "", message, [])
          
          state = if result == :ok do
            update_in(state.routing_stats.routed, &(&1 + 1))
          else
            update_in(state.routing_stats.failed, &(&1 + 1))
          end
          
          {:reply, result, state}
          
        {:error, changeset} ->
          Logger.error("Invalid Web Gateway message: #{inspect(changeset.errors)}")
          state = update_in(state.routing_stats.failed, &(&1 + 1))
          {:reply, {:error, :invalid_message}, state}
      end
    end

    @impl true
    def handle_call(:get_stats, _from, state) do
      stats = Map.merge(state.routing_stats, %{
        consumers: map_size(state.consumers),
        event_subscriptions: length(state.event_subscriptions)
      })
      {:reply, stats, state}
    end

    # Private functions

    defp setup_event_subscriptions(state) do
      # Subscribe to key EventBus events for AMQP routing
      events = [
        :vsm_event,
        :algedonic_signal,
        :system_command,
        :telemetry_data
      ]
      
      Enum.each(events, &EventBus.subscribe/1)
      
      %{state | event_subscriptions: events}
    end

    defp setup_amqp_consumers(state) do
      # Set up consumers for core queues
      consumers = [
        {"vsm.s3.events", &handle_vsm_message/2},
        {"vsm.algedonic.signals", &handle_algedonic_message/2},
        {"amcp.queue.core_processor", &handle_core_message/2}
      ]
      
      new_consumers = Enum.reduce(consumers, state.consumers, fn {queue, handler}, acc ->
        case MessageHandler.consume(queue, handler, [prefetch_count: 10]) do
          {:ok, consumer_info} ->
            Logger.info("Started consumer for queue: #{queue}")
            Map.put(acc, queue, consumer_info)
            
          {:error, reason} ->
            Logger.error("Failed to start consumer for #{queue}: #{inspect(reason)}")
            acc
        end
      end)
      
      %{state | consumers: new_consumers}
    end

    defp route_event_to_amqp(:vsm_event, %{subsystem: subsystem, type: type} = data, state) do
      # Route VSM events to appropriate AMQP exchanges
      case MessageHandler.publish_vsm_event(subsystem, type, data) do
        :ok ->
          update_in(state.routing_stats.routed, &(&1 + 1))
        _ ->
          update_in(state.routing_stats.failed, &(&1 + 1))
      end
    end

    defp route_event_to_amqp(:algedonic_signal, %{severity: severity} = data, state) do
      # Route algedonic signals with priority
      case MessageHandler.publish_algedonic(severity, data) do
        :ok ->
          update_in(state.routing_stats.routed, &(&1 + 1))
        _ ->
          update_in(state.routing_stats.failed, &(&1 + 1))
      end
    end

    defp route_event_to_amqp(_event_name, _data, state), do: state

    # Message handlers

    defp handle_core_message(payload, metadata) do
      Logger.debug("Processing core message: #{inspect(payload)}")
      
      # Route to EventBus for processing
      EventBus.publish(:amqp_core_message, %{
        payload: payload,
        metadata: metadata,
        timestamp: DateTime.utc_now()
      })
      
      :ok
    end

    defp handle_vsm_message(payload, _metadata) do
      Logger.debug("Processing VSM message: #{inspect(payload)}")
      
      # Extract subsystem and route appropriately
      case payload do
        %{"subsystem" => subsystem, "event_type" => event_type} ->
          EventBus.publish(:"vsm_#{subsystem}_#{event_type}", payload)
          :ok
          
        _ ->
          Logger.warning("Invalid VSM message format: #{inspect(payload)}")
          {:error, :invalid_format}
      end
    end

    defp handle_algedonic_message(payload, metadata) do
      Logger.info("Processing algedonic signal: #{inspect(payload)}")
      
      # High-priority routing to EventBus
      EventBus.publish(:algedonic_received, %{
        signal: payload,
        metadata: metadata,
        received_at: DateTime.utc_now()
      })
      
      :ok
    end

    # Public API

    @doc """
    Publishes a Web Gateway message through the router.
    """
    def publish_message(message_map) do
      GenServer.call(__MODULE__, {:publish, message_map})
    end

    @doc """
    Gets current routing statistics.
    """
    def get_stats do
      GenServer.call(__MODULE__, :get_stats)
    end
  end
else
  # Stub implementation when AMQP is not available
  defmodule AutonomousOpponentV2Core.AMCP.Router do
    @moduledoc """
    Stub implementation of AMCP Router when AMQP is not available.
    Routes all messages through EventBus.
    """
    use GenServer
    require Logger

    alias AutonomousOpponentV2Core.EventBus
    alias AutonomousOpponentV2Core.AMCP.Message
    import Ecto.Changeset

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(_opts) do
      Logger.warning("AMCP Router running in stub mode - using EventBus only")
      {:ok, %{stats: %{routed: 0, failed: 0}}}
    end

    @impl true
    def handle_call({:publish, message_map}, _from, state) do
      changeset = Message.changeset(%Message{}, message_map)

      case apply_action(changeset, :insert) do
        {:ok, message} ->
          EventBus.publish(:amcp_message, message)
          state = update_in(state.stats.routed, &(&1 + 1))
          {:reply, :ok, state}
          
        {:error, changeset} ->
          Logger.error("Invalid Web Gateway message: #{inspect(changeset.errors)}")
          state = update_in(state.stats.failed, &(&1 + 1))
          {:reply, {:error, :invalid_message}, state}
      end
    end

    @impl true
    def handle_call(:get_stats, _from, state) do
      {:reply, state.stats, state}
    end

    def publish_message(message_map) do
      GenServer.call(__MODULE__, {:publish, message_map})
    end

    def get_stats do
      GenServer.call(__MODULE__, :get_stats)
    end
  end
end
