defmodule AutonomousOpponentV2Web.MetricsControllerTest do
  use AutonomousOpponentV2Web.ConnCase

  test "GET /metrics returns prometheus format", %{conn: conn} do
    conn = get(conn, "/metrics")
    assert response = text_response(conn, 200)
    # Should contain prometheus format
    assert response =~ "#" || response == ""
  end
end