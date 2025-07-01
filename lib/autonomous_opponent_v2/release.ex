defmodule AutonomousOpponentV2.Release do
  @moduledoc """
  Release tasks for production deployment
  """

  @app :autonomous_opponent_v2

  def migrate do
    load_app()

    # Run migrations for both repos
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    # Get all configured repos from both umbrella apps
    core_repos = Application.get_env(:autonomous_opponent_core, :ecto_repos, [])
    web_repos = Application.get_env(:autonomous_opponent_web, :ecto_repos, [])

    Enum.uniq(core_repos ++ web_repos)
  end

  defp load_app do
    Application.load(@app)

    # Ensure all apps in the umbrella are loaded
    Application.load(:autonomous_opponent_core)
    Application.load(:autonomous_opponent_web)
  end
end
