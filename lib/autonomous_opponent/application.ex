defmodule AutonomousOpponent.Application do
  @moduledoc """
  Main application supervisor for the Autonomous Opponent V2 system.

  This supervisor manages all VSM subsystems and core components following
  Stafford Beer's Viable System Model principles.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Autonomous Opponent V2 Application")

    # Define child processes
    children = [
      # Core Infrastructure
      {Registry, keys: :unique, name: AutonomousOpponent.Registry},

      # EventBus for system-wide communication
      AutonomousOpponent.EventBus,

      # Circuit Breaker for fault tolerance
      {AutonomousOpponent.Core.CircuitBreaker, name: AutonomousOpponent.Core.CircuitBreaker},

      # VSM Components - Complete implementation
      # Start the VSM supervisor which manages all subsystems
      AutonomousOpponent.VSM.Supervisor
    ]

    # Supervisor options
    opts = [
      strategy: :one_for_one,
      name: AutonomousOpponent.Supervisor,
      max_restarts: 3,
      max_seconds: 5
    ]

    # Start the supervisor
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("Autonomous Opponent V2 Application started successfully")
        publish_startup_event()
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start Autonomous Opponent V2: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping Autonomous Opponent V2 Application")
    publish_shutdown_event()
    :ok
  end

  defp publish_startup_event do
    AutonomousOpponent.EventBus.publish(:system_startup, %{
      timestamp: System.monotonic_time(:millisecond),
      vsm_version: "2.0.0",
      phase: "phase_1_implementation"
    })
  end

  defp publish_shutdown_event do
    AutonomousOpponent.EventBus.publish(:system_shutdown, %{
      timestamp: System.monotonic_time(:millisecond),
      reason: :normal
    })
  end
end
