defmodule AutonomousOpponentV2Core.AMCP.Router do
  @moduledoc """
  The AMCP Router within the Cybernetic Core.
  This GenServer is responsible for routing messages between the core application
  and the RabbitMQ message broker, adhering to the aMCP specification.

  **Wisdom Preservation:** This router centralizes message flow, making it easier
  to observe, debug, and evolve the communication patterns of the system. It acts
  as a critical control point for the flow of information.
  """
  use GenServer
  require Logger

  alias AutonomousOpponentV2Core.AMCP.{ConnectionManager, Message, Topology}
  import Ecto.Changeset

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting AMCP Router...")
    channel = ConnectionManager.get_channel()

    # Start consuming messages from a designated queue (e.g., for core processing)
    Topology.consume_messages(channel, "amcp.queue.core_processor", &handle_incoming_message/1)

    Logger.info("AMCP Router started and consuming messages.")
    {:ok, %{channel: channel}}
  end

  @doc """
  Publishes an AMCP message to the RabbitMQ broker.
  """
  def publish_message(message_map) do
    GenServer.call(__MODULE__, {:publish, message_map})
  end

  @impl true
  def handle_call({:publish, message_map}, _from, state) do
    # Ensure the message conforms to the AMCP.Message schema
    changeset = Message.changeset(%Message{}, message_map)

    case apply_action(changeset, :insert) do
      {:ok, message} ->
        Topology.publish_message(state.channel, message)
        {:reply, :ok, state}
      {:error, changeset} ->
        Logger.error("Failed to publish AMCP message due to validation errors: #{inspect(changeset.errors)}")
        {:reply, {:error, :invalid_message}, state}
    end
  end

  # Internal function to handle messages consumed from RabbitMQ
  defp handle_incoming_message(message_payload) do
    # Decode the message payload (assuming JSON)
    case Jason.decode(message_payload.payload) do
      {:ok, decoded_message} ->
        Logger.info("Received and decoded AMCP message: #{inspect(decoded_message)}")
        # Here, you would dispatch the message to appropriate handlers
        # based on message.type or other fields.
        # For now, just log it.
        :ok
      {:error, e} ->
        Logger.error("Failed to decode AMCP message payload: #{inspect(e)}")
        :nack # Negative acknowledgment, message will be re-queued or sent to DLQ
    end
  end
end
