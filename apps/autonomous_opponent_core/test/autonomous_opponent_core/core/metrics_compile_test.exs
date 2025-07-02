defmodule AutonomousOpponentV2Core.Core.MetricsCompileTest do
  use ExUnit.Case

  test "Metrics module compiles" do
    assert Code.ensure_loaded?(AutonomousOpponentV2Core.Core.Metrics)
  end
end
