defmodule AutonomousOpponentV2Core.VSM.Supervisor do
  @moduledoc """
  The Viable System Model (VSM) Supervisor.

  This supervisor is responsible for dynamically starting and managing VSM components
  based on configurations fetched from the database. It embodies the self-organizing
  and adaptive nature of the Cybernetic system.

  **Wisdom Preservation:** This dynamic approach allows the system to adapt its
  structure at runtime, a key principle for resilience and continuous evolution.
  The configuration in the database serves as a living blueprint for the system's
  current and desired state.
  """
  use Supervisor
  require Logger

  alias AutonomousOpponentV2Core.VSM.System

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("🧠 Starting VSM Supervisor: Dynamically orchestrating cybernetic components...")

    children = [
      # Placeholder for dynamically started children.
      # The actual children will be added after fetching configurations from the DB.
    ]

    # We use :one_for_one strategy as each VSM component should be independently supervised.
    # Higher restart limits are set to allow for transient issues in dynamic components.
    opts = [
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60,
      name: __MODULE__
    ]

    Supervisor.init(children, opts)
  end

  @doc """
  Fetches VSM system configurations from the database.
  """
  def fetch_systems_config_from_db do
    AutonomousOpponentV2Core.Repo.all(System)
  end
end
