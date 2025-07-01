defmodule AutonomousOpponentV2Web.SystemEventSocket do
  @moduledoc """
  WebSocket endpoint for streaming raw system events.
  """

  use Phoenix.Socket
  require Logger

  # Channels
  channel("system:events", AutonomousOpponentV2Web.SystemEventChannel)

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
