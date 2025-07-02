defmodule AutonomousOpponent.VSM.Supervisor do
  @moduledoc """
  VSM Supervisor - Manages all VSM subsystems

  Supervises the complete VSM implementation including:
  - S1-S5 subsystems
  - Algedonic system
  - Control loop integration

  Implements restart strategies aligned with Beer's principles,
  ensuring system viability even under failure conditions.
  """

  use Supervisor
  require Logger

  alias AutonomousOpponent.VSM.{
    S1.Operations,
    S1.Supervisor,
    S2.Coordination,
    S3.Control,
    S4.Intelligence,
    S5.Policy,
    Algedonic.System,
    ControlLoop
  }

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Core VSM Subsystems
      # S1 - Operations Supervisor (Manages multiple workers for variety absorption)
      {AutonomousOpponent.VSM.S1.Supervisor, []},
      # S1 - Primary Operations Worker
      {Operations, [id: "s1_primary", name: S1.Operations]},

      # S2 - Coordination (Anti-oscillation)
      {Coordination, [id: "s2_primary", name: S2.Coordination]},

      # S3 - Control (Resource optimization)
      {Control, [id: "s3_primary", name: S3.Control]},

      # S4 - Intelligence (Environmental scanning)
      {Intelligence, [id: "s4_primary", name: S4.Intelligence]},

      # S5 - Policy (Identity and governance)
      {Policy, [id: "s5_primary", name: S5.Policy]},

      # Algedonic System (High priority pain/pleasure)
      {System, [id: "algedonic_primary", name: Algedonic.System]},

      # Control Loop (Connects all subsystems)
      {ControlLoop, [id: "control_loop_primary", name: VSM.ControlLoop]}
    ]

    # Supervisor strategy aligned with VSM principles
    opts = [
      # Subsystems are independent
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 60
    ]

    Logger.info("Starting VSM Supervisor with complete subsystem hierarchy")

    Supervisor.init(children, opts)
  end

  @doc """
  Get the status of all VSM subsystems
  """
  def get_vsm_status do
    %{
      supervisor_status: :running,
      subsystems: get_subsystem_status(),
      control_loop: get_control_loop_status(),
      algedonic: get_algedonic_status()
    }
  end

  @doc """
  Restart a specific subsystem
  """
  def restart_subsystem(subsystem)
      when subsystem in [:s1, :s2, :s3, :s4, :s5, :algedonic, :control_loop] do
    child_id = subsystem_to_child_id(subsystem)

    case Supervisor.terminate_child(__MODULE__, child_id) do
      :ok ->
        case Supervisor.restart_child(__MODULE__, child_id) do
          {:ok, _pid} -> {:ok, :restarted}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Enable emergency mode across all subsystems
  """
  def enable_emergency_mode do
    Logger.warn("VSM Supervisor enabling emergency mode")

    # Notify control loop to enter emergency mode
    if pid = Process.whereis(VSM.ControlLoop) do
      ControlLoop.enable_emergency_mode(pid)
    end

    # Notify S5 Policy
    if pid = Process.whereis(S5.Policy) do
      GenServer.cast(pid, {:emergency_mode, true})
    end

    # Notify Algedonic system
    if pid = Process.whereis(Algedonic.System) do
      GenServer.cast(pid, {:emergency_mode, true})
    end

    :ok
  end

  @doc """
  Perform health check on all subsystems
  """
  def health_check do
    subsystems = [:s1, :s2, :s3, :s4, :s5, :algedonic, :control_loop]

    health_results =
      Enum.map(subsystems, fn subsystem ->
        pid = get_subsystem_pid(subsystem)

        health =
          if pid && Process.alive?(pid) do
            # Try to call subsystem
            try do
              case subsystem do
                :s1 -> Operations.get_operational_metrics(pid)
                :s2 -> Coordination.get_coordination_status(pid)
                :s3 -> Control.get_resource_status(pid)
                :s4 -> Intelligence.get_environmental_model(pid)
                :s5 -> Policy.get_system_identity(pid)
                :algedonic -> System.get_status(pid)
                :control_loop -> ControlLoop.get_system_status(pid)
              end

              :healthy
            catch
              _ -> :unresponsive
            end
          else
            :dead
          end

        {subsystem, health}
      end)
      |> Map.new()

    overall_health =
      if Enum.all?(Map.values(health_results), &(&1 == :healthy)) do
        :healthy
      else
        :degraded
      end

    %{
      overall: overall_health,
      subsystems: health_results,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  # Private functions

  defp get_subsystem_status do
    %{
      s1: get_process_status(S1.Operations),
      s2: get_process_status(S2.Coordination),
      s3: get_process_status(S3.Control),
      s4: get_process_status(S4.Intelligence),
      s5: get_process_status(S5.Policy)
    }
  end

  defp get_control_loop_status do
    if pid = Process.whereis(VSM.ControlLoop) do
      try do
        ControlLoop.get_system_status(pid)
      catch
        _ -> %{status: :error}
      end
    else
      %{status: :not_running}
    end
  end

  defp get_algedonic_status do
    if pid = Process.whereis(Algedonic.System) do
      try do
        System.get_status(pid)
      catch
        _ -> %{status: :error}
      end
    else
      %{status: :not_running}
    end
  end

  defp get_process_status(name) do
    if pid = Process.whereis(name) do
      if Process.alive?(pid) do
        :running
      else
        :dead
      end
    else
      :not_started
    end
  end

  defp subsystem_to_child_id(subsystem) do
    case subsystem do
      :s1 -> Operations
      :s2 -> Coordination
      :s3 -> Control
      :s4 -> Intelligence
      :s5 -> Policy
      :algedonic -> System
      :control_loop -> ControlLoop
    end
  end

  defp get_subsystem_pid(subsystem) do
    case subsystem do
      :s1 -> Process.whereis(S1.Operations)
      :s2 -> Process.whereis(S2.Coordination)
      :s3 -> Process.whereis(S3.Control)
      :s4 -> Process.whereis(S4.Intelligence)
      :s5 -> Process.whereis(S5.Policy)
      :algedonic -> Process.whereis(Algedonic.System)
      :control_loop -> Process.whereis(VSM.ControlLoop)
    end
  end
end
