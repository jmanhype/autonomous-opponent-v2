defmodule AutonomousOpponentV2Web.HealthCheckTest do
  use ExUnit.Case
  alias AutonomousOpponentV2Web.HealthCheck

  test "returns healthy status when all checks pass" do
    assert {:ok, result} = HealthCheck.check()
    assert result.status == "healthy"
    assert is_map(result.checks)
  end

  test "includes system info" do
    assert {:ok, result} = HealthCheck.check()
    assert Map.has_key?(result, :system)
    assert Map.has_key?(result.system, :memory)
    assert Map.has_key?(result.system, :process_count)
  end
end