defmodule AutonomousOpponentV2.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"},
      {:poolboy, "~> 1.5"},
      {:handoff, "~> 0.1.0"},
      {:instructor, "~> 0.1.0"},
      {:goldrush, "~> 0.1.9"},
      {:uuid, "~> 1.1"},
      {:guardian, "~> 2.3"},
      {:comeonin, "~> 5.4"},
      {:bcrypt_elixir, "~> 3.1"},
      {:cors_plug, "~> 3.0"},
      {:jose, "~> 1.11"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:heroicons, "~> 0.5"},
      {:swoosh, "~> 1.5"}
    ]
  end

  defp aliases do
    [
      "deps.get": ["deps.get --only dev", "cmd mix deps.get"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["cmd mix ecto.reset"],
      test: ["cmd mix test"]
    ]
  end
end
