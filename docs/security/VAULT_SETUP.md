# HashiCorp Vault Setup Guide

This guide walks through setting up HashiCorp Vault for production use with the Autonomous Opponent security system.

## Overview

HashiCorp Vault provides:
- Centralized secrets management
- Dynamic secret generation
- Detailed audit logging
- Encryption as a service
- Fine-grained access control

## Prerequisites

- Docker or Vault binary installed
- PostgreSQL for Vault storage backend
- TLS certificates for production
- Basic understanding of Vault concepts

## Installation Options

### Option 1: Docker (Development)

```bash
# Pull official Vault image
docker pull vault:latest

# Run Vault in dev mode (NEVER use in production)
docker run --cap-add=IPC_LOCK \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=dev-token' \
  -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200' \
  -p 8200:8200 \
  vault:latest
```

### Option 2: Binary Installation (Production)

```bash
# Download Vault
wget https://releases.hashicorp.com/vault/1.15.0/vault_1.15.0_linux_amd64.zip
unzip vault_1.15.0_linux_amd64.zip
sudo mv vault /usr/local/bin/

# Verify installation
vault --version
```

### Option 3: Docker Compose (Recommended)

Create `docker-compose.vault.yml`:

```yaml
version: '3.8'

services:
  vault:
    image: vault:latest
    container_name: autonomous_vault
    cap_add:
      - IPC_LOCK
    environment:
      VAULT_ADDR: 'https://0.0.0.0:8200'
      VAULT_API_ADDR: 'https://0.0.0.0:8200'
    volumes:
      - ./vault/config:/vault/config
      - ./vault/data:/vault/data
      - ./vault/logs:/vault/logs
      - ./vault/certs:/vault/certs
    ports:
      - "8200:8200"
    command: vault server -config=/vault/config/vault.hcl
```

## Configuration

### 1. Create Vault Configuration

Create `vault/config/vault.hcl`:

```hcl
ui = true
disable_mlock = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/certs/vault.crt"
  tls_key_file  = "/vault/certs/vault.key"
}

storage "postgresql" {
  connection_url = "postgres://vault:vault_pass@postgres:5432/vault?sslmode=disable"
  ha_enabled     = true
}

api_addr = "https://vault.local:8200"
cluster_addr = "https://vault.local:8201"

# Enable audit logging
audit {
  enabled = true
  path    = "/vault/logs/audit.log"
}
```

### 2. Initialize Vault

```bash
# Set environment
export VAULT_ADDR='https://localhost:8200'

# Initialize Vault (do this only once!)
vault operator init -key-shares=5 -key-threshold=3

# Save output securely! Example output:
# Unseal Key 1: abcd1234...
# Unseal Key 2: efgh5678...
# Unseal Key 3: ijkl9012...
# Unseal Key 4: mnop3456...
# Unseal Key 5: qrst7890...
# Initial Root Token: s.ABC123XYZ...
```

### 3. Unseal Vault

Vault starts sealed. Unseal with 3 of the 5 keys:

```bash
vault operator unseal # Enter Unseal Key 1
vault operator unseal # Enter Unseal Key 2
vault operator unseal # Enter Unseal Key 3

# Check status
vault status
```

### 4. Login to Vault

```bash
# Login with root token
vault login
# Enter the Initial Root Token from initialization
```

## Autonomous Opponent Setup

### 1. Enable KV Secrets Engine

```bash
# Enable KV v2 for versioned secrets
vault secrets enable -path=autonomous-opponent -version=2 kv

# Configure metadata
vault kv metadata put -mount=autonomous-opponent \
  -max-versions=10 \
  -delete-version-after="720h" \
  config
```

### 2. Create App Policy

Create `vault-app-policy.hcl`:

```hcl
# Read secrets
path "autonomous-opponent/data/*" {
  capabilities = ["read", "list"]
}

# Write secrets (for rotation)
path "autonomous-opponent/data/api-keys/*" {
  capabilities = ["create", "update", "read", "list"]
}

# Manage metadata
path "autonomous-opponent/metadata/*" {
  capabilities = ["list", "read"]
}

# Enable encryption
path "transit/encrypt/autonomous-opponent" {
  capabilities = ["create", "update"]
}

path "transit/decrypt/autonomous-opponent" {
  capabilities = ["create", "update"]
}
```

Apply the policy:

```bash
vault policy write autonomous-app vault-app-policy.hcl
```

### 3. Create App Token

```bash
# Create token with policy
vault token create \
  -policy="autonomous-app" \
  -ttl="8760h" \
  -renewable \
  -display-name="autonomous-opponent-app"

# Save the token for app configuration
```

### 4. Store Initial Secrets

```bash
# Store API keys
vault kv put autonomous-opponent/api-keys/openai \
  key="sk-production-key" \
  environment="production" \
  rotation_interval="30d"

# Store database credentials
vault kv put autonomous-opponent/database \
  url="postgres://user:pass@localhost:5432/prod_db" \
  pool_size="20"

# Store encryption keys
vault kv put autonomous-opponent/encryption \
  master_key="base64_encoded_key" \
  algorithm="AES-256-GCM"
```

### 5. Enable Transit Engine (Optional)

For encryption as a service:

```bash
# Enable transit engine
vault secrets enable transit

# Create encryption key
vault write transit/keys/autonomous-opponent \
  type="aes256-gcm96" \
  derived=false \
  convergent_encryption=true
```

## Integration with Autonomous Opponent

### 1. Update Environment Variables

```bash
# .env.production
VAULT_ENABLED=true
VAULT_ADDR=https://vault.your-domain.com:8200
VAULT_TOKEN=s.your-app-token
VAULT_NAMESPACE=autonomous-opponent
VAULT_MOUNT=autonomous-opponent

# TLS settings
VAULT_CACERT=/path/to/ca.crt
VAULT_CLIENT_CERT=/path/to/client.crt
VAULT_CLIENT_KEY=/path/to/client.key
```

### 2. Configure VaultClient

The VaultClient module automatically uses these settings:

```elixir
# Verify connection in IEx
iex> VaultClient.health_check()
{:ok, %{initialized: true, sealed: false, version: "1.15.0"}}

# Test secret retrieval
iex> VaultClient.read_secret("api-keys/openai")
{:ok, %{"key" => "sk-production-key", ...}}
```

### 3. Enable Audit Logging

```bash
# Enable file audit
vault audit enable file file_path=/vault/logs/audit.log

# Enable syslog audit
vault audit enable syslog tag="vault" facility="LOCAL7"

# List audit devices
vault audit list
```

## High Availability Setup

### 1. PostgreSQL HA Backend

Configure multiple Vault instances with shared PostgreSQL:

```hcl
storage "postgresql" {
  connection_url = "postgres://vault:pass@pg-primary:5432/vault"
  ha_enabled     = true
  ha_table       = "vault_ha_locks"
  
  # Replicas for read scaling
  read_replicas = [
    "postgres://vault:pass@pg-replica1:5432/vault",
    "postgres://vault:pass@pg-replica2:5432/vault"
  ]
}
```

### 2. Load Balancer Configuration

Use HAProxy or similar:

```
frontend vault_frontend
  bind *:8200 ssl crt /etc/ssl/vault.pem
  default_backend vault_backend

backend vault_backend
  balance roundrobin
  option httpchk GET /v1/sys/health
  server vault1 vault1:8200 check ssl verify none
  server vault2 vault2:8200 check ssl verify none
  server vault3 vault3:8200 check ssl verify none
```

## Security Best Practices

### 1. Access Control

```bash
# Create separate tokens per environment
vault token create -policy=autonomous-dev -ttl=24h
vault token create -policy=autonomous-staging -ttl=168h
vault token create -policy=autonomous-prod -ttl=8760h

# Implement token renewal
vault token renew <token>
```

### 2. Secret Rotation

```bash
# Enable automatic rotation
vault write autonomous-opponent/config/api-keys/openai \
  rotation_period="30d" \
  rotation_lambda="arn:aws:lambda:..."
```

### 3. Encryption

```bash
# Always use TLS
VAULT_SKIP_VERIFY=false

# Encrypt sensitive logs
vault audit enable file \
  file_path=/vault/logs/audit.log \
  log_raw=false
```

### 4. Monitoring

Set up monitoring for:
- Unseal status
- Token expiration
- Secret access patterns
- Failed authentication attempts
- Audit log size

## Disaster Recovery

### 1. Backup Procedures

```bash
# Backup Vault data (PostgreSQL)
pg_dump -U vault -d vault > vault_backup_$(date +%Y%m%d).sql

# Backup configuration
tar -czf vault_config_$(date +%Y%m%d).tar.gz /vault/config

# Store unseal keys securely (never together!)
```

### 2. Recovery Steps

1. Restore PostgreSQL database
2. Start Vault instances
3. Unseal each instance
4. Verify replication status
5. Test secret access

### 3. Auto-Unseal (AWS KMS)

```hcl
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "alias/vault-unseal"
}
```

## Maintenance

### Regular Tasks

```bash
# Rotate root token (monthly)
vault operator generate-root

# Review audit logs
tail -f /vault/logs/audit.log | jq

# Clean up old secret versions
vault kv metadata delete autonomous-opponent/api-keys/old-key

# Update policies
vault policy write autonomous-app updated-policy.hcl
```

### Performance Tuning

```hcl
# Increase connection pool
max_parallel_connections = 128

# Enable caching
cache {
  use_auto_auth_token = true
}

# Tune PostgreSQL
max_connections = 200
shared_buffers = 256MB
```

## Troubleshooting

### Common Issues

#### "Vault is sealed"
```bash
# Check seal status
vault status

# Unseal if needed
vault operator unseal
```

#### "Permission denied"
```bash
# Check token capabilities
vault token capabilities <token> <path>

# Review policies
vault policy read autonomous-app
```

#### "Connection refused"
- Verify Vault address and port
- Check TLS certificates
- Ensure Vault is running

#### "Secret not found"
```bash
# List available secrets
vault kv list autonomous-opponent/

# Check secret path
vault kv get autonomous-opponent/api-keys/openai
```

## Integration Testing

Test Vault integration:

```elixir
# In test environment
defmodule VaultIntegrationTest do
  use ExUnit.Case
  
  test "vault connection" do
    assert {:ok, _} = VaultClient.health_check()
  end
  
  test "secret retrieval" do
    assert {:ok, secret} = VaultClient.read_secret("test/key")
    assert secret["value"] == "test_value"
  end
  
  test "secret rotation" do
    assert :ok = VaultClient.write_secret("test/rotate", %{
      value: "new_value"
    })
  end
end
```

## Next Steps

1. Review [Security Documentation](./README.md)
2. Implement [Migration Plan](./MIGRATION.md)
3. Ensure [Compliance](./COMPLIANCE.md)
4. Set up monitoring dashboards
5. Schedule disaster recovery drills