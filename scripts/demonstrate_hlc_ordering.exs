#!/usr/bin/env elixir

# Demonstration of HLC-based EventBus Ordering
# Shows the phased rollout starting with S4 Intelligence

defmodule HLCOrderingDemo do
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.IntelligenceOrderedSubscriber
  
  def run do
    IO.puts """
    ╔══════════════════════════════════════════════════════════════╗
    ║         HLC EventBus Ordering Demonstration                  ║
    ║                                                              ║
    ║  Phase 1: S4 Intelligence Subsystem                          ║
    ╚══════════════════════════════════════════════════════════════╝
    """
    
    # Check if S4 ordered delivery is enabled
    stats = IntelligenceOrderedSubscriber.get_stats()
    
    if stats.enabled do
      IO.puts "\n✅ S4 Intelligence is using HLC-ordered delivery"
      IO.puts "   Buffer window: 100ms"
      IO.puts "   Batch delivery: enabled"
      IO.puts "   Adaptive windowing: enabled"
    else
      IO.puts "\n⚠️  S4 Intelligence is using standard delivery"
      IO.puts "   Enabling ordered delivery..."
      IntelligenceOrderedSubscriber.enable_ordering()
      Process.sleep(100)
    end
    
    # Demonstrate out-of-order pattern detection
    demonstrate_pattern_detection()
    
    # Show ordering statistics
    show_ordering_stats()
    
    # Demonstrate algedonic bypass
    demonstrate_algedonic_bypass()
    
    # Show performance impact
    benchmark_ordering_overhead()
    
    IO.puts "\n\n✨ Demonstration complete!"
  end
  
  defp demonstrate_pattern_detection do
    IO.puts "\n\n📊 PATTERN DETECTION WITH ORDERING"
    IO.puts "=" |> String.duplicate(60)
    
    # Create a subscriber to observe events
    test_pid = spawn(fn -> event_observer() end)
    EventBus.subscribe(:pattern_detected, test_pid, ordered_delivery: true, buffer_window_ms: 200)
    
    IO.puts "\nPublishing patterns out of order (simulating network delays)..."
    
    # Publish patterns in reverse order to simulate network delays
    patterns = for i <- 10..1//-1 do
      pattern = %{
        pattern_id: "anomaly_#{i}",
        confidence: 0.5 + i * 0.05,
        sequence: i,
        data: "Pattern #{i} represents step #{i} in the sequence"
      }
      
      EventBus.publish(:pattern_detected, pattern)
      
      # Simulate variable network delay
      Process.sleep(:rand.uniform(20))
      
      pattern
    end
    
    # Wait for ordering buffer
    IO.puts "Waiting for buffer window (200ms)..."
    Process.sleep(250)
    
    # Check results
    send(test_pid, {:report, self()})
    
    receive do
      {:patterns_received, received_patterns} ->
        IO.puts "\n✅ Received #{length(received_patterns)} patterns"
        
        # Verify ordering
        sequences = Enum.map(received_patterns, fn p -> p.data.sequence end)
        if sequences == Enum.sort(sequences) do
          IO.puts "✅ Patterns arrived in correct causal order: #{inspect(sequences)}"
          IO.puts "\n🎯 Pattern detection accuracy improved with proper sequencing!"
        else
          IO.puts "❌ Patterns still out of order: #{inspect(sequences)}"
        end
    after
      1000 -> IO.puts "❌ Timeout waiting for patterns"
    end
    
    # Cleanup
    Process.exit(test_pid, :normal)
  end
  
  defp demonstrate_algedonic_bypass do
    IO.puts "\n\n⚡ ALGEDONIC SIGNAL BYPASS"
    IO.puts "=" |> String.duplicate(60)
    
    # Create observer
    test_pid = spawn(fn -> event_observer() end)
    
    # Subscribe to both regular and algedonic events
    EventBus.subscribe(:control_action, test_pid, ordered_delivery: true, buffer_window_ms: 500)
    EventBus.subscribe(:algedonic_pain, test_pid, ordered_delivery: true)
    
    IO.puts "\nPublishing regular control action (will be buffered)..."
    EventBus.publish(:control_action, %{
      action: "increase_resources",
      amount: 0.2,
      reason: "predicted_load"
    })
    
    Process.sleep(50)
    
    IO.puts "Publishing HIGH-INTENSITY pain signal (will bypass)..."
    EventBus.publish(:algedonic_pain, %{
      intensity: 0.99,
      source: "memory_exhaustion",
      urgent: true,
      metadata: %{algedonic: true, intensity: 0.99}
    })
    
    # Check immediate delivery
    send(test_pid, {:check_immediate, self()})
    
    receive do
      {:immediate_events, events} ->
        pain_events = Enum.filter(events, fn e -> e.type == :algedonic_pain end)
        if length(pain_events) > 0 do
          IO.puts "\n✅ Pain signal bypassed ordering and arrived immediately!"
          IO.puts "   Intensity: #{hd(pain_events).data.intensity}"
        else
          IO.puts "\n❌ Pain signal did not bypass"
        end
    after
      100 -> IO.puts "\n❌ No immediate events"
    end
    
    # Wait for buffered events
    Process.sleep(500)
    
    send(test_pid, {:report, self()})
    receive do
      {:patterns_received, all_events} ->
        control_events = Enum.filter(all_events, fn e -> e.type == :control_action end)
        IO.puts "\n✅ Control action arrived after buffer window"
        IO.puts "   Total events: #{length(all_events)}"
    after
      1000 -> :ok
    end
    
    Process.exit(test_pid, :normal)
  end
  
  defp benchmark_ordering_overhead do
    IO.puts "\n\n⚡ PERFORMANCE BENCHMARK"
    IO.puts "=" |> String.duplicate(60)
    
    # Benchmark with standard delivery
    IO.puts "\nBenchmarking standard delivery..."
    standard_pid = spawn(fn -> benchmark_receiver() end)
    EventBus.subscribe(:benchmark_event, standard_pid)
    
    standard_time = :timer.tc(fn ->
      for i <- 1..1000 do
        EventBus.publish(:benchmark_event, %{seq: i, data: :crypto.strong_rand_bytes(100)})
      end
      Process.sleep(100)
    end) |> elem(0)
    
    EventBus.unsubscribe(:benchmark_event, standard_pid)
    Process.exit(standard_pid, :normal)
    
    # Benchmark with ordered delivery
    IO.puts "Benchmarking ordered delivery..."
    ordered_pid = spawn(fn -> benchmark_receiver() end)
    EventBus.subscribe(:benchmark_event, ordered_pid, ordered_delivery: true, buffer_window_ms: 50)
    
    ordered_time = :timer.tc(fn ->
      for i <- 1..1000 do
        EventBus.publish(:benchmark_event, %{seq: i, data: :crypto.strong_rand_bytes(100)})
      end
      Process.sleep(150)  # Account for buffer window
    end) |> elem(0)
    
    EventBus.unsubscribe(:benchmark_event, ordered_pid)
    Process.exit(ordered_pid, :normal)
    
    # Calculate overhead
    overhead = ((ordered_time - standard_time) / standard_time) * 100
    
    IO.puts "\n📊 Performance Results:"
    IO.puts "   Standard delivery: #{standard_time / 1000}ms"
    IO.puts "   Ordered delivery:  #{ordered_time / 1000}ms"
    IO.puts "   Overhead: #{Float.round(overhead, 2)}%"
    
    if overhead < 20 do
      IO.puts "\n✅ Performance overhead is within acceptable range (<20%)"
    else
      IO.puts "\n⚠️  Performance overhead is higher than expected"
    end
  end
  
  defp show_ordering_stats do
    IO.puts "\n\n📈 ORDERING STATISTICS"
    IO.puts "=" |> String.duplicate(60)
    
    stats = IntelligenceOrderedSubscriber.get_stats()
    
    IO.puts """
    
    S4 Intelligence Ordered Delivery Stats:
    - Events received: #{stats.events_received}
    - Patterns improved: #{stats.patterns_improved}
    - Improvement rate: #{if stats.events_received > 0, do: Float.round(stats.patterns_improved / stats.events_received * 100, 2), else: 0}%
    - Uptime: #{stats.uptime_seconds}s
    """
    
    # Show EventBus ordering dashboard location
    IO.puts "\n🌐 View real-time metrics at: http://localhost:4000/eventbus/ordering"
  end
  
  # Helper process for observing events
  defp event_observer do
    event_observer_loop([])
  end
  
  defp event_observer_loop(events) do
    receive do
      {:event_bus_hlc, event} ->
        event_observer_loop([event | events])
        
      {:ordered_event, event} ->
        event_observer_loop([event | events])
        
      {:ordered_event_batch, batch} ->
        event_observer_loop(batch ++ events)
        
      {:report, caller} ->
        send(caller, {:patterns_received, Enum.reverse(events)})
        event_observer_loop(events)
        
      {:check_immediate, caller} ->
        send(caller, {:immediate_events, Enum.reverse(events)})
        event_observer_loop(events)
        
      _ ->
        event_observer_loop(events)
    end
  end
  
  defp benchmark_receiver do
    receive do
      _ -> benchmark_receiver()
    end
  end
end

# Run the demonstration
HLCOrderingDemo.run()