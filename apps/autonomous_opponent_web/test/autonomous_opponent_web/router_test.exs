defmodule AutonomousOpponentV2Web.RouterTest do
  use AutonomousOpponentV2Web.ConnCase

  test "health endpoint returns 200", %{conn: conn} do
    conn = get(conn, "/health")
    assert json_response(conn, 200)["status"] == "healthy"
  end

  test "unknown routes return 404", %{conn: conn} do
    assert_error_sent 404, fn ->
      get(conn, "/nonexistent")
    end
  end
end