defmodule AutonomousOpponentV2Core.VSM.DynamicWorker do
  @moduledoc """
  A dynamic worker for VSM systems.
  This GenServer implements the basic behavior for dynamically started VSM components.
  """
  use GenServer
  require Logger

  alias AutonomousOpponentV2Core.VSM.Registry

  def start_link(id) do
    GenServer.start_link(__MODULE__, id, name: via_tuple(id))
  end

  @impl true
  def init(id) do
    Logger.info("Starting VSM SystemWorker for #{elem(id, 1)} #{elem(id, 2)}")
    {:ok, id}
  end

  defp via_tuple({:system, type, id}), do: {:via, Registry, {Registry, {:system, type, id}}}
  defp via_tuple({:subsystem, id}), do: {:via, Registry, {Registry, {:subsystem, id}}}

  def child_spec(id) do
    %{id: id,
      start: {__MODULE__, :start_link, [id]},
      type: :worker,
      restart: :permanent,
      shutdown: 500}
  end
end
