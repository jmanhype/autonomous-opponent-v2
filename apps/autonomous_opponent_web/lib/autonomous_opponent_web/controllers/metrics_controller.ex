defmodule AutonomousOpponentV2Web.MetricsController do
  @moduledoc """
  Controller for exposing metrics in Prometheus format.
  This endpoint can be scraped by Prometheus/Grafana for monitoring.
  """
  use AutonomousOpponentV2Web, :controller


  def index(conn, _params) do
    prometheus_text =
      case Process.whereis(AutonomousOpponentV2Core.Core.Metrics) do
        nil ->
          # Return empty metrics if metrics system not running
          "# No metrics available - metrics system not running\n"
        _pid ->
          try do
            AutonomousOpponentV2Core.Core.Metrics.prometheus_format(AutonomousOpponentV2Core.Core.Metrics)
          rescue
            _ -> "# Error retrieving metrics\n"
          end
      end

    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, prometheus_text)
  end
end