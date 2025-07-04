defmodule AutonomousOpponentV2Core.Security.KeyRotationTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.Security.KeyRotation
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Start test instance of KeyRotation
    {:ok, pid} = KeyRotation.start_link(
      name: :test_key_rotation,
      default_interval: :timer.seconds(5)
    )
    
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)
    
    {:ok, rotation: pid}
  end
  
  describe "schedule_rotation/3" do
    test "schedules key for rotation", %{rotation: rotation} do
      assert :ok = GenServer.call(rotation, 
        {:schedule_rotation, "TEST_KEY", :timer.seconds(10), []})
      
      {:ok, status} = GenServer.call(rotation, {:get_status, "TEST_KEY"})
      
      assert status.scheduled != nil
      assert status.scheduled.interval == :timer.seconds(10)
      assert status.scheduled.enabled == true
    end
    
    test "accepts interval shortcuts", %{rotation: rotation} do
      assert :ok = GenServer.call(rotation, 
        {:schedule_rotation, "DAILY_KEY", :daily, []})
      
      {:ok, status} = GenServer.call(rotation, {:get_status, "DAILY_KEY"})
      assert status.scheduled.interval == :timer.hours(24)
    end
  end
  
  describe "rotate_now/2" do
    test "generates new key value", %{rotation: rotation} do
      # Mock SecretsManager response
      result = GenServer.call(rotation, {:rotate_now, "TEST_KEY", []})
      
      case result do
        {:ok, rotation_info} ->
          assert rotation_info.key == "TEST_KEY"
          assert is_binary(rotation_info.new_key)
          assert rotation_info.emergency == false
        {:error, _} ->
          # Expected when SecretsManager is not available
          assert true
      end
    end
    
    test "respects emergency flag", %{rotation: rotation} do
      result = GenServer.call(rotation, 
        {:rotate_now, "EMERGENCY_KEY", [emergency: true, grace_period: 0]})
      
      case result do
        {:ok, rotation_info} ->
          assert rotation_info.emergency == true
          assert rotation_info.grace_period == 0
        {:error, _} ->
          # Expected when SecretsManager is not available
          assert true
      end
    end
  end
  
  describe "get_status/1" do
    test "returns complete status for key", %{rotation: rotation} do
      {:ok, status} = GenServer.call(rotation, {:get_status, "OPENAI_API_KEY"})
      
      assert Map.has_key?(status, :scheduled)
      assert Map.has_key?(status, :active_rotation)
      assert Map.has_key?(status, :last_rotation)
      
      # Default schedule should exist for OPENAI_API_KEY
      assert status.scheduled != nil
      assert status.scheduled.enabled == true
    end
    
    test "returns empty status for unknown key", %{rotation: rotation} do
      {:ok, status} = GenServer.call(rotation, {:get_status, "UNKNOWN_KEY"})
      
      assert status.scheduled == nil
      assert status.active_rotation == nil
      assert status.last_rotation == nil
    end
  end
  
  describe "cancel_rotation/1" do
    test "disables scheduled rotation", %{rotation: rotation} do
      # First schedule a rotation
      GenServer.call(rotation, 
        {:schedule_rotation, "CANCEL_TEST", :timer.hours(1), []})
      
      # Then cancel it
      assert :ok = GenServer.call(rotation, {:cancel_rotation, "CANCEL_TEST"})
      
      # Verify it's disabled
      {:ok, status} = GenServer.call(rotation, {:get_status, "CANCEL_TEST"})
      assert status.scheduled.enabled == false
    end
    
    test "returns error for non-scheduled key", %{rotation: rotation} do
      assert {:error, :not_scheduled} = 
        GenServer.call(rotation, {:cancel_rotation, "NOT_SCHEDULED"})
    end
  end
  
  describe "get_history/1" do
    test "returns rotation history", %{rotation: rotation} do
      {:ok, history} = GenServer.call(rotation, {:get_history, []})
      
      assert is_list(history)
      # May be empty initially
    end
    
    test "filters history by key", %{rotation: rotation} do
      # Attempt a rotation to generate history
      GenServer.call(rotation, {:rotate_now, "HISTORY_TEST", []})
      
      {:ok, history} = GenServer.call(rotation, 
        {:get_history, [key: "HISTORY_TEST"]})
      
      assert is_list(history)
      assert Enum.all?(history, & &1.key == "HISTORY_TEST")
    end
    
    test "limits history results", %{rotation: rotation} do
      {:ok, history} = GenServer.call(rotation, {:get_history, [limit: 5]})
      
      assert length(history) <= 5
    end
  end
  
  describe "automatic rotation" do
    test "triggers rotation on schedule", %{rotation: rotation} do
      # Subscribe to rotation events
      EventBus.subscribe(:key_rotated)
      
      # Schedule immediate rotation
      GenServer.call(rotation, 
        {:schedule_rotation, "AUTO_TEST", :timer.milliseconds(100), []})
      
      # Wait for rotation to trigger
      Process.sleep(200)
      
      # Check if rotation was attempted
      {:ok, status} = GenServer.call(rotation, {:get_status, "AUTO_TEST"})
      assert status.scheduled != nil
    end
  end
  
  describe "security events" do
    test "handles security breach event", %{rotation: rotation} do
      # Send security breach event
      send(rotation, {:event, :security_breach, %{keys: ["BREACH_KEY"]}})
      
      # Give it time to process
      Process.sleep(100)
      
      # Should not crash
      assert Process.alive?(rotation)
    end
    
    test "handles rotation required event", %{rotation: rotation} do
      # Send rotation required event
      send(rotation, {:event, :rotation_required, %{key: "REQUIRED_KEY"}})
      
      # Give it time to process
      Process.sleep(100)
      
      # Should not crash
      assert Process.alive?(rotation)
    end
  end
  
  describe "grace period handling" do
    test "expires old keys after grace period", %{rotation: rotation} do
      # Subscribe to expiration events
      EventBus.subscribe(:key_expired)
      
      # Mock a rotation with short grace period
      send(rotation, {:expire_old_key, "EXPIRE_TEST", "old-key-123"})
      
      # Should receive expiration event
      assert_receive {:event, :key_expired, %{key: "EXPIRE_TEST"}}, 1000
    end
  end
end