defmodule AutonomousOpponentV2Core.AMCP.ConnectionManager do
  @moduledoc """
  Manages the AMQP connection and channel for the aMCP.
  Ensures a persistent and reliable connection to RabbitMQ.

  **Wisdom Preservation:** Centralizing connection management prevents resource leaks,
  simplifies error handling, and provides a single point of control for RabbitMQ interactions.
  """
  use GenServer
  require Logger

  alias AMQP.Connection
  alias AMQP.Channel
  alias AutonomousOpponentV2Core.AMCP.Topology
  alias Application

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Connecting to RabbitMQ...")
    connection_opts = Application.get_env(:autonomous_opponent_core, :amqp_connection)
    {:ok, connection} = Connection.open(connection_opts)
    {:ok, channel} = Channel.open(connection)

    # Declare topology on startup
    Topology.declare_topology(channel)

    Logger.info("Successfully connected to RabbitMQ and declared topology.")
    {:ok, %{connection: connection, channel: channel}}
  end

  @impl true
  def handle_call(:get_channel, _from, state) do
    {:reply, state.channel, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Closing RabbitMQ connection...")
    Connection.close(state.connection)
    :ok
  end

  @doc """
  Returns the AMQP channel for publishing and consuming messages.
  """
  def get_channel do
    GenServer.call(__MODULE__, :get_channel)
  end
end
