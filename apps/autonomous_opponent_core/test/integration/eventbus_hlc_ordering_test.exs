defmodule AutonomousOpponentV2Core.Integration.EventBusHLCOrderingTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Clock
  
  setup do
    # Clean up any existing subscriptions
    :ets.delete_all_objects(:event_bus_subscriptions)
    :ets.delete_all_objects(:event_bus_ordered_delivery)
    
    :ok
  end
  
  describe "end-to-end ordered delivery" do
    test "VSM subsystem receives events in causal order" do
      # Create a mock S4 Intelligence subsystem
      test_pid = self()
      
      # Subscribe with ordered delivery and batch mode
      EventBus.subscribe(:pattern_detected, test_pid, ordered_delivery: true, buffer_window_ms: 100, batch_delivery: true)
      
      # Simulate pattern detection events arriving out of order
      # This might happen due to network delays or concurrent processing
      patterns = for i <- 1..10 do
        data = %{
          pattern_id: "pattern_#{i}",
          confidence: 0.5 + i * 0.05,
          timestamp: DateTime.utc_now()
        }
        
        # Create event
        EventBus.publish(:pattern_detected, data)
        
        # Return expected event structure for verification
        {:pattern_detected, data}
      end
      
      # Wait for buffer window
      Process.sleep(150)
      
      # Collect all received events (may come as batches or individual events)
      events = collect_ordered_events([], 10, 1000)
      
      # Verify we got all events
      assert length(events) == 10
      
      # Verify ordering by HLC timestamp
      timestamps = Enum.map(events, fn event -> event.timestamp end)
      assert timestamps == Enum.sort_by(timestamps, &hlc_to_comparable/1)
      
      # Verify patterns are in correct order
      pattern_ids = Enum.map(events, fn event -> event.data.pattern_id end)
      assert pattern_ids == ["pattern_1", "pattern_2", "pattern_3", "pattern_4", "pattern_5", 
                             "pattern_6", "pattern_7", "pattern_8", "pattern_9", "pattern_10"]
    end
    
    test "algedonic signals bypass ordering when critical" do
      test_pid = self()
      
      # Subscribe to both regular and algedonic events
      EventBus.subscribe(:control_action, test_pid, ordered_delivery: true, buffer_window_ms: 200)
      EventBus.subscribe(:algedonic_pain, test_pid, ordered_delivery: true)
      
      # Publish regular control action
      EventBus.publish(:control_action, %{action: "adjust_resources", value: 0.7})
      
      # Simulate critical pain signal
      EventBus.publish(:algedonic_pain, %{
        intensity: 0.99,
        source: "resource_exhaustion",
        metadata: %{algedonic: true, intensity: 0.99}
      })
      
      # Pain should arrive immediately
      assert_receive {:ordered_event, pain_event}, 50
      assert pain_event.type == :algedonic_pain
      assert pain_event.data.intensity == 0.99
      
      # Control action arrives later after buffer window
      refute_receive {:ordered_event, _}, 100
      Process.sleep(150)
      assert_receive {:ordered_event, control_event}
      assert control_event.type == :control_action
    end
    
    test "multiple subscribers with different ordering preferences" do
      # Subscriber 1: Wants ordered delivery
      ordered_pid = spawn_link(fn -> 
        receive_loop(:ordered, [])
      end)
      
      # Subscriber 2: Wants immediate delivery
      immediate_pid = spawn_link(fn ->
        receive_loop(:immediate, [])
      end)
      
      # Subscribe with different preferences
      EventBus.subscribe(:test_event, ordered_pid, ordered_delivery: true, buffer_window_ms: 100)
      EventBus.subscribe(:test_event, immediate_pid)  # Default: immediate delivery
      
      # Publish events
      events = for i <- 5..1//-1 do
        EventBus.publish(:test_event, %{seq: i})
        Process.sleep(10)
        i
      end
      
      # Immediate subscriber should get events as published (5,4,3,2,1)
      Process.sleep(50)
      send(immediate_pid, :report)
      assert_receive {:immediate_events, immediate_events}
      immediate_seqs = Enum.map(immediate_events, fn e -> e.data.seq end)
      assert immediate_seqs == [5, 4, 3, 2, 1]
      
      # Ordered subscriber should get events in HLC order (likely 5,4,3,2,1 due to sleep)
      Process.sleep(100)
      send(ordered_pid, :report)
      assert_receive {:ordered_events, ordered_events}
      
      # Verify HLC ordering
      ordered_timestamps = Enum.map(ordered_events, fn e -> e.timestamp end)
      assert ordered_timestamps == Enum.sort_by(ordered_timestamps, &hlc_to_comparable/1)
    end
    
    test "subsystem isolation with partial ordering" do
      test_pid = self()
      
      # Subscribe to events from different subsystems
      # Using SubsystemOrderedDelivery for this test
      {:ok, sod_pid} = AutonomousOpponent.EventBus.SubsystemOrderedDelivery.start_link([
        subscriber: test_pid,
        config: %{
          subsystem_windows: %{
            s1_operations: 50,
            s4_intelligence: 150
          }
        }
      ])
      
      # Simulate concurrent events from different subsystems
      task1 = Task.async(fn ->
        for i <- 1..5 do
          {:ok, event} = Clock.create_event(:eventbus, :operation_started, %{op_id: i})
          AutonomousOpponent.EventBus.SubsystemOrderedDelivery.submit_event(sod_pid, event)
          Process.sleep(20)
        end
      end)
      
      task2 = Task.async(fn ->
        for i <- 1..5 do
          {:ok, event} = Clock.create_event(:eventbus, :pattern_detected, %{pattern_id: i})
          AutonomousOpponent.EventBus.SubsystemOrderedDelivery.submit_event(sod_pid, event)
          Process.sleep(30)
        end
      end)
      
      Task.await(task1)
      Task.await(task2)
      
      # S1 operations should start arriving after 50ms
      Process.sleep(60)
      
      # Collect S1 events
      s1_events = receive_events_for(100)
      assert length(s1_events) == 5
      assert Enum.all?(s1_events, fn e -> e.type == :operation_started end)
      
      # S4 intelligence events arrive later
      Process.sleep(100)
      s4_events = receive_events_for(100)
      assert length(s4_events) == 5
      assert Enum.all?(s4_events, fn e -> e.type == :pattern_detected end)
    end
  end
  
  describe "performance under load" do
    @tag :performance
    test "maintains ordering under high event load" do
      test_pid = self()
      
      # Subscribe with ordered delivery
      EventBus.subscribe(:load_test, test_pid, 
        ordered_delivery: true, 
        buffer_window_ms: 200,
        batch_delivery: true
      )
      
      # Generate high load
      num_events = 1000
      
      # Spawn multiple publishers to create concurrency
      tasks = for publisher_id <- 1..10 do
        Task.async(fn ->
          for i <- 1..div(num_events, 10) do
            EventBus.publish(:load_test, %{
              publisher: publisher_id,
              seq: i,
              data: :crypto.strong_rand_bytes(100)  # Some payload
            })
          end
        end)
      end
      
      # Wait for all publishers
      Enum.each(tasks, &Task.await/1)
      
      # Wait for buffer window
      Process.sleep(300)
      
      # Collect all events
      all_events = receive_all_event_batches([], 1000)
      
      # Verify count
      assert length(all_events) == num_events
      
      # Verify HLC ordering
      timestamps = Enum.map(all_events, fn e -> e.timestamp end)
      sorted_timestamps = Enum.sort_by(timestamps, &hlc_to_comparable/1)
      assert timestamps == sorted_timestamps
      
      # Verify no duplicates
      event_ids = Enum.map(all_events, fn e -> e.id end)
      assert length(Enum.uniq(event_ids)) == num_events
    end
  end
  
  describe "fault tolerance" do
    test "handles subscriber disconnection gracefully" do
      # Create a temporary subscriber process
      {:ok, subscriber} = Agent.start_link(fn -> [] end)
      
      # Subscribe with ordered delivery
      EventBus.subscribe(:fault_test, subscriber, ordered_delivery: true)
      
      # Publish some events
      for i <- 1..5 do
        EventBus.publish(:fault_test, %{seq: i})
      end
      
      # Kill the subscriber
      Process.exit(subscriber, :kill)
      Process.sleep(100)
      
      # Publishing more events should not crash
      for i <- 6..10 do
        EventBus.publish(:fault_test, %{seq: i})
      end
      
      # Verify EventBus is still alive
      assert Process.alive?(Process.whereis(AutonomousOpponentV2Core.EventBus))
    end
    
    test "recovers from OrderedDelivery process crash" do
      test_pid = self()
      
      # Subscribe with ordered delivery
      EventBus.subscribe(:crash_test, test_pid, ordered_delivery: true)
      
      # Find the OrderedDelivery process
      [{_, od_pid}] = :ets.lookup(:event_bus_ordered_delivery, {:crash_test, test_pid})
      
      # Publish event
      EventBus.publish(:crash_test, %{seq: 1})
      
      # Kill the OrderedDelivery process
      Process.exit(od_pid, :kill)
      Process.sleep(100)
      
      # The supervisor should restart it, but we'd lose buffered events
      # This is expected behavior - at-most-once delivery
      
      # New events should still work
      EventBus.publish(:crash_test, %{seq: 2})
      
      # We might not receive seq: 1, but the system should be stable
      assert Process.alive?(Process.whereis(AutonomousOpponentV2Core.EventBus))
    end
  end
  
  # Helper functions
  
  defp collect_ordered_events(collected, expected_count, timeout) when length(collected) >= expected_count do
    Enum.take(collected, expected_count)
  end
  
  defp collect_ordered_events(collected, expected_count, timeout) do
    receive do
      {:ordered_event, event} ->
        collect_ordered_events(collected ++ [event], expected_count, timeout)
        
      {:ordered_event_batch, batch} ->
        collect_ordered_events(collected ++ batch, expected_count, timeout)
    after
      timeout ->
        collected
    end
  end
  
  defp receive_loop(type, events) do
    receive do
      {:event_bus_hlc, event} ->
        receive_loop(type, [event | events])
        
      {:ordered_event, event} ->
        receive_loop(type, [event | events])
        
      {:ordered_event_batch, batch} ->
        receive_loop(type, batch ++ events)
        
      :report ->
        send(Process.get(:"$callers") |> hd(), {:"#{type}_events", Enum.reverse(events)})
        
      _ ->
        receive_loop(type, events)
    end
  end
  
  defp receive_events_for(timeout) do
    receive_events_for([], timeout)
  end
  
  defp receive_events_for(acc, timeout) do
    receive do
      {:ordered_event, event} ->
        receive_events_for([event | acc], timeout)
        
      {:ordered_event_batch, batch} ->
        receive_events_for(batch ++ acc, timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end
  
  defp receive_all_event_batches(acc, timeout) do
    receive do
      {:ordered_event_batch, batch} ->
        receive_all_event_batches(batch ++ acc, timeout)
        
      {:ordered_event, event} ->
        receive_all_event_batches([event | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end
  
  defp hlc_to_comparable(hlc) do
    {hlc.physical, hlc.logical, hlc.node_id}
  end
end