defmodule AutonomousOpponentV2Web.EndpointTest do
  use ExUnit.Case
  
  test "config_change returns ok" do
    assert :ok = AutonomousOpponentV2Web.Endpoint.config_change([], [])
  end
end