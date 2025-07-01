defmodule AutonomousOpponentV2.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      AutonomousOpponentV2Web.Telemetry,
      # Start the Ecto repository
      AutonomousOpponentV2.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: AutonomousOpponentV2.PubSub},
      # Start the Endpoint (http/https)
      AutonomousOpponentV2Web.Endpoint,
      # Start the EventBus
      AutonomousOpponentV2.EventBus
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AutonomousOpponentV2.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, new) do
    AutonomousOpponentV2Web.Endpoint.config_change(changed, new)
    :ok
  end
    :ok
  end
end