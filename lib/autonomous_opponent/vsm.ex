defmodule AutonomousOpponent.VSM do
  @moduledoc """
  Viable System Model (VSM) - Main API

  Provides the public interface to the VSM implementation based on
  Stafford Beer's cybernetic principles. This module serves as the
  entry point for interacting with the complete VSM system.

  ## Architecture

  The VSM consists of five subsystems plus algedonic channels:

  - **S1 (Operations)**: Variety absorption and operational units
  - **S2 (Coordination)**: Anti-oscillation between S1 units
  - **S3 (Control)**: Resource bargaining and optimization
  - **S4 (Intelligence)**: Environmental scanning and future modeling
  - **S5 (Policy)**: Identity, values, and governance
  - **Algedonic**: High-priority pain/pleasure signals

  ## Usage

      # Start the complete VSM
      AutonomousOpponent.VSM.start_link()
      
      # Get system status
      AutonomousOpponent.VSM.get_status()
      
      # Submit operational variety
      AutonomousOpponent.VSM.absorb_variety(event)
      
      # Get environmental intelligence
      AutonomousOpponent.VSM.get_intelligence_report()
  """

  alias AutonomousOpponent.VSM.{
    Algedonic.System,
    ControlLoop,
    S1.Operations,
    S2.Coordination,
    S3.Control,
    S4.Intelligence,
    S5.Policy,
    Supervisor
  }

  @doc """
  Starts the complete VSM system
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(opts)
  end

  @doc """
  Get comprehensive VSM status
  """
  def get_status do
    %{
      vsm_status: Supervisor.get_vsm_status(),
      health_check: Supervisor.health_check(),
      control_loop: get_control_loop_status(),
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Submit variety to S1 Operations for absorption
  """
  def absorb_variety(event) do
    with {:ok, s1_pid} <- get_subsystem_pid(:s1) do
      Operations.absorb_variety(s1_pid, event)
    end
  end

  @doc """
  Get operational metrics from S1
  """
  def get_operational_metrics do
    with {:ok, s1_pid} <- get_subsystem_pid(:s1) do
      Operations.get_operational_metrics(s1_pid)
    end
  end

  @doc """
  Get coordination status from S2
  """
  def get_coordination_status do
    with {:ok, s2_pid} <- get_subsystem_pid(:s2) do
      Coordination.get_coordination_status(s2_pid)
    end
  end

  @doc """
  Get resource allocation from S3
  """
  def get_resource_allocation do
    with {:ok, s3_pid} <- get_subsystem_pid(:s3) do
      Control.get_resource_status(s3_pid)
    end
  end

  @doc """
  Request resource optimization from S3
  """
  def optimize_resources(constraints \\ %{}) do
    with {:ok, s3_pid} <- get_subsystem_pid(:s3) do
      Control.optimize_resources(s3_pid, constraints)
    end
  end

  @doc """
  Get environmental intelligence from S4
  """
  def get_intelligence_report(focus_areas \\ :all) do
    with {:ok, s4_pid} <- get_subsystem_pid(:s4) do
      Intelligence.scan_environment(s4_pid, focus_areas)
    end
  end

  @doc """
  Get future scenarios from S4
  """
  def get_future_scenarios(params \\ %{}) do
    with {:ok, s4_pid} <- get_subsystem_pid(:s4) do
      Intelligence.model_scenarios(s4_pid, params)
    end
  end

  @doc """
  Get system identity from S5
  """
  def get_system_identity do
    with {:ok, s5_pid} <- get_subsystem_pid(:s5) do
      Policy.get_system_identity(s5_pid)
    end
  end

  @doc """
  Set strategic goal via S5
  """
  def set_strategic_goal(goal) do
    with {:ok, s5_pid} <- get_subsystem_pid(:s5) do
      Policy.set_strategic_goal(s5_pid, goal)
    end
  end

  @doc """
  Submit action for policy evaluation
  """
  def evaluate_action(action) do
    with {:ok, s5_pid} <- get_subsystem_pid(:s5) do
      Policy.enforce_policy(s5_pid, action)
    end
  end

  @doc """
  Trigger algedonic signal (pain or pleasure)
  """
  def trigger_algedonic(type, source, metadata \\ %{}) when type in [:pain, :pleasure] do
    with {:ok, alg_pid} <- get_subsystem_pid(:algedonic) do
      System.trigger(alg_pid, type, source, metadata)
    end
  end

  @doc """
  Get algedonic system status
  """
  def get_algedonic_status do
    with {:ok, alg_pid} <- get_subsystem_pid(:algedonic) do
      System.get_status(alg_pid)
    end
  end

  @doc """
  Enable emergency mode across VSM
  """
  def enable_emergency_mode do
    Supervisor.enable_emergency_mode()
  end

  @doc """
  Disable emergency mode
  """
  def disable_emergency_mode do
    with {:ok, cl_pid} <- get_subsystem_pid(:control_loop) do
      ControlLoop.disable_emergency_mode(cl_pid)
    end
  end

  @doc """
  Perform complete health check
  """
  def health_check do
    Supervisor.health_check()
  end

  @doc """
  Restart a specific subsystem
  """
  def restart_subsystem(subsystem)
      when subsystem in [:s1, :s2, :s3, :s4, :s5, :algedonic, :control_loop] do
    Supervisor.restart_subsystem(subsystem)
  end

  @doc """
  Get metrics for the control loop
  """
  def get_control_loop_metrics do
    with {:ok, cl_pid} <- get_subsystem_pid(:control_loop) do
      status = ControlLoop.get_system_status(cl_pid)
      status[:metrics]
    end
  end

  @doc """
  Manually trigger a control cycle
  """
  def trigger_control_cycle do
    with {:ok, cl_pid} <- get_subsystem_pid(:control_loop) do
      ControlLoop.trigger_control_cycle(cl_pid)
    end
  end

  # Private functions

  defp get_subsystem_pid(subsystem) do
    module = get_subsystem_module(subsystem)
    pid = Process.whereis(module)

    if pid && Process.alive?(pid) do
      {:ok, pid}
    else
      {:error, {:subsystem_not_available, subsystem}}
    end
  end

  defp get_subsystem_module(:s1), do: S1.Operations
  defp get_subsystem_module(:s2), do: S2.Coordination
  defp get_subsystem_module(:s3), do: S3.Control
  defp get_subsystem_module(:s4), do: S4.Intelligence
  defp get_subsystem_module(:s5), do: S5.Policy
  defp get_subsystem_module(:algedonic), do: Algedonic.System
  defp get_subsystem_module(:control_loop), do: VSM.ControlLoop

  defp get_control_loop_status do
    case get_subsystem_pid(:control_loop) do
      {:ok, pid} -> ControlLoop.get_system_status(pid)
      error -> error
    end
  end
end
