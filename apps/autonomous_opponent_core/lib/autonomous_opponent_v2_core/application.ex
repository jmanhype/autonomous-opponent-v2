defmodule AutonomousOpponentV2Core.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Ensure AMQP application is started before we check for it
    ensure_amqp_started()
    
    children = [
      # Start the Ecto repository
      AutonomousOpponentV2Core.Repo,
      # Start the EventBus
      {AutonomousOpponentV2Core.EventBus, name: AutonomousOpponentV2Core.EventBus},
      # Start core infrastructure services
      {AutonomousOpponentV2Core.Core.CircuitBreaker, name: AutonomousOpponentV2Core.Core.CircuitBreaker},
      {AutonomousOpponentV2Core.Core.RateLimiter, name: AutonomousOpponentV2Core.Core.RateLimiter},
      # Start the Telemetry supervisor
      # AutonomousOpponentV2Core.Telemetry,
      # Start Security services (Task 7)
      AutonomousOpponentV2Core.Security.Supervisor,
      # Start MCP Gateway (Task 8)
      AutonomousOpponentV2Core.MCP.Gateway,
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
    if amqp_enabled?() do
      [
        # AMQP Supervisor manages all AMQP components
        AutonomousOpponentV2Core.AMCP.Supervisor
      ]
    else
      []
    end
  end
  
  defp ensure_amqp_started do
    if amqp_enabled?() do
      case Application.ensure_all_started(:amqp) do
        {:ok, _apps} ->
          :ok
        {:error, reason} ->
          Logger.warning("Failed to start AMQP application: #{inspect(reason)}")
      end
    end
  end
  
  defp amqp_enabled? do
    case Application.get_env(:autonomous_opponent_core, :amqp_enabled) do
      nil -> System.get_env("AMQP_ENABLED", "true") == "true"
      false -> false
      true -> true
      value when is_binary(value) -> value == "true"
      _ -> true
    end
  end
end