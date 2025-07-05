defmodule AutonomousOpponentV2Core.WebGateway.GatewayTest do
  @moduledoc """
  Tests for the Web Gateway supervisor and core functionality.
  """
  
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.WebGateway.Gateway
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Subscribe to relevant events for testing
    EventBus.subscribe(:vsm_s4_metrics)
    EventBus.subscribe(:vsm_algedonic)
    
    :ok
  end
  
  describe "Gateway supervisor" do
    test "starts all required child processes" do
      # Gateway should already be started by application
      assert Process.whereis(Gateway) != nil
      
      # Check child processes
      children = Supervisor.which_children(Gateway)
      child_names = Enum.map(children, fn {name, _, _, _} -> name end)
      
      # Check for required supervisors and modules
      assert Enum.any?(child_names, &String.contains?(to_string(&1), "Registry"))
      assert Enum.member?(child_names, AutonomousOpponentV2Core.WebGateway.Pool.ConnectionPool)
      assert Enum.member?(child_names, AutonomousOpponentV2Core.WebGateway.LoadBalancer.ConsistentHash)
      assert Enum.member?(child_names, AutonomousOpponentV2Core.WebGateway.Transport.Router)
      assert Enum.any?(child_names, &String.contains?(to_string(&1), "TaskSupervisor"))
    end
    
    test "restarts child processes on failure" do
      # Get the router PID
      [{_, router_pid, _, _}] = Supervisor.which_children(Gateway)
      |> Enum.filter(fn {name, _, _, _} -> 
        name == AutonomousOpponentV2Core.WebGateway.Transport.Router 
      end)
      
      # Kill the process
      Process.exit(router_pid, :kill)
      
      # Give supervisor time to restart
      :timer.sleep(100)
      
      # Check it was restarted
      [{_, new_router_pid, _, _}] = Supervisor.which_children(Gateway)
      |> Enum.filter(fn {name, _, _, _} -> 
        name == AutonomousOpponentV2Core.WebGateway.Transport.Router 
      end)
      
      assert new_router_pid != router_pid
      assert Process.alive?(new_router_pid)
    end
  end
  
  describe "report_metrics/1" do
    test "publishes metrics to VSM S4 subsystem" do
      metrics = %{
        active_connections: 10,
        messages_sent: 100,
        errors: 2
      }
      
      Gateway.report_metrics(metrics)
      
      assert_receive {:event_bus, :vsm_s4_metrics, event_data}
      assert event_data.source == :web_gateway
      assert event_data.metrics == metrics
      assert is_struct(event_data.timestamp, DateTime)
    end
  end
  
  describe "trigger_algedonic/2" do
    test "publishes pain signal for critical failures" do
      Gateway.trigger_algedonic(:critical, :all_transports_down)
      
      assert_receive {:event_bus, :vsm_algedonic, event_data}
      assert event_data.type == :pain
      assert event_data.severity == :critical
      assert event_data.source == :web_gateway
      assert event_data.reason == :all_transports_down
      assert is_struct(event_data.timestamp, DateTime)
    end
    
    test "publishes pain signal with custom reason" do
      reason = {:connection_pool_exhausted, %{available: 0, checked_out: 100}}
      Gateway.trigger_algedonic(:high, reason)
      
      assert_receive {:event_bus, :vsm_algedonic, event_data}
      assert event_data.severity == :high
      assert event_data.reason == reason
    end
  end
end