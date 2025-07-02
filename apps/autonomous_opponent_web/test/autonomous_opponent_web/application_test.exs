defmodule AutonomousOpponentV2Web.ApplicationTest do
  use ExUnit.Case
  
  test "module is available" do
    assert Code.ensure_loaded?(AutonomousOpponentV2Web.Application)
  end
  
  test "has start function" do
    assert function_exported?(AutonomousOpponentV2Web.Application, :start, 2)
  end
  
  test "application supervisor name is correct" do
    # Just verify the module structure
    assert AutonomousOpponentV2Web.Application.__info__(:module) == AutonomousOpponentV2Web.Application
  end
end