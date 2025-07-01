defmodule AutonomousOpponentV2Web.SystemEventChannel do
  @moduledoc """
  Main system event channel - broadcasts ALL system events in real-time.
  """

  use AutonomousOpponentV2Web, :channel

  alias AutonomousOpponentV2.EventBus
  require Logger

  @impl true
  def join("system:events", _payload, socket) do
    EventBus.subscribe("system:*", fn _, _ -> :ok end)
    send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    push(socket, "event", %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      type: "system:connection",
      content: %{
        message: "Connected to raw event stream",
        pid: inspect(self()),
        node: node()
      }
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:event, topic, event}, socket) do
    push(socket, "event", %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      type: topic,
      content: event,
      source: %{
        pid: inspect(self()),
        node: node()
      }
    })

    {:noreply, socket}
  end

  @impl true
  def terminate(reason, _socket) do
    Logger.info("SystemEventChannel terminating: #{inspect(reason)}")
    :ok
  end
end
