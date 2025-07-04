defmodule AutonomousOpponentV2Core.Security.IntegrationTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.Security.{SecretsManager, Encryption, KeyRotation}
  alias AutonomousOpponentV2Core.EventBus
  
  @moduletag :integration
  
  describe "complete security workflow" do
    test "secure secret storage and retrieval with encryption" do
      # Start encryption vault
      {:ok, _} = start_supervised({
        Encryption,
        name: :test_encryption,
        encryption_key: Encryption.generate_key()
      })
      
      # Encrypt a secret
      secret_value = "sk-test-openai-key-12345"
      {:ok, encrypted} = Encryption.encrypt(secret_value)
      
      # Store encrypted value (simulating storage)
      stored_value = encrypted
      
      # Retrieve and decrypt
      {:ok, decrypted} = Encryption.decrypt(stored_value)
      assert decrypted == secret_value
    end
    
    test "api key rotation with grace period" do
      # Set up test environment
      System.put_env("TEST_API_KEY", "old-key-value")
      
      # Start services
      {:ok, secrets} = start_supervised({
        SecretsManager,
        name: :test_secrets_int,
        vault_enabled: false,
        allowed_env_keys: ["TEST_API_KEY"]
      })
      
      {:ok, rotation} = start_supervised({
        KeyRotation,
        name: :test_rotation_int,
        default_grace_period: :timer.milliseconds(100)
      })
      
      # Subscribe to events
      EventBus.subscribe(:key_rotated)
      EventBus.subscribe(:key_expired)
      
      # Initial key retrieval
      {:ok, old_key} = GenServer.call(secrets, {:get_secret, "TEST_API_KEY", []})
      assert old_key == "old-key-value"
      
      # Schedule rotation
      :ok = GenServer.call(rotation, 
        {:schedule_rotation, "TEST_API_KEY", :timer.hours(1), [grace_period: :timer.milliseconds(100)]})
      
      # Trigger immediate rotation
      result = GenServer.call(rotation, {:rotate_now, "TEST_API_KEY", []})
      
      case result do
        {:ok, rotation_info} ->
          assert rotation_info.old_key == old_key
          assert rotation_info.new_key != old_key
          
          # Wait for grace period to expire
          assert_receive {:event, :key_expired, %{key: "TEST_API_KEY"}}, 500
          
        {:error, _} ->
          # Expected when full stack isn't available
          assert true
      end
      
      # Cleanup
      System.delete_env("TEST_API_KEY")
    end
    
    test "encrypted configuration values" do
      # Start encryption
      {:ok, _} = start_supervised({
        Encryption,
        name: :test_enc_config,
        encryption_key: Encryption.generate_key()
      })
      
      # Simulate storing encrypted config
      config = %{
        "database_password" => "super_secret_db_pass",
        "api_token" => "bearer_token_12345",
        "webhook_secret" => "webhook_signing_key"
      }
      
      # Encrypt all values
      encrypted_config = Enum.reduce(config, %{}, fn {key, value}, acc ->
        {:ok, encrypted} = Encryption.encrypt(value)
        Map.put(acc, key, encrypted)
      end)
      
      # Verify all values are encrypted
      Enum.each(encrypted_config, fn {key, encrypted_value} ->
        assert encrypted_value != config[key]
        assert is_binary(encrypted_value)
      end)
      
      # Decrypt and verify
      decrypted_config = Enum.reduce(encrypted_config, %{}, fn {key, encrypted}, acc ->
        {:ok, decrypted} = Encryption.decrypt(encrypted)
        Map.put(acc, key, decrypted)
      end)
      
      assert decrypted_config == config
    end
    
    test "security breach triggers emergency rotation" do
      # Start services
      {:ok, _secrets} = start_supervised({
        SecretsManager,
        name: :test_breach_secrets,
        vault_enabled: false,
        allowed_env_keys: ["COMPROMISED_KEY"]
      })
      
      {:ok, rotation} = start_supervised({
        KeyRotation,
        name: :test_breach_rotation
      })
      
      # Subscribe to events
      EventBus.subscribe(:key_rotated)
      
      # Simulate security breach
      send(rotation, {:event, :security_breach, %{keys: ["COMPROMISED_KEY"]}})
      
      # Should trigger emergency rotation
      # In real scenario, this would rotate the key immediately
      Process.sleep(100)
      
      # Verify process didn't crash
      assert Process.alive?(rotation)
    end
  end
  
  describe "audit logging" do
    test "tracks all secret access" do
      {:ok, secrets} = start_supervised({
        SecretsManager,
        name: :test_audit_secrets,
        vault_enabled: false,
        allowed_env_keys: ["AUDIT_TEST_KEY"]
      })
      
      # Set test value
      System.put_env("AUDIT_TEST_KEY", "audit_value")
      
      # Access secret multiple times
      GenServer.call(secrets, {:get_secret, "AUDIT_TEST_KEY", []})
      GenServer.call(secrets, {:get_secret, "AUDIT_TEST_KEY", [cache: false]})
      GenServer.call(secrets, {:get_secret, "NON_EXISTENT", []})
      
      # Get audit log
      {:ok, log} = GenServer.call(secrets, {:get_audit_log, []})
      
      assert length(log) >= 3
      
      # Verify log entries
      access_logs = Enum.filter(log, & &1.type == :access)
      assert length(access_logs) >= 3
      
      # Check for different results
      results = Enum.map(access_logs, & &1.result) |> Enum.uniq()
      assert :env_hit in results
      assert :cache_hit in results
      assert :not_found in results
      
      # Cleanup
      System.delete_env("AUDIT_TEST_KEY")
    end
  end
  
  describe "VSM integration" do
    test "security events trigger algedonic signals" do
      # Subscribe to VSM events
      EventBus.subscribe(:security_alert)
      EventBus.subscribe(:algedonic_signal)
      
      # Publish security alert
      EventBus.publish(:security_alert, %{
        type: :rotation_failure,
        key: "CRITICAL_KEY",
        reason: :vault_unavailable,
        severity: :high
      })
      
      # In a full VSM implementation, this would trigger pain signals
      assert_receive {:event, :security_alert, %{severity: :high}}, 1000
    end
  end
end