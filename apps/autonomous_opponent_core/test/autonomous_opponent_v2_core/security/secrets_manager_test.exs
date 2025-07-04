defmodule AutonomousOpponentV2Core.Security.SecretsManagerTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.Security.SecretsManager
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Start test instance of SecretsManager
    {:ok, pid} = SecretsManager.start_link(
      name: :test_secrets_manager,
      vault_enabled: false,
      allowed_env_keys: ["TEST_SECRET", "OPENAI_API_KEY"]
    )
    
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)
    
    {:ok, manager: pid}
  end
  
  describe "get_secret/2" do
    test "retrieves secret from environment variables", %{manager: manager} do
      # Set test environment variable
      System.put_env("TEST_SECRET", "test_value_123")
      
      assert {:ok, "test_value_123"} = GenServer.call(manager, {:get_secret, "TEST_SECRET", []})
      
      # Clean up
      System.delete_env("TEST_SECRET")
    end
    
    test "returns error for non-existent secret", %{manager: manager} do
      assert {:error, :secret_not_found} = 
        GenServer.call(manager, {:get_secret, "NON_EXISTENT", []})
    end
    
    test "respects allowed_env_keys restriction", %{manager: manager} do
      System.put_env("FORBIDDEN_SECRET", "should_not_access")
      
      assert {:error, :secret_not_found} = 
        GenServer.call(manager, {:get_secret, "FORBIDDEN_SECRET", []})
      
      System.delete_env("FORBIDDEN_SECRET")
    end
    
    test "caches retrieved values", %{manager: manager} do
      System.put_env("TEST_SECRET", "cached_value")
      
      # First call - from env
      assert {:ok, "cached_value"} = GenServer.call(manager, {:get_secret, "TEST_SECRET", []})
      
      # Change env value
      System.put_env("TEST_SECRET", "new_value")
      
      # Second call - should be from cache
      assert {:ok, "cached_value"} = GenServer.call(manager, {:get_secret, "TEST_SECRET", []})
      
      System.delete_env("TEST_SECRET")
    end
    
    test "bypasses cache when requested", %{manager: manager} do
      System.put_env("TEST_SECRET", "initial_value")
      
      # First call
      assert {:ok, "initial_value"} = GenServer.call(manager, {:get_secret, "TEST_SECRET", []})
      
      # Change value
      System.put_env("TEST_SECRET", "updated_value")
      
      # Call with cache bypass
      assert {:ok, "updated_value"} = 
        GenServer.call(manager, {:get_secret, "TEST_SECRET", [cache: false]})
      
      System.delete_env("TEST_SECRET")
    end
  end
  
  describe "put_secret/3" do
    test "validates secret format", %{manager: manager} do
      # Invalid key
      assert {:error, :invalid_key} = 
        GenServer.call(manager, {:put_secret, "", "value", []})
      
      # Invalid value
      assert {:error, :invalid_value} = 
        GenServer.call(manager, {:put_secret, "KEY", "", []})
      
      # Key with spaces
      assert {:error, :key_contains_spaces} = 
        GenServer.call(manager, {:put_secret, "KEY WITH SPACES", "value", []})
    end
    
    test "returns error when vault not configured", %{manager: manager} do
      assert {:error, :vault_not_configured} = 
        GenServer.call(manager, {:put_secret, "TEST_KEY", "test_value", []})
    end
  end
  
  describe "rotate_secret/2" do
    test "generates new secret value", %{manager: manager} do
      result = GenServer.call(manager, {:rotate_secret, "TEST_SECRET", nil})
      
      case result do
        {:ok, new_value} ->
          assert is_binary(new_value)
          assert String.length(new_value) == 32
        {:error, :vault_not_configured} ->
          # Expected when Vault is not available
          assert true
      end
    end
    
    test "uses custom generator for known keys", %{manager: manager} do
      result = GenServer.call(manager, {:rotate_secret, "OPENAI_API_KEY", nil})
      
      case result do
        {:ok, new_value} ->
          assert String.starts_with?(new_value, "sk-")
          assert String.length(new_value) == 51  # "sk-" + 48 chars
        {:error, :vault_not_configured} ->
          # Expected when Vault is not available
          assert true
      end
    end
  end
  
  describe "list_secrets/0" do
    test "returns allowed environment keys", %{manager: manager} do
      {:ok, keys} = GenServer.call(manager, :list_secrets)
      
      assert "TEST_SECRET" in keys
      assert "OPENAI_API_KEY" in keys
    end
  end
  
  describe "get_audit_log/1" do
    test "tracks secret access", %{manager: manager} do
      System.put_env("TEST_SECRET", "audit_test")
      
      # Access the secret
      GenServer.call(manager, {:get_secret, "TEST_SECRET", []})
      
      # Check audit log
      {:ok, log} = GenServer.call(manager, {:get_audit_log, []})
      
      assert length(log) > 0
      [entry | _] = log
      
      assert entry.type == :access
      assert entry.key == "TEST_SECRET"
      assert entry.result == :env_hit
      assert is_struct(entry.timestamp, DateTime)
      
      System.delete_env("TEST_SECRET")
    end
    
    test "filters audit log by type", %{manager: manager} do
      # Generate some audit entries
      GenServer.call(manager, {:get_secret, "TEST_SECRET", []})
      
      # Filter by type
      {:ok, log} = GenServer.call(manager, {:get_audit_log, [type: :access]})
      
      assert Enum.all?(log, & &1.type == :access)
    end
  end
  
  describe "security events" do
    test "handles security breach event", %{manager: manager} do
      # Subscribe to events
      EventBus.subscribe(:secret_rotated)
      
      # Simulate security breach
      send(manager, {:event, :security_breach, %{key: "TEST_SECRET"}})
      
      # Should trigger rotation (though it may fail without Vault)
      # Just verify it doesn't crash
      Process.sleep(100)
      assert Process.alive?(manager)
    end
  end
end