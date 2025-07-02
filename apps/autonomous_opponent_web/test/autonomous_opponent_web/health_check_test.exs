defmodule AutonomousOpponentV2Web.HealthCheckTest do
  use ExUnit.Case
  alias AutonomousOpponentV2Web.HealthCheck

  test "returns error when server not running" do
    # When the endpoint is not started, it should return error
    assert {:error, result} = HealthCheck.check()
    assert result.status == "unhealthy"
  end

  test "health check structure is correct" do
    # Even when failing, the structure should be correct
    {:error, result} = HealthCheck.check()
    assert Map.has_key?(result, :status)
    assert Map.has_key?(result, :checks)
    assert Map.has_key?(result, :system)
  end
end