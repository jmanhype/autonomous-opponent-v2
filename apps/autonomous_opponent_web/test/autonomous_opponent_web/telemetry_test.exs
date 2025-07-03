defmodule AutonomousOpponentV2Web.TelemetryTest do
  use ExUnit.Case
  alias AutonomousOpponentV2Web.Telemetry

  test "module is available" do
    assert Code.ensure_loaded?(AutonomousOpponentV2Web.Telemetry)
  end

  test "metrics are defined" do
    metrics = Telemetry.metrics()
    assert is_list(metrics)
    assert length(metrics) > 0
  end
end