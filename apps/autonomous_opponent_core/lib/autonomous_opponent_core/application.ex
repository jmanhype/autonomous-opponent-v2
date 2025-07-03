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
      # Start the VSM Registry (must be started before VSM Supervisor)
      AutonomousOpponentV2Core.VSM.Registry,
      # Start the VSM Supervisor, which dynamically manages VSM components
      AutonomousOpponentV2Core.VSM.Supervisor
      # AMQP temporarily disabled - uncomment when library supports OTP 27+
      # AutonomousOpponentV2Core.AMCP.ConnectionManager,
      # AutonomousOpponentV2Core.AMCP.Router
      # Add your core application children here
    ]

    opts = [strategy: :one_for_one, name: AutonomousOpponentV2Core.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
