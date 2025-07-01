defmodule AutonomousOpponentV2.Repo do
  use Ecto.Repo,
    otp_app: :autonomous_opponent_v2,
    adapter: Ecto.Adapters.Postgres
end
