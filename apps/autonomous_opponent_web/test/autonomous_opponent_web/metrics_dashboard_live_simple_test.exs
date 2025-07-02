defmodule AutonomousOpponentV2Web.MetricsDashboardLiveSimpleTest do
  use ExUnit.Case
  alias AutonomousOpponentV2Web.MetricsDashboardLive
  
  test "mount returns ok" do
    # Just test that mount doesn't crash
    socket = %Phoenix.LiveView.Socket{
      assigns: %{}
    }
    
    {:ok, _socket} = MetricsDashboardLive.mount(%{}, %{}, socket)
  end
  
  test "handle_info refresh returns noreply" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        metrics: %{},
        dashboard: %{},
        subsystems: []
      }
    }
    
    {:noreply, _socket} = MetricsDashboardLive.handle_info(:refresh, socket)
  end
end