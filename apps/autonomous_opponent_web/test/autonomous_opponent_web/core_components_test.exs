defmodule AutonomousOpponentV2Web.CoreComponentsTest do
  use ExUnit.Case
  import Phoenix.LiveViewTest
  
  test "core_components module is available" do
    assert Code.ensure_loaded?(AutonomousOpponentV2Web.CoreComponents)
  end
  
  test "has expected component functions" do
    # Just check that it's a module with some functions
    assert length(AutonomousOpponentV2Web.CoreComponents.__info__(:functions)) > 0
  end
end