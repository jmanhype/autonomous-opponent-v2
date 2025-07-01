defmodule AutonomousOpponentV2Core.VSM.Registry do
  @moduledoc """
  A Registry for VSM dynamic workers.
  This allows VSM components to be named and looked up dynamically.
  """
  

  def start_link(_opts) do
    Registry.start_link(keys: :unique, name: __MODULE__)
  end

  def child_spec(opts) do
    %{id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500}
  end
end
