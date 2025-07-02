defmodule AutonomousOpponentV2Web.RouterTest do
  use AutonomousOpponentV2Web.ConnCase

  test "health endpoint returns 503 in test environment", %{conn: conn} do
    conn = get(conn, "/health")
    # In test environment, health check fails because server is not running
    assert json_response(conn, 503)["status"] == "unhealthy"
  end

  test "unknown routes return 404", %{conn: conn} do
    conn = get(conn, "/nonexistent")
    assert conn.status == 404
  end
end