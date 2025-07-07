defmodule AutonomousOpponentV2Core.VSM.ClockTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.Core.HybridLogicalClock
  
  setup do
    # Start HLC for testing
    {:ok, _pid} = HybridLogicalClock.start_link(node_id: "test-vsm-node")
    :ok
  end
  
  describe "VSM timestamp generation" do
    test "generates VSM timestamps" do
      {:ok, timestamp} = Clock.now()
      
      assert is_map(timestamp)
      assert Map.has_key?(timestamp, :physical)
      assert Map.has_key?(timestamp, :logical)
      assert Map.has_key?(timestamp, :node_id)
    end
    
    test "generates event IDs with subsystem context" do
      {:ok, event_id} = Clock.event_id(:s1, :operation_complete, %{data: "test"})
      
      assert is_binary(event_id)
      assert String.contains?(event_id, "-")
    end
  end
  
  describe "VSM event creation" do
    test "creates complete VSM events" do
      {:ok, event} = Clock.create_event(:s1, :variety_absorption, %{input: "test"})
      
      assert event.subsystem == :s1
      assert event.type == :variety_absorption
      assert event.data == %{input: "test"}
      assert Map.has_key?(event, :timestamp)
      assert Map.has_key?(event, :created_at)
      assert Map.has_key?(event, :id)
      
      assert is_binary(event.id)
      assert is_binary(event.created_at)
      assert is_map(event.timestamp)
    end
    
    test "validates event structure" do
      {:ok, event} = Clock.create_event(:s2, :coordination, %{})
      
      assert Clock.valid_event?(event)
      
      # Test invalid event
      invalid_event = %{id: "test", subsystem: :s1}
      refute Clock.valid_event?(invalid_event)
    end
  end
  
  describe "event ordering" do
    test "orders events by timestamp" do
      {:ok, event1} = Clock.create_event(:s1, :op1, %{})
      Process.sleep(1)
      {:ok, event2} = Clock.create_event(:s2, :op2, %{})
      Process.sleep(1)
      {:ok, event3} = Clock.create_event(:s3, :op3, %{})
      
      events = [event3, event1, event2]
      ordered = Clock.order_events(events)
      
      assert ordered == [event1, event2, event3]
    end
    
    test "finds latest and earliest events" do
      {:ok, event1} = Clock.create_event(:s1, :op1, %{})
      Process.sleep(1)
      {:ok, event2} = Clock.create_event(:s2, :op2, %{})
      Process.sleep(1)
      {:ok, event3} = Clock.create_event(:s3, :op3, %{})
      
      events = [event2, event1, event3]
      
      assert Clock.earliest_event(events) == event1
      assert Clock.latest_event(events) == event3
      assert Clock.earliest_event([]) == nil
      assert Clock.latest_event([]) == nil
    end
  end
  
  describe "time window operations" do
    test "checks if event is within time window" do
      {:ok, event} = Clock.create_event(:s1, :recent_op, %{})
      
      # Should be within a large window
      assert Clock.within_window?(event, 60_000)
      
      # Create old event by manipulating timestamp
      old_event = %{event | timestamp: %{event.timestamp | physical: event.timestamp.physical - 70_000}}
      
      # Should not be within small window
      refute Clock.within_window?(old_event, 60_000)
    end
    
    test "calculates event age" do
      {:ok, event} = Clock.create_event(:s1, :timed_op, %{})
      
      Process.sleep(10)
      
      {:ok, age} = Clock.event_age(event)
      assert age >= 10
      assert age < 1000  # Should be recent
    end
  end
  
  describe "sequence numbers and correlation" do
    test "generates sequence numbers" do
      {:ok, seq1} = Clock.sequence_number()
      Process.sleep(1)
      {:ok, seq2} = Clock.sequence_number()
      
      assert is_binary(seq1)
      assert is_binary(seq2)
      assert seq1 != seq2
      assert String.contains?(seq1, "-")
    end
    
    test "generates correlation IDs" do
      {:ok, corr_id} = Clock.correlation_id("test_operation")
      
      assert is_binary(corr_id)
      assert String.starts_with?(corr_id, "vsm_")
    end
  end
  
  describe "utility functions" do
    test "converts events to string representation" do
      {:ok, event} = Clock.create_event(:s4, :intelligence_scan, %{})
      
      str = Clock.event_to_string(event)
      assert String.contains?(str, "s4:intelligence_scan@")
    end
    
    test "generates partition keys" do
      {:ok, event} = Clock.create_event(:s1, :partition_test, %{})
      
      partition_key = Clock.partition_key(event, 8)
      assert String.starts_with?(partition_key, "vsm_partition_")
      
      # Should be consistent for same event
      assert partition_key == Clock.partition_key(event, 8)
    end
  end
  
  describe "synchronization" do
    test "synchronizes with remote timestamps" do
      {:ok, local_timestamp} = Clock.now()
      
      # Create remote timestamp slightly in the future
      remote_timestamp = %{
        physical: local_timestamp.physical + 100,
        logical: 0,
        node_id: "remote-vsm-node"
      }
      
      {:ok, synced_timestamp} = Clock.sync_with_remote(remote_timestamp)
      
      # Should be after the remote timestamp
      assert HybridLogicalClock.after?(synced_timestamp, remote_timestamp)
    end
  end
  
  describe "edge cases" do
    test "handles empty event lists" do
      assert Clock.order_events([]) == []
      assert Clock.latest_event([]) == nil
      assert Clock.earliest_event([]) == nil
    end
    
    test "handles single event lists" do
      {:ok, event} = Clock.create_event(:s1, :single, %{})
      
      assert Clock.order_events([event]) == [event]
      assert Clock.latest_event([event]) == event
      assert Clock.earliest_event([event]) == event
    end
    
    test "validates malformed events" do
      refute Clock.valid_event?(%{})
      refute Clock.valid_event?(%{timestamp: "invalid"})
      refute Clock.valid_event?("not a map")
      refute Clock.valid_event?(nil)
    end
  end
end