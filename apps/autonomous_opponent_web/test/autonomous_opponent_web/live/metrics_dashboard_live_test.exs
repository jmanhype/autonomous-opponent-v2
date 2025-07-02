defmodule AutonomousOpponentV2Web.MetricsDashboardLiveTest do
  use AutonomousOpponentV2Web.ConnCase
  import Phoenix.LiveViewTest

  @tag :skip
  test "renders metrics dashboard", %{conn: conn} do
    # Skip this test until Floki is properly configured
    {:ok, _view, html} = live(conn, "/metrics/dashboard")
    assert html =~ "VSM Metrics Dashboard"
    assert html =~ "System Health"
  end

  @tag :skip
  test "updates metrics in real-time", %{conn: conn} do
    # Skip this test until Floki is properly configured
    {:ok, view, _html} = live(conn, "/metrics/dashboard")
    
    # Should have initial metrics
    assert has_element?(view, "#system-health")
    assert has_element?(view, "#algedonic-balance")
  end
end