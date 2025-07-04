# Security Migration Guide

This guide helps you migrate from plain environment variables to the secure secrets management system implemented in Task 7.

## Overview

The migration process involves:
1. Setting up encryption infrastructure
2. Migrating existing secrets
3. Updating application configuration
4. Verifying the migration
5. Cleaning up old configurations

## Prerequisites

- Elixir ~> 1.16
- PostgreSQL running
- Access to current environment variables
- Backup of all sensitive data

## Step-by-Step Migration

### 1. Generate Encryption Keys

First, generate the required encryption keys:

```bash
# Run the security setup script
mix run scripts/setup_security.exs

# This will output a base64-encoded encryption key
# Save this securely - you'll need it for all environments
```

**Important**: Store the encryption key in a secure location. Loss of this key means loss of all encrypted data.

### 2. Set Up Environment

Create or update your `.env` file:

```bash
# Core security settings
ENCRYPTION_KEY=<your-generated-key>

# Optional: Enable Vault for production
VAULT_ENABLED=false  # Set to true when ready
VAULT_ADDR=http://localhost:8200
VAULT_TOKEN=<your-vault-token>

# Existing secrets (will be migrated)
OPENAI_API_KEY=sk-your-existing-key
DATABASE_URL=postgres://user:pass@localhost:5432/db
```

### 3. Update Application Configuration

Ensure your `config/runtime.exs` includes security configuration:

```elixir
# Security configuration
config :autonomous_opponent_core, :security,
  vault_enabled: System.get_env("VAULT_ENABLED", "false") == "true",
  allowed_env_keys: [
    "OPENAI_API_KEY",
    "DATABASE_URL",
    "GUARDIAN_SECRET",
    # Add other allowed keys
  ]
```

### 4. Migrate Existing Secrets

#### Option A: Automatic Migration (Recommended)

The system automatically migrates allowed environment variables:

```bash
# Start the application
iex -S mix phx.server

# Verify secrets are accessible
iex> SecretsManager.get_secret("OPENAI_API_KEY")
{:ok, "sk-your-existing-key"}
```

#### Option B: Manual Migration

For custom secrets or non-environment variables:

```elixir
# In IEx console
alias AutonomousOpponentV2Core.Security.SecretsManager

# Migrate individual secrets
SecretsManager.put_secret("CUSTOM_SECRET", "secret_value")

# Migrate with metadata
SecretsManager.put_secret("API_KEY", "value", [
  service: "external_api",
  rotation_required: true
])
```

### 5. Update Database Fields

If you have sensitive data in database fields:

```elixir
# Update your schemas to use encrypted fields
defmodule MyApp.Credential do
  use Ecto.Schema
  
  schema "credentials" do
    field :service_name, :string
    # Change from :string to encrypted type
    field :api_key, AutonomousOpponentV2Core.Security.Encryption.EncryptedString
    field :config, AutonomousOpponentV2Core.Security.Encryption.EncryptedMap
    
    timestamps()
  end
end
```

Create a migration to re-encrypt existing data:

```elixir
defmodule MyApp.Repo.Migrations.EncryptCredentials do
  use Ecto.Migration
  
  def up do
    # Fetch all credentials
    credentials = MyApp.Repo.all(MyApp.Credential)
    
    # Re-save to trigger encryption
    Enum.each(credentials, fn cred ->
      cred
      |> Ecto.Changeset.change(%{})
      |> MyApp.Repo.update!()
    end)
  end
  
  def down do
    # Encryption is transparent, no action needed
  end
end
```

### 6. Enable Key Rotation

Set up automatic key rotation for critical secrets:

```elixir
# In your application startup or a scheduled task
alias AutonomousOpponentV2Core.Security.KeyRotation

# Schedule monthly rotation for API keys
KeyRotation.schedule_rotation("OPENAI_API_KEY", :monthly,
  grace_period: :timer.hours(48)
)

# Schedule quarterly rotation for auth secrets
KeyRotation.schedule_rotation("GUARDIAN_SECRET", :quarterly,
  grace_period: :timer.hours(72)
)
```

### 7. Verify Migration

Run verification checks:

```elixir
# Check all secrets are accessible
iex> SecretsManager.list_secrets()
{:ok, ["OPENAI_API_KEY", "DATABASE_URL", ...]}

# Verify encryption is working
iex> Encryption.encrypt("test")
{:ok, encrypted}

iex> Encryption.decrypt(encrypted)
{:ok, "test"}

# Check rotation status
iex> KeyRotation.get_status("OPENAI_API_KEY")
{:ok, %{scheduled: %{...}, last_rotation: nil}}
```

### 8. Clean Up

Once migration is verified:

1. **Remove plain text secrets** from configuration files
2. **Update deployment scripts** to use encrypted configuration
3. **Rotate all keys** that were previously in plain text
4. **Enable audit logging** for compliance

```elixir
# Rotate all migrated keys
["OPENAI_API_KEY", "GUARDIAN_SECRET", ...]
|> Enum.each(&KeyRotation.rotate_now/1)
```

## Rollback Plan

If issues occur during migration:

1. **Keep original environment variables** until migration is verified
2. **Disable encryption** by removing ENCRYPTION_KEY
3. **Revert schema changes** if database encryption was enabled
4. **Restore from backup** if data corruption occurs

## Production Migration

### Additional Steps for Production

1. **Set up HashiCorp Vault**:
   ```bash
   # Initialize Vault
   vault operator init
   
   # Create secrets engine
   vault secrets enable -path=autonomous-opponent kv-v2
   
   # Set initial secrets
   vault kv put autonomous-opponent/api-keys \
     openai_key=sk-production-key
   ```

2. **Enable TLS 1.3**:
   ```bash
   # Set in production environment
   TLS_ENABLED=true
   TLS_KEY_PATH=/path/to/key.pem
   TLS_CERT_PATH=/path/to/cert.pem
   ```

3. **Configure monitoring**:
   - Set up alerts for rotation failures
   - Monitor Vault connectivity
   - Track secret access patterns

### Zero-Downtime Migration

For production systems requiring zero downtime:

1. **Deploy security code** without enabling features
2. **Run migration** in background
3. **Switch to encrypted access** gradually
4. **Monitor for errors** during transition
5. **Complete cutover** when stable

## Common Issues

### "Encryption key not found"
- Ensure ENCRYPTION_KEY is set in environment
- Check key format (base64, 32 bytes)

### "Cannot decrypt existing data"
- Verify using same encryption key
- Check data wasn't corrupted
- Ensure proper Ecto type in schema

### "Vault connection failed"
- Verify Vault is running
- Check network connectivity
- Validate authentication token

### "Key rotation failed"
- Check service-specific key format
- Verify API credentials are valid
- Review rotation logs for details

## Best Practices

1. **Test in staging first** - Always migrate staging before production
2. **Backup everything** - Including encryption keys and current secrets
3. **Monitor closely** - Watch logs during migration
4. **Rotate after migration** - Change all keys that were in plain text
5. **Document key storage** - Ensure team knows where keys are stored

## Next Steps

After successful migration:

1. Review [Security README](./README.md) for usage patterns
2. Set up [Vault in production](./VAULT_SETUP.md)
3. Ensure [compliance requirements](./COMPLIANCE.md) are met
4. Schedule regular security audits
5. Train team on new security procedures

## Support

For migration assistance:
- Check application logs: `tail -f log/dev.log`
- Review security supervisor: `Supervisor.which_children(Security.Supervisor)`
- Enable debug logging: `config :logger, level: :debug`