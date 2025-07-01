defmodule AutonomousOpponentV2Web.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      # AutonomousOpponentV2Web.Repo,
      # Start the Telemetry supervisor
      AutonomousOpponentV2Web.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: AutonomousOpponentV2Web.PubSub},
      # Start the Endpoint (http/https)
      AutonomousOpponentV2Web.Endpoint
      # Start a worker by calling: AutonomousOpponentV2Web.Worker.start_link(arg)
      # {AutonomousOpponentV2Web.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AutonomousOpponentV2Web.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
