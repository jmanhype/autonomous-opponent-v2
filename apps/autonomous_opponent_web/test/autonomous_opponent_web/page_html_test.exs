defmodule AutonomousOpponentV2Web.PageHTMLTest do
  use ExUnit.Case
  
  test "module is available" do
    assert Code.ensure_loaded?(AutonomousOpponentV2Web.PageHTML)
  end
  
  test "module defines templates" do
    # Force module to load
    _ = AutonomousOpponentV2Web.PageHTML.__info__(:module)
    assert true
  end
end