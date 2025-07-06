defmodule AutonomousOpponentV2Web.Telemetry do
  import Telemetry.Metrics
  alias AutonomousOpponentV2Core.Telemetry.SystemTelemetry

  def metrics do
    # Delegate to the comprehensive telemetry dashboard
    AutonomousOpponentV2Web.TelemetryDashboard.metrics()
  end
  
  @doc """
  Emit VM metrics periodically via telemetry poller.
  """
  def emit_vm_metrics do
    memory = :erlang.memory()
    
    SystemTelemetry.emit(
      [:vm, :memory],
      %{
        total: memory[:total],
        processes: memory[:processes],
        binary: memory[:binary],
        ets: memory[:ets],
        atom: memory[:atom],
        atom_used: memory[:atom_used]
      },
      %{}
    )
    
    system_counts = :erlang.system_info(:system_counts)
    
    SystemTelemetry.emit(
      [:vm, :system_counts],
      %{
        process_count: system_counts[:process_count],
        atom_count: system_counts[:atom_count],
        port_count: system_counts[:port_count]
      },
      %{}
    )
    
    run_queue = :erlang.statistics(:run_queue_lengths)
    
    SystemTelemetry.emit(
      [:vm, :total_run_queue_lengths],
      %{
        total: Enum.sum(run_queue),
        cpu: length(run_queue),
        io: 0  # IO run queue not directly available
      },
      %{}
    )
  end
end
