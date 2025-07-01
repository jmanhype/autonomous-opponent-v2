defmodule DatabaseConfigTest do
  use ExUnit.Case

  test "AutonomousOpponentV2Core.Repo configuration exists" do
    config = Application.get_env(:autonomous_opponent_core, AutonomousOpponentV2Core.Repo)
    assert config != nil
    assert config[:database] != nil || config[:url] != nil
  end

  test "AutonomousOpponentV2Web.Repo configuration exists" do
    config = Application.get_env(:autonomous_opponent_web, AutonomousOpponentV2Web.Repo)
    assert config != nil
    assert config[:database] != nil || config[:url] != nil
  end

  test "can query AutonomousOpponentV2Core.Repo" do
    # This will fail if the database is not configured properly
    result = AutonomousOpponentV2Core.Repo.query!("SELECT 1")
    assert result.rows == [[1]]
  end

  test "can query AutonomousOpponentV2Web.Repo" do
    # This will fail if the database is not configured properly
    result = AutonomousOpponentV2Web.Repo.query!("SELECT 1")
    assert result.rows == [[1]]
  end
end