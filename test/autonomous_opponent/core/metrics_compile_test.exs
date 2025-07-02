defmodule AutonomousOpponent.Core.MetricsCompileTest do
  use ExUnit.Case

  test "Metrics module compiles" do
    assert Code.ensure_loaded?(AutonomousOpponent.Core.Metrics)
  end
end