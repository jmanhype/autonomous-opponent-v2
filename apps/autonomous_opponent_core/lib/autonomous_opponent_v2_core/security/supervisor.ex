defmodule AutonomousOpponentV2Core.Security.Supervisor do
  @moduledoc """
  Supervisor for all security-related processes.
  
  This supervisor manages:
  - Secrets Manager
  - Vault Client
  - Encryption Vault
  - Key Rotation Service
  
  The supervisor ensures proper startup order and handles
  failures with appropriate restart strategies.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      # Encryption vault must start first
      {AutonomousOpponentV2Core.Security.Encryption, 
        name: AutonomousOpponentV2Core.Security.Encryption,
        encryption_key: get_encryption_key()
      },
      
      # Vault client (may fail if Vault not available)
      {AutonomousOpponentV2Core.Security.VaultClient,
        get_vault_config()
      },
      
      # Secrets manager depends on Vault client
      {AutonomousOpponentV2Core.Security.SecretsManager,
        name: AutonomousOpponentV2Core.Security.SecretsManager,
        vault_enabled: vault_enabled?()
      },
      
      # Key rotation depends on secrets manager
      {AutonomousOpponentV2Core.Security.KeyRotation,
        name: AutonomousOpponentV2Core.Security.KeyRotation
      }
    ]
    
    # Use rest_for_one strategy so if Vault fails, 
    # dependent services are restarted
    Supervisor.init(children, strategy: :rest_for_one)
  end
  
  defp get_encryption_key do
    # Try to get from environment, generate if not present
    case System.get_env("ENCRYPTION_KEY") do
      nil ->
        key = AutonomousOpponentV2Core.Security.Encryption.generate_key()
        
        # WARNING: In production, this should be persisted securely
        IO.puts("WARNING: Generated new encryption key. This should be persisted securely!")
        
        key
        
      key ->
        key
    end
  end
  
  defp get_vault_config do
    %{
      address: System.get_env("VAULT_ADDR") || "http://localhost:8200",
      token: System.get_env("VAULT_TOKEN"),
      namespace: System.get_env("VAULT_NAMESPACE") || "autonomous-opponent",
      engine: System.get_env("VAULT_ENGINE") || "secret",
      kv_version: 2
    }
  end
  
  defp vault_enabled? do
    System.get_env("VAULT_ENABLED") == "true" && System.get_env("VAULT_TOKEN") != nil
  end
end