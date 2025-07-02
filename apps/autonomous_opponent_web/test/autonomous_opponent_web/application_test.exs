defmodule AutonomousOpponentV2Web.ApplicationTest do
  use ExUnit.Case
  
  test "module is available" do
    assert Code.ensure_loaded?(AutonomousOpponentV2Web.Application)
  end
  
  test "has start function" do
    assert function_exported?(AutonomousOpponentV2Web.Application, :start, 2)
  end
  
  test "can call config_change" do
    # This is called when configuration changes
    assert :ok = AutonomousOpponentV2Web.Application.config_change([], [], [])
  end
end