defmodule AutonomousOpponent.VSM.S1.Supervisor do
  @moduledoc """
  Dynamic supervisor for S1 operational units.
  
  Manages the lifecycle of S1 operations processes, allowing dynamic spawning
  based on variety absorption needs following VSM principles.
  """
  
  use DynamicSupervisor
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end
  
  def start_operational_unit(opts \\ []) do
    spec = {AutonomousOpponent.VSM.S1.Operations, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
  
  def count_operational_units do
    DynamicSupervisor.count_children(__MODULE__)
  end
  
  def list_operational_units do
    DynamicSupervisor.which_children(__MODULE__)
  end
end