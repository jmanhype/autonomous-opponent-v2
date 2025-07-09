defmodule AutonomousOpponentV2Core.EventBus.OrderedDeliverySupervisor do
  @moduledoc """
  Supervisor for OrderedDelivery processes.
  
  Each subscriber that opts into ordered delivery gets its own OrderedDelivery
  process supervised here. This ensures fault tolerance - if an OrderedDelivery
  process crashes, it can be restarted without affecting other subscribers.
  """
  
  use DynamicSupervisor
  require Logger
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    Logger.info("OrderedDeliverySupervisor starting")
    
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 60
    )
  end
end