defmodule AutonomousOpponentV2Web.PageControllerTest do
  use AutonomousOpponentV2Web.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Autonomous Opponent"
  end
end