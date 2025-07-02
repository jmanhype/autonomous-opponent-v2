defmodule AutonomousOpponentV2Web.BaseTest do
  use ExUnit.Case
  
  test "static_paths returns expected paths" do
    paths = AutonomousOpponentV2Web.static_paths()
    assert is_list(paths)
    assert "assets" in paths
    assert "favicon.ico" in paths
  end
  
  test "router macro is available" do
    assert is_function(&AutonomousOpponentV2Web.router/0)
  end
  
  test "controller macro is available" do
    assert is_function(&AutonomousOpponentV2Web.controller/0)
  end
end