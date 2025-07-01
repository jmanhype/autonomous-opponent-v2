defmodule AutonomousOpponentV2Web.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      # Phoenix LiveView metrics
      counter("phoenix_live_view.mount.start"),
      counter("phoenix_live_view.mount.stop"),
      counter("phoenix_live_view.handle_params.start"),
      counter("phoenix_live_view.handle_params.stop"),
      counter("phoenix_live_view.handle_event.start"),
      counter("phoenix_live_view.handle_event.stop"),
      counter("phoenix_live_view.handle_info.start"),
      counter("phoenix_live_view.handle_info.stop"),
      counter("phoenix_live_view.render.start"),
      counter("phoenix_live_view.render.stop"),

      # Phoenix Endpoint metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      last_value("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      # Database metrics
      summary("autonomous_opponent_web.repo.query.total_time",
        unit: {:native, :millisecond}
      ),
      last_value("autonomous_opponent_web.repo.query.total_time",
        unit: {:native, :millisecond}
      )
    ]
  end
end
