defmodule AutonomousOpponentV2Core.VSM.DynamicStarter do
  @moduledoc """
  A GenServer responsible for dynamically starting VSM components.
  It fetches system configurations from the database and starts them under the VSM Supervisor.
  """
  use GenServer
  require Logger

  alias AutonomousOpponentV2Core.Repo
  alias AutonomousOpponentV2Core.VSM.System

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("🚀 VSM DynamicStarter initialized. Scheduling dynamic children startup...")
    Process.send_after(self(), :start_dynamic_children, 1000) # Delay to allow VSM Supervisor to fully start
    {:ok, %{}}
  end

  @impl true
  def handle_info(:start_dynamic_children, state) do
    Logger.info("Fetching VSM records for dynamic supervision...")
    systems = Repo.all(System)
    Logger.info("Fetched #{length(systems)} VSM records for supervision.")

    # Enum.each(systems, fn system ->
    #   case system.system_type do
    #     "s5" ->
    #       Logger.info("Starting new VSM child with spec: {:system, :s5, "#{system.id}"}")
    #       Supervisor.start_child(AutonomousOpponentV2Core.VSM.Supervisor, DynamicWorker.child_spec({:system, :s5, system.id}))
    #
    #     "s4" ->
    #       Logger.info("Starting new VSM child with spec: {:system, :s4, "#{system.id}"}")
    #       Supervisor.start_child(AutonomousOpponentV2Core.VSM.Supervisor, DynamicWorker.child_spec({:system, :s4, system.id}))
    #
    #     "s3" ->
    #       Logger.info("Starting new VSM child with spec: {:system, :s3, "#{system.id}"}")
    #       Supervisor.start_child(AutonomousOpponentV2Core.VSM.Supervisor, DynamicWorker.child_spec({:system, :s3, system.id}))
    #
    #     "s2" ->
    #       Logger.info("Starting new VSM child with spec: {:system, :s2, "#{system.id}"}")
    #       Supervisor.start_child(AutonomousOpponentV2Core.VSM.Supervisor, DynamicWorker.child_spec({:system, :s2, system.id}))
    #
    #     "s1" ->
    #       if String.starts_with?(system.name, "Subsystem") do
    #         Logger.info("Starting new VSM child with spec: {:subsystem, "#{system.id}"}")
    #         Supervisor.start_child(AutonomousOpponentV2Core.VSM.Supervisor, DynamicWorker.child_spec({:subsystem, system.id}))
    #       else
    #         Logger.warning("System record with type 's1' encountered (ID: #{system.id}). S1 workers should be started from Subsystem records. Skipping.")
    #       end
    #
    #     other_type ->
    #       Logger.warning("Unknown system type '#{other_type}' for system ID #{system.id}. Skipping.")
    #   end
    # end)

    Logger.info("VSM children reconciliation complete.")
    {:noreply, state}
  end
end
