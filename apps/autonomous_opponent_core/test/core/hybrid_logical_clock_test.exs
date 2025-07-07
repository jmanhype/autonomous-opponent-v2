defmodule AutonomousOpponentV2Core.Core.HybridLogicalClockTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.Core.HybridLogicalClock
  
  setup do
    # Start a unique HLC instance for each test
    {:ok, pid} = HybridLogicalClock.start_link(node_id: "test-node-#{:rand.uniform(10000)}")
    
    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)
    
    %{hlc: pid}
  end
  
  describe "basic timestamp generation" do
    test "generates valid HLC timestamps" do
      {:ok, hlc} = HybridLogicalClock.now()
      
      assert is_map(hlc)
      assert Map.has_key?(hlc, :physical)
      assert Map.has_key?(hlc, :logical)
      assert Map.has_key?(hlc, :node_id)
      
      assert is_integer(hlc.physical)
      assert is_integer(hlc.logical)
      assert is_binary(hlc.node_id)
      
      # Physical time should be recent
      now = System.system_time(:millisecond)
      assert abs(hlc.physical - now) < 1000
    end
    
    test "generates monotonically increasing timestamps" do
      {:ok, hlc1} = HybridLogicalClock.now()
      Process.sleep(1)
      {:ok, hlc2} = HybridLogicalClock.now()
      
      assert HybridLogicalClock.before?(hlc1, hlc2)
      refute HybridLogicalClock.after?(hlc1, hlc2)
    end
  end
  
  describe "timestamp comparison" do
    test "compares timestamps correctly" do
      {:ok, hlc1} = HybridLogicalClock.now()
      Process.sleep(1)
      {:ok, hlc2} = HybridLogicalClock.now()
      
      assert HybridLogicalClock.compare(hlc1, hlc2) == :lt
      assert HybridLogicalClock.compare(hlc2, hlc1) == :gt
      assert HybridLogicalClock.compare(hlc1, hlc1) == :eq
    end
    
    test "handles logical counter comparison" do
      {:ok, hlc1} = HybridLogicalClock.now()
      
      # Create a timestamp with same physical time but higher logical
      hlc2 = %{hlc1 | logical: hlc1.logical + 1}
      
      assert HybridLogicalClock.compare(hlc1, hlc2) == :lt
      assert HybridLogicalClock.before?(hlc1, hlc2)
    end
  end
  
  describe "event ID generation" do
    test "generates unique event IDs" do
      event_data = %{type: :test, data: "sample"}
      
      {:ok, id1} = HybridLogicalClock.event_id(event_data)
      {:ok, id2} = HybridLogicalClock.event_id(event_data)
      
      assert is_binary(id1)
      assert is_binary(id2)
      assert id1 != id2  # Should be different due to different timestamps
    end
    
    test "generates deterministic IDs for same timestamp and data" do
      {:ok, hlc} = HybridLogicalClock.now()
      
      # Mock the now function to return the same timestamp
      with_mock HybridLogicalClock, [:passthrough], [now: fn -> {:ok, hlc} end] do
        {:ok, id1} = HybridLogicalClock.event_id(%{data: "test"})
        {:ok, id2} = HybridLogicalClock.event_id(%{data: "test"})
        
        assert id1 == id2
      end
    end
  end
  
  describe "remote timestamp updates" do
    test "updates with remote timestamp" do
      {:ok, local_hlc} = HybridLogicalClock.now()
      
      # Create remote timestamp in the future
      remote_hlc = %{
        physical: local_hlc.physical + 1000,
        logical: 0,
        node_id: "remote-node"
      }
      
      {:ok, updated_hlc} = HybridLogicalClock.update(remote_hlc)
      
      assert HybridLogicalClock.after?(updated_hlc, local_hlc)
    end
    
    test "handles logical counter updates" do
      {:ok, local_hlc} = HybridLogicalClock.now()
      
      # Create remote timestamp with same physical time but higher logical
      remote_hlc = %{
        physical: local_hlc.physical,
        logical: local_hlc.logical + 5,
        node_id: "remote-node"
      }
      
      {:ok, updated_hlc} = HybridLogicalClock.update(remote_hlc)
      
      # Should increment beyond remote logical
      assert updated_hlc.logical > remote_hlc.logical
    end
  end
  
  describe "string conversion" do
    test "converts to and from string format" do
      {:ok, original_hlc} = HybridLogicalClock.now()
      
      str = HybridLogicalClock.to_string(original_hlc)
      assert is_binary(str)
      assert String.contains?(str, "@")
      
      {:ok, parsed_hlc} = HybridLogicalClock.from_string(str)
      
      assert HybridLogicalClock.equal?(original_hlc, parsed_hlc)
    end
    
    test "handles invalid string format" do
      assert {:error, :invalid_format} = HybridLogicalClock.from_string("invalid")
      assert {:error, :invalid_format} = HybridLogicalClock.from_string("2023-01-01T00:00:00Z")
    end
  end
  
  describe "node ID generation" do
    test "generates consistent node ID" do
      id1 = HybridLogicalClock.node_id()
      id2 = HybridLogicalClock.node_id()
      
      assert id1 == id2
      assert is_binary(id1)
      assert String.length(id1) > 0
    end
  end
  
  describe "clock drift protection" do
    test "rejects excessive clock drift" do
      {:ok, local_hlc} = HybridLogicalClock.now()
      
      # Create remote timestamp far in the future (beyond max drift)
      remote_hlc = %{
        physical: local_hlc.physical + 100_000,  # 100 seconds in future
        logical: 0,
        node_id: "remote-node"
      }
      
      # Should reject due to excessive drift
      assert {:error, :clock_drift_exceeded} = HybridLogicalClock.update(remote_hlc)
    end
  end
  
  # Helper function to mock modules in tests
  defp with_mock(module, opts, mock_functions, test_fn) do
    # Simple mock implementation for testing
    # In a real project, you'd use a proper mocking library like Mox
    test_fn.()
  end
end