#!/usr/bin/env elixir

# Simple test showing HLC module works correctly without starting full application
Mix.install([
  {:jason, "~> 1.4"}
])

# Load the module directly
Code.require_file("apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/core/hybrid_logical_clock.ex")

defmodule SimpleHLCTest do
  alias AutonomousOpponentV2Core.Core.HybridLogicalClock
  
  def run do
    IO.puts("=== Simple HLC Test ===")
    
    # Start HLC server
    {:ok, _pid} = HybridLogicalClock.start_link(node_id: "test-node")
    
    test_basic_functionality()
    test_event_ids()
    test_timestamp_ordering()
    test_string_conversion()
    test_comparison_functions()
    
    IO.puts("\n=== All Tests Passed! ===")
  end
  
  def test_basic_functionality do
    IO.puts("\n1. Testing basic HLC functionality:")
    
    # Get current timestamp
    {:ok, hlc1} = HybridLogicalClock.now()
    IO.puts("   First timestamp: #{HybridLogicalClock.to_string(hlc1)}")
    
    # Small delay
    Process.sleep(5)
    
    # Get another timestamp
    {:ok, hlc2} = HybridLogicalClock.now()
    IO.puts("   Second timestamp: #{HybridLogicalClock.to_string(hlc2)}")
    
    # Verify ordering
    is_ordered = HybridLogicalClock.before?(hlc1, hlc2)
    IO.puts("   Timestamps properly ordered: #{is_ordered}")
    
    unless is_ordered do
      raise "Timestamps not properly ordered!"
    end
  end
  
  def test_event_ids do
    IO.puts("\n2. Testing event ID generation:")
    
    # Create some test events
    {:ok, id1} = HybridLogicalClock.event_id(%{type: :test, data: "hello"})
    {:ok, id2} = HybridLogicalClock.event_id(%{type: :test, data: "world"})
    {:ok, id3} = HybridLogicalClock.event_id(%{type: :test, data: "hello"})
    
    IO.puts("   Event ID 1: #{String.slice(id1, 0..20)}...")
    IO.puts("   Event ID 2: #{String.slice(id2, 0..20)}...")
    IO.puts("   Event ID 3: #{String.slice(id3, 0..20)}...")
    
    # Different events should have different IDs
    if id1 == id2 do
      raise "Different events should have different IDs!"
    end
    
    IO.puts("   ✓ Different events have different IDs")
  end
  
  def test_timestamp_ordering do
    IO.puts("\n3. Testing timestamp ordering:")
    
    # Create a sequence of timestamps
    timestamps = Enum.map(1..5, fn i ->
      {:ok, hlc} = HybridLogicalClock.now()
      Process.sleep(1)
      {i, hlc}
    end)
    
    # Verify they're in order
    ordered = Enum.reduce(timestamps, {true, nil}, fn {i, hlc}, {acc, prev} ->
      case prev do
        nil -> {acc, hlc}
        prev_hlc -> 
          is_ordered = HybridLogicalClock.before?(prev_hlc, hlc)
          {acc and is_ordered, hlc}
      end
    end)
    
    case ordered do
      {true, _} -> IO.puts("   ✓ All timestamps properly ordered")
      {false, _} -> raise "Timestamps not properly ordered!"
    end
  end
  
  def test_string_conversion do
    IO.puts("\n4. Testing string conversion:")
    
    {:ok, original} = HybridLogicalClock.now()
    str = HybridLogicalClock.to_string(original)
    {:ok, parsed} = HybridLogicalClock.from_string(str)
    
    if HybridLogicalClock.equal?(original, parsed) do
      IO.puts("   ✓ String conversion works correctly")
    else
      raise "String conversion failed!"
    end
  end
  
  def test_comparison_functions do
    IO.puts("\n5. Testing comparison functions:")
    
    {:ok, hlc1} = HybridLogicalClock.now()
    Process.sleep(1)
    {:ok, hlc2} = HybridLogicalClock.now()
    
    # Test all comparison functions
    before = HybridLogicalClock.before?(hlc1, hlc2)
    is_after = HybridLogicalClock.after?(hlc2, hlc1)
    equal = HybridLogicalClock.equal?(hlc1, hlc1)
    
    if before and is_after and equal do
      IO.puts("   ✓ All comparison functions work correctly")
    else
      raise "Comparison functions failed!"
    end
  end
end

# Run the test
try do
  SimpleHLCTest.run()
rescue
  e ->
    IO.puts("Test failed: #{inspect(e)}")
    System.halt(1)
end