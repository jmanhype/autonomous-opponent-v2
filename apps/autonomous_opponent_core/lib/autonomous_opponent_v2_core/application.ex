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
    ] ++ amqp_children() ++ vsm_children()

    opts = [strategy: :one_for_one, name: AutonomousOpponentV2Core.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Start VSM in all environments including test
  defp vsm_children do
    [AutonomousOpponentV2Core.VSM.Supervisor]
  end

  # Start AMQP services if enabled
  defp amqp_children do
    if Application.get_env(:autonomous_opponent_core, :amqp_enabled, true) do
      [
        # Connection pool must start first
        AutonomousOpponentV2Core.AMCP.ConnectionPool,
        # Then the connection manager for backward compatibility
        AutonomousOpponentV2Core.AMCP.ConnectionManager,
        # Health monitoring
        AutonomousOpponentV2Core.AMCP.HealthMonitor,
        # Router if it exists
        # AutonomousOpponentV2Core.AMCP.Router
      ]
    else
      []
    end
  end
end