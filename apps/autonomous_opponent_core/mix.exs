defmodule AutonomousOpponentV2Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :autonomous_opponent_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [
        summary: [threshold: 40]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {AutonomousOpponentV2Core.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      {:poolboy, "~> 1.5"},
      # {:handoff, "~> 0.1.0"}, # Commented out - requires Elixir 1.18+
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
      {:httpoison, "~> 1.8"},
      {:finch, "~> 0.18"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # AMQP library - version 4.x supports OTP 27
      # If still incompatible, the code gracefully degrades to stub mode
      {:amqp, "~> 4.0"},
      
      # OpenTelemetry for distributed tracing
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry_exporter, "~> 1.8"},
      
      # JWT authentication
      {:joken, "~> 2.6"},
      
      # GenStage for event processing
      {:gen_stage, "~> 1.2"},
      
      # Encryption library
      {:cloak, "~> 1.1"},
      {:cloak_ecto, "~> 1.3"},
      
      # Redis client for distributed rate limiting
      {:redix, "~> 1.5"}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["test"]
    ]
  end
end
