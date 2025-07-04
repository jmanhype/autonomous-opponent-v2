#!/usr/bin/env elixir

# Script to set up security features for Task 7
# Usage: mix run scripts/setup_security.exs

require Logger

defmodule SecuritySetup do
  @moduledoc """
  Security setup script for Autonomous Opponent V2.
  
  This script:
  1. Generates encryption keys
  2. Creates sample certificates for TLS
  3. Sets up environment variables
  4. Validates security configuration
  """
  
  def run do
    Logger.info("🔐 Setting up security features for Autonomous Opponent V2...")
    
    # Generate encryption key if not present
    setup_encryption_key()
    
    # Generate sample TLS certificates
    setup_tls_certificates()
    
    # Set up Vault configuration
    setup_vault_config()
    
    # Generate sample API keys
    setup_sample_keys()
    
    # Validate configuration
    validate_setup()
    
    Logger.info("✅ Security setup complete!")
    print_next_steps()
  end
  
  defp setup_encryption_key do
    case System.get_env("ENCRYPTION_KEY") do
      nil ->
        key = :crypto.strong_rand_bytes(32) |> Base.encode64()
        Logger.info("🔑 Generated new encryption key")
        Logger.warn("""
        
        IMPORTANT: Save this encryption key securely!
        ENCRYPTION_KEY=#{key}
        
        Add to your .env file or secure configuration.
        """)
        
      _ ->
        Logger.info("✓ Encryption key already configured")
    end
  end
  
  defp setup_tls_certificates do
    cert_dir = "priv/certs"
    File.mkdir_p!(cert_dir)
    
    key_file = Path.join(cert_dir, "selfsigned_key.pem")
    cert_file = Path.join(cert_dir, "selfsigned_cert.pem")
    
    if not File.exists?(key_file) or not File.exists?(cert_file) do
      Logger.info("📜 Generating self-signed TLS certificates...")
      
      # Generate self-signed certificate (for development only)
      System.cmd("openssl", [
        "req", "-x509", "-nodes", "-days", "365", "-newkey", "rsa:2048",
        "-keyout", key_file,
        "-out", cert_file,
        "-subj", "/C=US/ST=State/L=City/O=AutonomousOpponent/CN=localhost"
      ])
      
      Logger.info("✓ Generated TLS certificates in #{cert_dir}")
      Logger.warn("⚠️  These are self-signed certificates for development only!")
    else
      Logger.info("✓ TLS certificates already exist")
    end
  end
  
  defp setup_vault_config do
    if System.get_env("VAULT_ENABLED") == "true" do
      Logger.info("🏦 Vault integration is enabled")
      
      if is_nil(System.get_env("VAULT_TOKEN")) do
        Logger.warn("""
        
        ⚠️  VAULT_TOKEN is not set!
        
        To use HashiCorp Vault:
        1. Install Vault: brew install vault
        2. Start Vault dev server: vault server -dev
        3. Set environment variables:
           export VAULT_ADDR='http://127.0.0.1:8200'
           export VAULT_TOKEN='<dev-root-token>'
           export VAULT_ENABLED=true
        """)
      else
        Logger.info("✓ Vault token configured")
      end
    else
      Logger.info("ℹ️  Vault integration disabled (using environment variables)")
    end
  end
  
  defp setup_sample_keys do
    sample_keys = %{
      "OPENAI_API_KEY" => "sk-sample-" <> random_string(48),
      "GUARDIAN_SECRET" => random_string(64)
    }
    
    Logger.info("\n📋 Sample API keys for development:")
    Enum.each(sample_keys, fn {key, value} ->
      Logger.info("#{key}=#{value}")
    end)
    
    Logger.warn("\n⚠️  These are sample keys only! Replace with real values in production.")
  end
  
  defp validate_setup do
    Logger.info("\n🔍 Validating security configuration...")
    
    checks = [
      {"Encryption key", System.get_env("ENCRYPTION_KEY") != nil},
      {"TLS certificates", File.exists?("priv/certs/selfsigned_cert.pem")},
      {"Secret key base", System.get_env("SECRET_KEY_BASE") != nil},
      {"Database URL", System.get_env("DATABASE_URL") != nil}
    ]
    
    all_passed = Enum.all?(checks, fn {name, passed} ->
      if passed do
        Logger.info("✓ #{name}")
      else
        Logger.warn("✗ #{name} - not configured")
      end
      passed
    end)
    
    if not all_passed do
      Logger.warn("\n⚠️  Some security features are not fully configured")
    end
  end
  
  defp print_next_steps do
    Logger.info("""
    
    🚀 Next Steps:
    
    1. Update your .env file with the generated keys
    2. Configure your production secrets in Vault or environment
    3. Enable TLS in production:
       export TLS_ENABLED=true
       export TLS_PORT=443
       export TLS_KEY_PATH=/path/to/key.pem
       export TLS_CERT_PATH=/path/to/cert.pem
    
    4. Test security features:
       mix test --only integration
    
    5. Monitor security events:
       - Check logs for rotation events
       - Monitor audit trails
       - Set up alerts for security breaches
    
    For more information, see docs/security/README.md
    """)
  end
  
  defp random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64(padding: false)
    |> String.slice(0, length)
  end
end

# Run the setup
SecuritySetup.run()