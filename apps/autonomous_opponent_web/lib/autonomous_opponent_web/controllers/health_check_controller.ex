defmodule AutonomousOpponentV2Web.HealthCheckController do
  use AutonomousOpponentV2Web, :controller
  alias AutonomousOpponentV2Web.HealthCheck

  def index(conn, _params) do
    case HealthCheck.check() do
      {:ok, health_data} ->
        conn
        |> put_status(:ok)
        |> json(health_data)
        
      {:error, health_data} ->
        conn
        |> put_status(:service_unavailable)
        |> json(health_data)
    end
  end
end