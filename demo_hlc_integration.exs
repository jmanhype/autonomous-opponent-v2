#!/usr/bin/env elixir

# Demo script showing Hybrid Logical Clock integration with VSM
# Run with: elixir demo_hlc_integration.exs

Mix.install([
  {:autonomous_opponent_core, path: "./apps/autonomous_opponent_core"}
])

defmodule HLCDemo do
  @moduledoc """
  Demonstrates the Hybrid Logical Clock integration with VSM components.
  Shows how deterministic timestamps replace DateTime.utc_now() calls.
  """
  
  alias AutonomousOpponentV2Core.Core.HybridLogicalClock
  alias AutonomousOpponentV2Core.VSM.Clock
  
  def run do
    IO.puts("=== Hybrid Logical Clock Demo ===\n")
    
    # Start the HLC system
    {:ok, _pid} = HybridLogicalClock.start_link(node_id: "demo-node")
    
    demo_basic_timestamps()
    demo_event_creation()
    demo_event_ordering()
    demo_causal_relationships()
    demo_distributed_simulation()
    
    IO.puts("\n=== Demo Complete ===")
  end
  
  defp demo_basic_timestamps do
    IO.puts("1. Basic Timestamp Generation")
    IO.puts("   Instead of: DateTime.utc_now()")
    IO.puts("   We now use: HybridLogicalClock.now()")
    
    # Old way (non-deterministic)
    datetime = DateTime.utc_now()
    IO.puts("   DateTime: #{DateTime.to_iso8601(datetime)}")
    
    # New way (deterministic, causally ordered)
    {:ok, hlc} = HybridLogicalClock.now()
    IO.puts("   HLC: #{HybridLogicalClock.to_string(hlc)}")
    IO.puts("   Physical: #{hlc.physical}, Logical: #{hlc.logical}, Node: #{hlc.node_id}")
    
    IO.puts("")
  end
  
  defp demo_event_creation do
    IO.puts("2. VSM Event Creation with HLC")
    
    # Create various VSM events
    {:ok, s1_event} = Clock.create_event(:s1, :operation_complete, %{
      input: "environmental_data",
      output: "processed_variety"
    })
    
    {:ok, s2_event} = Clock.create_event(:s2, :coordination_signal, %{
      from: :s1,
      to: :s3,
      message: "anti_oscillation_active"
    })
    
    {:ok, s4_event} = Clock.create_event(:s4, :intelligence_scan, %{
      environment: "external_changes",
      adaptation_needed: true
    })
    
    IO.puts("   S1 Event: #{Clock.event_to_string(s1_event)}")
    IO.puts("   S2 Event: #{Clock.event_to_string(s2_event)}")
    IO.puts("   S4 Event: #{Clock.event_to_string(s4_event)}")
    
    IO.puts("")
  end
  
  defp demo_event_ordering do
    IO.puts("3. Deterministic Event Ordering")
    
    # Create events with small delays
    events = Enum.map(1..5, fn i ->
      {:ok, event} = Clock.create_event(:s1, :sequence_test, %{sequence: i})
      Process.sleep(1)  # Small delay
      event
    end)
    
    # Shuffle events
    shuffled = Enum.shuffle(events)
    IO.puts("   Shuffled order: #{Enum.map(shuffled, & &1.data.sequence) |> Enum.join(", ")}")
    
    # Order by HLC timestamp
    ordered = Clock.order_events(shuffled)
    IO.puts("   HLC ordered:    #{Enum.map(ordered, & &1.data.sequence) |> Enum.join(", ")}")
    
    IO.puts("")
  end
  
  defp demo_causal_relationships do
    IO.puts("4. Causal Relationships")
    
    # Create causally related events
    {:ok, cause_event} = Clock.create_event(:s1, :variety_input, %{data: "trigger"})
    
    # Simulate processing delay
    Process.sleep(5)
    
    {:ok, effect_event} = Clock.create_event(:s2, :coordination_response, %{
      triggered_by: cause_event.id,
      response: "coordinated_action"
    })
    
    IO.puts("   Cause event:  #{Clock.event_to_string(cause_event)}")
    IO.puts("   Effect event: #{Clock.event_to_string(effect_event)}")
    
    # Verify causal ordering
    is_causal = HybridLogicalClock.before?(cause_event.timestamp, effect_event.timestamp)
    IO.puts("   Causal order maintained: #{is_causal}")
    
    {:ok, age_diff} = Clock.event_age(cause_event)
    IO.puts("   Cause event age: #{age_diff}ms")
    
    IO.puts("")
  end
  
  defp demo_distributed_simulation do
    IO.puts("5. Distributed Node Simulation")
    
    # Simulate receiving timestamp from remote node
    {:ok, local_timestamp} = HybridLogicalClock.now()
    
    # Create "remote" timestamp
    remote_timestamp = %{
      physical: local_timestamp.physical + 50,  # 50ms in future
      logical: 5,
      node_id: "remote-vsm-node"
    }
    
    IO.puts("   Local timestamp:  #{HybridLogicalClock.to_string(local_timestamp)}")
    IO.puts("   Remote timestamp: #{HybridLogicalClock.to_string(remote_timestamp)}")
    
    # Synchronize with remote
    {:ok, synced_timestamp} = Clock.sync_with_remote(remote_timestamp)
    IO.puts("   Synced timestamp: #{HybridLogicalClock.to_string(synced_timestamp)}")
    
    # Verify synchronization worked
    is_after_remote = HybridLogicalClock.after?(synced_timestamp, remote_timestamp)
    IO.puts("   Synchronized correctly: #{is_after_remote}")
    
    IO.puts("")
  end
  
  def benchmark_performance do
    IO.puts("6. Performance Comparison")
    
    # Benchmark DateTime.utc_now()
    {time_datetime, _} = :timer.tc(fn ->
      Enum.each(1..1000, fn _ -> DateTime.utc_now() end)
    end)
    
    # Benchmark HybridLogicalClock.now()
    {time_hlc, _} = :timer.tc(fn ->
      Enum.each(1..1000, fn _ -> HybridLogicalClock.now() end)
    end)
    
    IO.puts("   DateTime.utc_now() x1000: #{time_datetime}μs")
    IO.puts("   HybridLogicalClock.now() x1000: #{time_hlc}μs")
    IO.puts("   Overhead: #{Float.round(time_hlc / time_datetime, 2)}x")
    
    IO.puts("")
  end
end

# Run the demo
try do
  HLCDemo.run()
rescue
  e ->
    IO.puts("Error running demo: #{inspect(e)}")
    IO.puts("Make sure the VSM system is available")
end