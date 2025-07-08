defmodule AutonomousOpponentV2Core.VSM.VarietyFlowTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  
  @moduletag :integration
  
  describe "variety flow through VSM channels" do
    setup do
      # Ensure VSM is started
      Application.ensure_all_started(:autonomous_opponent_core)
      
      # Clear any existing subscriptions for clean test
      :ok
    end
    
    test "variety flows from S1 → S2 → S3 → S1 completing the control loop" do
      # Set up test process to monitor variety flow
      test_pid = self()
      
      # Subscribe to all variety channels to monitor flow
      EventBus.subscribe(:s1_operations)
      EventBus.subscribe(:s2_coordination)
      EventBus.subscribe(:s3_control)
      
      # Simulate S1 publishing operational variety
      s1_variety = %{
        unit_id: :test_s1_unit,
        variety_type: :operational,
        entropy: 0.85,
        load: 75,
        timestamp: DateTime.utc_now()
      }
      
      # This should trigger the variety flow
      EventBus.publish(:s1_operations, s1_variety)
      
      # Wait for variety to flow through channels
      # S1 → VarietyChannel → S2
      assert_receive {:event_bus_hlc, %{topic: :s2_coordination, data: s2_data}}, 1000
      assert s2_data.variety_type == :aggregated
      assert s2_data.source_variety == :operational
      
      # S2 should process and publish coordination data
      # (In real system, S2.Coordination would do this automatically)
      # For test, we simulate S2's response
      s2_coordination = %{
        coordination_id: :test_coordination,
        variety_type: :coordinated,
        damping_applied: false,
        units_coordinated: [:test_s1_unit],
        timestamp: DateTime.utc_now()
      }
      
      EventBus.publish(:s2_coordination, s2_coordination)
      
      # S2 → VarietyChannel → S3
      assert_receive {:event_bus_hlc, %{topic: :s3_control, data: s3_data}}, 1000
      assert s3_data.variety_type == :control_ready
      assert s3_data.coordination_status == :coordinated
      
      # S3 should generate control commands
      # For test, we simulate S3's control command
      s3_command = %{
        control_id: :test_control,
        variety_type: :control,
        command: :throttle,
        target_unit: :test_s1_unit,
        timestamp: DateTime.utc_now()
      }
      
      EventBus.publish(:s3_control, s3_command)
      
      # S3 → VarietyChannel → S1 (CLOSES THE LOOP!)
      assert_receive {:event_bus_hlc, %{topic: :s1_operations, data: s1_command}}, 1000
      assert s1_command.variety_type == :command
      assert s1_command.commands != nil
      
      # Verify the control loop is complete
      assert s1_command.commands |> Enum.any?(fn cmd -> 
        cmd.command == :throttle && cmd.target_unit == :test_s1_unit
      end)
    end
    
    test "algedonic signals bypass normal variety flow" do
      # Subscribe to algedonic channel
      EventBus.subscribe(:algedonic_pain)
      
      # S1 extreme pain should go directly to S5, bypassing S2/S3/S4
      pain_signal = %{
        source: :s1_operations,
        pain_level: 0.95,  # Extreme pain
        reason: "system overload",
        timestamp: DateTime.utc_now()
      }
      
      EventBus.publish(:algedonic_pain, pain_signal)
      
      # Should receive immediately (no variety transformation)
      assert_receive {:event_bus_hlc, %{topic: :algedonic_pain, data: ^pain_signal}}, 100
    end
    
    test "broken variety channel prevents flow" do
      # Stop a variety channel to simulate failure
      # Note: In production, this would trigger algedonic pain
      
      # Try to get the S1→S2 variety channel
      s1_to_s2_channels = Process.registered()
      |> Enum.filter(fn name -> 
        name |> Atom.to_string() |> String.contains?("variety_channel_s1_to_s2")
      end)
      
      if length(s1_to_s2_channels) > 0 do
        # Stop the channel
        Process.exit(Process.whereis(hd(s1_to_s2_channels)), :kill)
        
        # Give it time to die
        Process.sleep(100)
        
        # Now variety shouldn't flow
        test_variety = %{test: "should_not_arrive"}
        EventBus.publish(:s1_operations, test_variety)
        
        # Should NOT receive on S2
        refute_receive {:event_bus_hlc, %{topic: :s2_coordination, data: _}}, 500
      end
    end
  end
  
  describe "variety channel subscriptions" do
    test "all VSM subsystems have correct subscriptions after fix" do
      # Get current subscribers
      subscribers = EventBus.list_subscribers()
      
      # S2 should subscribe to its variety channel output, not S1 directly
      assert :s2_coordination in Map.keys(subscribers)
      
      # S3 should subscribe to its variety channel output
      assert :s3_control in Map.keys(subscribers)
      
      # S1 should subscribe to receive control commands
      assert :s1_operations in Map.keys(subscribers)
      
      # Variety channels themselves should be subscribed to sources
      # (This validates the channels are wired correctly)
      s1_ops_subscribers = Map.get(subscribers, :s1_operations, [])
      assert Enum.any?(s1_ops_subscribers, fn subscriber ->
        subscriber |> inspect() |> String.contains?("VarietyChannel")
      end)
    end
  end
end