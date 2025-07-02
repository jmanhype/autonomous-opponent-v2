defmodule AutonomousOpponentV2Web.CoreComponentsBasicTest do
  use ExUnit.Case
  import Phoenix.Component
  alias AutonomousOpponentV2Web.CoreComponents
  
  test "flash component renders" do
    assigns = %{
      flash: %{"info" => "Test message"},
      kind: :info,
      title: "Info",
      class: nil,
      inner_block: []
    }
    
    # Just test that it doesn't crash
    _ = CoreComponents.flash(assigns)
    assert true
  end
  
  test "flash_group component renders" do
    assigns = %{
      flash: %{"info" => "Test message"},
      kind: :info,
      title: "Info",
      class: nil,
      inner_block: []
    }
    
    # Just test that it doesn't crash
    _ = CoreComponents.flash_group(assigns)
    assert true
  end
end