defmodule AutonomousOpponentV2Core.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      AutonomousOpponentV2Core.Repo,
      # Start the EventBus
      {AutonomousOpponentV2Core.EventBus, name: AutonomousOpponentV2Core.EventBus},
      # Start the Telemetry supervisor
      # AutonomousOpponentV2Core.Telemetry,
      # Start the VSM Supervisor
    ] ++ vsm_children() ++ amqp_children()

    opts = [strategy: :one_for_one, name: AutonomousOpponentV2Core.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Start VSM in all environments including test
  defp vsm_children do
    [AutonomousOpponentV2Core.VSM.Supervisor]
  end

  # Start AMQP supervisor if enabled
  defp amqp_children do
    if Application.get_env(:autonomous_opponent_core, :amqp_enabled, false) do
      [AutonomousOpponentV2Core.AMCP.Supervisor]
    else
      []
    end
  end
end