defmodule AutonomousOpponent.EventBus.OrderedDeliveryTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponent.EventBus.OrderedDelivery
  alias AutonomousOpponentV2Core.VSM.Clock
  
  setup do
    # Start HLC for event creation
    start_supervised!({AutonomousOpponentV2Core.Core.HybridLogicalClock, []})
    
    # Create a test subscriber process
    test_pid = self()
    
    {:ok, %{subscriber: test_pid}}
  end
  
  describe "basic ordering" do
    test "delivers events in HLC order within buffer window", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 100
      ]})
      
      # Create events with different timestamps
      {:ok, event1} = Clock.create_event(:test, :event1, %{data: "first"})
      Process.sleep(10)
      {:ok, event2} = Clock.create_event(:test, :event2, %{data: "second"})
      Process.sleep(10)
      {:ok, event3} = Clock.create_event(:test, :event3, %{data: "third"})
      
      # Submit events out of order
      OrderedDelivery.submit_event(od_pid, event3)
      OrderedDelivery.submit_event(od_pid, event1)
      OrderedDelivery.submit_event(od_pid, event2)
      
      # Wait for buffer window to expire
      Process.sleep(150)
      
      # Should receive events in correct order
      assert_receive {:ordered_event_batch, [^event1, ^event2, ^event3]}, 200
    end
    
    test "delivers single events when batch_size is 1", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 50,
        config: %{batch_size: 1}
      ]})
      
      {:ok, event1} = Clock.create_event(:test, :event1, %{data: "first"})
      {:ok, event2} = Clock.create_event(:test, :event2, %{data: "second"})
      
      OrderedDelivery.submit_event(od_pid, event1)
      OrderedDelivery.submit_event(od_pid, event2)
      
      Process.sleep(100)
      
      # Should receive individual events
      assert_receive {:ordered_event, ^event1}
      assert_receive {:ordered_event, ^event2}
    end
    
    test "handles duplicate events", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 50
      ]})
      
      {:ok, event} = Clock.create_event(:test, :event1, %{data: "test"})
      
      # Submit same event twice
      OrderedDelivery.submit_event(od_pid, event)
      OrderedDelivery.submit_event(od_pid, event)
      
      Process.sleep(100)
      
      # Should only receive one event
      assert_receive {:ordered_event, ^event}
      refute_receive {:ordered_event, _}, 50
    end
  end
  
  describe "late event handling" do
    test "delivers late events immediately", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 50
      ]})
      
      # Create an old event
      old_timestamp = %{
        physical: System.os_time(:nanosecond) - 200_000_000,  # 200ms ago
        logical: 0,
        node_id: "test"
      }
      
      old_event = %{
        id: "old-event",
        timestamp: old_timestamp,
        topic: :test,
        data: %{},
        metadata: %{}
      }
      
      OrderedDelivery.submit_event(od_pid, old_event)
      
      # Should receive immediately
      assert_receive {:ordered_event, ^old_event}, 100
    end
  end
  
  describe "algedonic bypass" do
    test "bypasses ordering for high-intensity algedonic signals", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 100
      ]})
      
      # Create regular event
      {:ok, regular_event} = Clock.create_event(:test, :regular, %{data: "normal"})
      
      # Create high-intensity algedonic event
      {:ok, pain_event} = Clock.create_event(:test, :pain, %{
        data: "pain",
        metadata: %{algedonic: true, intensity: 0.99}
      })
      
      # Submit regular event first
      OrderedDelivery.submit_event(od_pid, regular_event)
      
      # Submit pain event - should bypass
      OrderedDelivery.submit_event(od_pid, pain_event)
      
      # Should receive pain event immediately
      assert_receive {:ordered_event, ^pain_event}, 50
      
      # Regular event comes later after buffer window
      Process.sleep(150)
      assert_receive {:ordered_event, ^regular_event}
    end
    
    test "buffers low-intensity algedonic signals", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 100
      ]})
      
      {:ok, mild_pain} = Clock.create_event(:test, :mild_pain, %{
        data: "mild",
        metadata: %{algedonic: true, intensity: 0.5}
      })
      
      OrderedDelivery.submit_event(od_pid, mild_pain)
      
      # Should not receive immediately
      refute_receive {:ordered_event, _}, 50
      
      # Should receive after buffer window
      Process.sleep(100)
      assert_receive {:ordered_event, ^mild_pain}
    end
  end
  
  describe "adaptive windowing" do
    test "increases window on high reorder ratio", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 50,
        config: %{
          adaptive_window: true,
          min_window_ms: 10,
          max_window_ms: 200
        }
      ]})
      
      # Submit many out-of-order events to trigger adaptation
      for i <- 20..1 do
        {:ok, event} = Clock.create_event(:test, :"event_#{i}", %{seq: i})
        OrderedDelivery.submit_event(od_pid, event)
        Process.sleep(5)
      end
      
      # Let it process
      Process.sleep(200)
      
      # Check that window has adapted
      stats = OrderedDelivery.get_stats(od_pid)
      assert stats.current_window_ms > 50
    end
  end
  
  describe "buffer overflow protection" do
    test "forces flush when buffer exceeds max size", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 5000,  # Long window
        config: %{max_buffer_size: 10}
      ]})
      
      # Submit more events than buffer can hold
      events = for i <- 1..15 do
        {:ok, event} = Clock.create_event(:test, :"overflow_#{i}", %{seq: i})
        OrderedDelivery.submit_event(od_pid, event)
        event
      end
      
      # Should receive first batch immediately due to overflow
      assert_receive {:ordered_event_batch, received_events}, 500
      assert length(received_events) >= 10
    end
  end
  
  describe "subscriber monitoring" do
    test "shuts down when subscriber process dies" do
      # Start a separate process as subscriber
      {:ok, subscriber_pid} = Agent.start_link(fn -> [] end)
      
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber_pid,
        buffer_window_ms: 100
      ]})
      
      # Verify it's alive
      assert Process.alive?(od_pid)
      
      # Kill the subscriber
      Process.exit(subscriber_pid, :kill)
      
      # OrderedDelivery should shut down
      Process.sleep(100)
      refute Process.alive?(od_pid)
    end
  end
  
  describe "statistics tracking" do
    test "tracks comprehensive statistics", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 50
      ]})
      
      # Submit some events
      for i <- 1..5 do
        {:ok, event} = Clock.create_event(:test, :"stat_#{i}", %{seq: i})
        OrderedDelivery.submit_event(od_pid, event)
      end
      
      # Force delivery
      OrderedDelivery.flush(od_pid)
      
      stats = OrderedDelivery.get_stats(od_pid)
      
      assert stats.events_buffered == 5
      assert stats.events_delivered == 5
      assert stats.current_buffer_size == 0
      assert stats.throughput_per_sec > 0
    end
  end
  
  describe "error handling" do
    test "handles events with future timestamps gracefully", %{subscriber: subscriber} do
      {:ok, od_pid} = start_supervised({OrderedDelivery, [
        subscriber: subscriber,
        buffer_window_ms: 50
      ]})
      
      # Create event with future timestamp
      future_timestamp = %{
        physical: System.os_time(:nanosecond) + 60_000_000_000,  # 1 minute in future
        logical: 0,
        node_id: "test"
      }
      
      future_event = %{
        id: "future-event",
        timestamp: future_timestamp,
        topic: :test,
        data: %{},
        metadata: %{}
      }
      
      OrderedDelivery.submit_event(od_pid, future_event)
      
      # Should still be buffered and delivered after window
      Process.sleep(100)
      assert_receive {:ordered_event, ^future_event}
    end
  end
end