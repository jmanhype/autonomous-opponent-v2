defmodule AutonomousOpponent.EventBus.SubsystemOrderedDeliveryTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponent.EventBus.SubsystemOrderedDelivery
  alias AutonomousOpponentV2Core.VSM.Clock
  
  setup do
    # Start HLC for event creation
    start_supervised!({AutonomousOpponentV2Core.Core.HybridLogicalClock, []})
    
    # Create a test subscriber process
    test_pid = self()
    
    {:ok, %{subscriber: test_pid}}
  end
  
  describe "subsystem isolation" do
    test "maintains separate buffers for each subsystem", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber,
        config: %{
          subsystem_windows: %{
            s1_operations: 50,
            s4_intelligence: 100
          }
        }
      ]})
      
      # Create events for different subsystems
      {:ok, s1_event} = Clock.create_event(:test, :operation_started, %{data: "s1"})
      {:ok, s4_event} = Clock.create_event(:test, :pattern_detected, %{data: "s4"})
      
      # Submit events
      SubsystemOrderedDelivery.submit_event(sod_pid, s1_event)
      SubsystemOrderedDelivery.submit_event(sod_pid, s4_event)
      
      # S1 should deliver after 50ms
      Process.sleep(60)
      assert_receive {:ordered_event, ^s1_event}
      refute_receive {:ordered_event, _}, 10
      
      # S4 should deliver after 100ms total
      Process.sleep(50)
      assert_receive {:ordered_event, ^s4_event}
    end
    
    test "orders events within subsystem boundaries", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber
      ]})
      
      # Create S1 events out of order
      {:ok, s1_event1} = Clock.create_event(:test, :operation_started, %{seq: 1})
      Process.sleep(10)
      {:ok, s1_event2} = Clock.create_event(:test, :operation_completed, %{seq: 2})
      
      # Create S2 events out of order
      {:ok, s2_event1} = Clock.create_event(:test, :coordination_required, %{seq: 1})
      Process.sleep(10)
      {:ok, s2_event2} = Clock.create_event(:test, :anti_oscillation, %{seq: 2})
      
      # Submit all events mixed
      SubsystemOrderedDelivery.submit_event(sod_pid, s1_event2)
      SubsystemOrderedDelivery.submit_event(sod_pid, s2_event2)
      SubsystemOrderedDelivery.submit_event(sod_pid, s1_event1)
      SubsystemOrderedDelivery.submit_event(sod_pid, s2_event1)
      
      # Wait for delivery
      Process.sleep(100)
      
      # Should receive in correct order per subsystem
      assert_receive {:ordered_event_batch, [^s1_event1, ^s1_event2]}
      assert_receive {:ordered_event_batch, [^s2_event1, ^s2_event2]}
    end
  end
  
  describe "subsystem-specific configuration" do
    test "respects different batch sizes per subsystem", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber,
        config: %{
          subsystem_windows: %{
            s1_operations: 50,
            s4_intelligence: 50
          },
          batch_sizes: %{
            s1_operations: 1,      # Individual delivery
            s4_intelligence: 100   # Batch delivery
          }
        }
      ]})
      
      # Create multiple events for each subsystem
      s1_events = for i <- 1..3 do
        {:ok, event} = Clock.create_event(:test, :operation_started, %{seq: i})
        SubsystemOrderedDelivery.submit_event(sod_pid, event)
        event
      end
      
      s4_events = for i <- 1..3 do
        {:ok, event} = Clock.create_event(:test, :pattern_detected, %{seq: i})
        SubsystemOrderedDelivery.submit_event(sod_pid, event)
        event
      end
      
      Process.sleep(100)
      
      # S1 events should come individually
      for event <- s1_events do
        assert_receive {:ordered_event, ^event}
      end
      
      # S4 events should come as batch
      assert_receive {:ordered_event_batch, ^s4_events}
    end
    
    test "applies adaptive windowing only where configured", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber,
        config: %{
          adaptive_windows: %{
            s1_operations: true,
            s5_policy: false
          }
        }
      ]})
      
      # Submit many S1 events to trigger adaptation
      for i <- 20..1 do
        {:ok, event} = Clock.create_event(:test, :operation_started, %{seq: i})
        SubsystemOrderedDelivery.submit_event(sod_pid, event)
      end
      
      # Submit S5 events
      for i <- 1..10 do
        {:ok, event} = Clock.create_event(:test, :policy_update, %{seq: i})
        SubsystemOrderedDelivery.submit_event(sod_pid, event)
      end
      
      Process.sleep(200)
      
      stats = SubsystemOrderedDelivery.get_stats(sod_pid)
      
      # S1 window should have adapted
      assert stats.s1_operations.current_window_ms != 50
      
      # S5 window should remain unchanged
      assert stats.s5_policy.current_window_ms == 100
    end
  end
  
  describe "algedonic subsystem handling" do
    test "minimal buffering for algedonic signals", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber
      ]})
      
      {:ok, pain_event} = Clock.create_event(:test, :algedonic_pain, %{
        intensity: 0.8,
        metadata: %{algedonic: true, intensity: 0.8}
      })
      
      SubsystemOrderedDelivery.submit_event(sod_pid, pain_event)
      
      # Should receive quickly (10ms window)
      assert_receive {:ordered_event, ^pain_event}, 20
    end
    
    test "bypasses buffering for emergency algedonic signals", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber
      ]})
      
      {:ok, emergency} = Clock.create_event(:test, :emergency_algedonic, %{
        intensity: 0.99,
        metadata: %{algedonic: true, intensity: 0.99}
      })
      
      SubsystemOrderedDelivery.submit_event(sod_pid, emergency)
      
      # Should bypass and receive immediately
      assert_receive {:ordered_event, ^emergency}, 5
    end
  end
  
  describe "subsystem determination" do
    test "correctly categorizes events by topic", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber
      ]})
      
      # Test various event topics
      topic_tests = [
        {:operation_started, :s1_operations},
        {:coordination_required, :s2_coordination},
        {:control_action, :s3_control},
        {:pattern_detected, :s4_intelligence},
        {:policy_update, :s5_policy},
        {:algedonic_pain, :algedonic},
        {:unknown_event, :meta_system}
      ]
      
      for {topic, expected_subsystem} <- topic_tests do
        {:ok, event} = Clock.create_event(:test, topic, %{test: true})
        SubsystemOrderedDelivery.submit_event(sod_pid, event)
      end
      
      Process.sleep(150)
      
      # Should receive all events
      for _ <- 1..length(topic_tests) do
        assert_receive {:ordered_event, _}
      end
    end
    
    test "respects explicit subsystem metadata", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber
      ]})
      
      # Create event with explicit subsystem
      {:ok, event} = Clock.create_event(:test, :generic_event, %{
        data: "test",
        metadata: %{subsystem: :s3_control}
      })
      
      SubsystemOrderedDelivery.submit_event(sod_pid, event)
      
      # Check stats to verify it went to S3
      Process.sleep(10)
      stats = SubsystemOrderedDelivery.get_stats(sod_pid)
      assert stats.s3_control.events_buffered == 1
    end
  end
  
  describe "selective flushing" do
    test "flushes single subsystem on demand", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber,
        config: %{
          subsystem_windows: %{
            s1_operations: 5000,    # Very long window
            s2_coordination: 5000
          }
        }
      ]})
      
      # Add events to multiple subsystems
      {:ok, s1_event} = Clock.create_event(:test, :operation_started, %{})
      {:ok, s2_event} = Clock.create_event(:test, :coordination_required, %{})
      
      SubsystemOrderedDelivery.submit_event(sod_pid, s1_event)
      SubsystemOrderedDelivery.submit_event(sod_pid, s2_event)
      
      # Flush only S1
      SubsystemOrderedDelivery.flush_subsystem(sod_pid, :s1_operations)
      
      # Should receive S1 event immediately
      assert_receive {:ordered_event, ^s1_event}, 100
      
      # Should not receive S2 event
      refute_receive {:ordered_event, ^s2_event}, 100
    end
    
    test "flushes all subsystems on general flush", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber,
        config: %{
          subsystem_windows: %{
            s1_operations: 5000,
            s2_coordination: 5000,
            s3_control: 5000
          }
        }
      ]})
      
      # Add events to multiple subsystems
      events = for subsystem <- [:operation_started, :coordination_required, :control_action] do
        {:ok, event} = Clock.create_event(:test, subsystem, %{})
        SubsystemOrderedDelivery.submit_event(sod_pid, event)
        event
      end
      
      # Flush all
      SubsystemOrderedDelivery.flush(sod_pid)
      
      # Should receive all events
      for event <- events do
        assert_receive {:ordered_event, ^event}, 100
      end
    end
  end
  
  describe "performance characteristics" do
    test "handles high-frequency S1 operations efficiently", %{subscriber: subscriber} do
      {:ok, sod_pid} = start_supervised({SubsystemOrderedDelivery, [
        subscriber: subscriber,
        config: %{
          subsystem_windows: %{s1_operations: 20},
          batch_sizes: %{s1_operations: 50}
        }
      ]})
      
      # Simulate high-frequency operations
      events = for i <- 1..100 do
        {:ok, event} = Clock.create_event(:test, :operation_started, %{seq: i})
        SubsystemOrderedDelivery.submit_event(sod_pid, event)
        event
      end
      
      # Should receive in batches
      batches_received = receive_all_batches([], 500)
      
      # Verify all events received
      all_received = Enum.flat_map(batches_received, & &1)
      assert length(all_received) == 100
      
      # Verify batch sizes
      assert Enum.all?(batches_received, fn batch -> 
        length(batch) <= 50 
      end)
    end
  end
  
  # Helper functions
  
  defp receive_all_batches(acc, timeout) do
    receive do
      {:ordered_event_batch, batch} ->
        receive_all_batches([batch | acc], timeout)
      {:ordered_event, event} ->
        receive_all_batches([[event] | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end
end