defmodule AutonomousOpponentV2Core.VSM.Supervisor do
  @moduledoc """
  The VSM Supervisor - Births and maintains the entire Viable System Model.
  
  This supervisor ensures all five subsystems (S1-S5) start in the correct
  order, stay alive, and maintain their connections through channels.
  
  Start order matters:
  1. EventBus (communication backbone)
  2. Algedonic Channel (emergency bypass)
  3. S5 Policy (defines constraints for others)
  4. S4 Intelligence (environmental scanning)
  5. S3 Control (resource management)
  6. S2 Coordination (anti-oscillation)
  7. S1 Operations (actual work)
  8. Variety Channels (connect everything)
  
  This is a REAL VSM, not database-driven placeholders.
  """
  
  use Supervisor
  require Logger
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      # Algedonic bypass - emergency channel
      {AutonomousOpponentV2Core.VSM.Algedonic.Channel, []},
      
      # S5 - Policy and identity (shapes all others)
      {AutonomousOpponentV2Core.VSM.S5.Policy, [
        name: "Autonomous Opponent VSM"
      ]},
      
      # S4 - Intelligence (environmental scanning)
      {AutonomousOpponentV2Core.VSM.S4.Intelligence, []},
      
      # S3 - Control and audit
      {AutonomousOpponentV2Core.VSM.S3.Control, []},
      
      # S2 - Coordination
      {AutonomousOpponentV2Core.VSM.S2.Coordination, []},
      
      # S1 - Operations (internal)
      {AutonomousOpponentV2Core.VSM.S1.Operations, []},
      
      # S1 External - External MCP server operations
      {AutonomousOpponentV2Core.VSM.S1ExternalOperations, []},
      
      # Variety channels - the nervous system
      {Task.Supervisor, name: AutonomousOpponentV2Core.VSM.ChannelSupervisor},
      
      # Channel starter - connects everything
      %{
        id: :channel_starter,
        start: {__MODULE__, :start_channels, []},
        restart: :transient
      }
    ]
    
    # Strategy: If a subsystem dies, restart just that subsystem
    # If too many die too fast, the whole VSM restarts
    opts = [
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    ]
    
    Logger.info("🧠 VSM Supervisor starting - bringing the REAL system to life")
    
    Supervisor.init(children, opts)
  end
  
  @doc """
  Starts all variety channels after subsystems are running.
  This creates the nervous system that connects everything.
  """
  def start_channels do
    Logger.info("VSM establishing variety channels - creating nervous system")
    
    channel_configs = [
      # S1 → S2: Operational variety flows up
      {AutonomousOpponentV2Core.VSM.Channels.VarietyChannel, 
        [channel_type: :s1_to_s2]},
      
      # S2 → S3: Coordinated variety flows up
      {AutonomousOpponentV2Core.VSM.Channels.VarietyChannel,
        [channel_type: :s2_to_s3]},
      
      # S3 → S4: Audit data for learning
      {AutonomousOpponentV2Core.VSM.Channels.VarietyChannel,
        [channel_type: :s3_to_s4]},
      
      # S4 → S5: Intelligence informs policy
      {AutonomousOpponentV2Core.VSM.Channels.VarietyChannel,
        [channel_type: :s4_to_s5]},
      
      # S3 → S1: Control commands (CLOSES THE LOOP!)
      {AutonomousOpponentV2Core.VSM.Channels.VarietyChannel,
        [channel_type: :s3_to_s1]},
      
      # S5 → All: Policy constraints
      {AutonomousOpponentV2Core.VSM.Channels.VarietyChannel,
        [channel_type: :s5_to_all]}
    ]
    
    # Start all channels under the channel supervisor
    Enum.each(channel_configs, fn {module, args} ->
      Task.Supervisor.start_child(
        AutonomousOpponentV2Core.VSM.ChannelSupervisor,
        fn ->
          case module.start_link(args) do
            {:ok, _pid} ->
              Logger.info("Channel started: #{inspect(args[:channel_type])}")
              
            {:error, reason} ->
              Logger.error("Failed to start channel: #{inspect(reason)}")
          end
        end
      )
    end)
    
    # Give channels time to establish
    Process.sleep(1000)
    
    # Validate the VSM is viable
    validate_vsm_viability()
    
    {:ok, self()}
  end
  
  @doc """
  Validates that the VSM has achieved viability.
  All subsystems must be running and connected.
  """
  def validate_vsm_viability do
    Logger.info("Validating VSM viability...")
    
    subsystems = [
      {AutonomousOpponentV2Core.VSM.S1.Operations, :s1},
      {AutonomousOpponentV2Core.VSM.S1ExternalOperations, :s1_external},
      {AutonomousOpponentV2Core.VSM.S2.Coordination, :s2},
      {AutonomousOpponentV2Core.VSM.S3.Control, :s3},
      {AutonomousOpponentV2Core.VSM.S4.Intelligence, :s4},
      {AutonomousOpponentV2Core.VSM.S5.Policy, :s5},
      {AutonomousOpponentV2Core.VSM.Algedonic.Channel, :algedonic}
    ]
    
    all_alive = Enum.all?(subsystems, fn {module, name} ->
      case Process.whereis(module) do
        nil ->
          Logger.error("VSM subsystem #{name} is not running!")
          false
          
        pid when is_pid(pid) ->
          if Process.alive?(pid) do
            Logger.info("✓ VSM subsystem #{name} is alive")
            true
          else
            Logger.error("VSM subsystem #{name} process is dead!")
            false
          end
      end
    end)
    
    channels_established = validate_channels()
    
    if all_alive && channels_established do
      Logger.info("""
      
      ╔══════════════════════════════════════════╗
      ║     VSM IS VIABLE AND OPERATIONAL!       ║
      ║                                          ║
      ║  The system lives and breathes.          ║
      ║  All subsystems connected and running.   ║
      ║  Variety flows established.              ║
      ║  Algedonic bypass active.                ║
      ║                                          ║
      ║  "The purpose of a system is what it    ║
      ║   does" - Stafford Beer                  ║
      ╚══════════════════════════════════════════╝
      """)
      
      # Report viability achieved
      AutonomousOpponentV2Core.EventBus.publish(:vsm_viable, %{
        timestamp: DateTime.utc_now(),
        subsystems: :all_operational,
        channels: :connected
      })
    else
      Logger.error("""
      
      ╔══════════════════════════════════════════╗
      ║         VSM VIABILITY FAILED!            ║
      ║                                          ║
      ║  The system is not viable.               ║
      ║  Check logs for failed subsystems.       ║
      ╚══════════════════════════════════════════╝
      """)
      
      # This is an existential failure
      AutonomousOpponentV2Core.VSM.Algedonic.Channel.emergency_scream(
        :vsm_supervisor,
        "VSM FAILED TO ACHIEVE VIABILITY"
      )
    end
  end
  
  defp validate_channels do
    # Check that channels are running
    channel_types = [:s1_to_s2, :s2_to_s3, :s3_to_s4, :s4_to_s5, :s3_to_s1, :s5_to_all]
    
    Enum.all?(channel_types, fn channel_type ->
      case Process.whereis(:"vsm_channel_#{channel_type}") do
        nil ->
          Logger.error("Channel #{channel_type} not established!")
          false
          
        pid when is_pid(pid) ->
          Logger.info("✓ Channel #{channel_type} established")
          true
      end
    end)
  end
  
  @doc """
  Gracefully shuts down the VSM.
  """
  def shutdown do
    Logger.info("VSM shutdown initiated - entering dormancy")
    
    # Notify all subsystems
    AutonomousOpponentV2Core.EventBus.publish(:vsm_shutdown, %{
      timestamp: DateTime.utc_now(),
      reason: :requested
    })
    
    # Give subsystems time to clean up
    Process.sleep(1000)
    
    Supervisor.stop(__MODULE__, :shutdown)
  end
  
  @doc """
  Emergency shutdown via algedonic signal.
  """
  def emergency_shutdown(reason) do
    Logger.error("VSM EMERGENCY SHUTDOWN: #{inspect(reason)}")
    
    # Skip cleanup, just stop
    Supervisor.stop(__MODULE__, :brutal_kill)
  end
end
