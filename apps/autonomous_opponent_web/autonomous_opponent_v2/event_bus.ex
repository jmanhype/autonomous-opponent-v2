defmodule AutonomousOpponentV2.EventBus do
  @moduledoc """
  A simple event bus for local event distribution.
  """

  use GenServer
  require Logger

  alias AutonomousOpponentV2.EventBus.Registry

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def publish(topic, data, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:publish, topic, data, metadata})
  end

  def subscribe(topic_pattern, handler) when is_function(handler, 2) do
    GenServer.call(__MODULE__, {:subscribe, topic_pattern, handler})
  end

  def unsubscribe(topic_pattern, handler) when is_function(handler, 2) do
    GenServer.call(__MODULE__, {:unsubscribe, topic_pattern, handler})
  end

  @impl true
  def init(_opts) do
    Registry.start_link([])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:publish, topic, data, metadata}, state) do
    event = %{
      topic: topic,
      data: data,
      metadata: metadata,
      id: UUID.uuid4(),
      timestamp: DateTime.utc_now()
    }

    Task.start(fn ->
      handlers = Registry.get_handlers(event.topic)
      for handler <- handlers do
        try do
          handler.(event.topic, event.data)
        rescue
          e -> Logger.error("Event handler failed: #{inspect(e)}")
        end
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:subscribe, topic_pattern, handler}, _from, state) do
    Registry.subscribe(topic_pattern, handler)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unsubscribe, topic_pattern, handler}, _from, state) do
    Registry.unsubscribe(topic_pattern, handler)
    {:reply, :ok, state}
  end
end
