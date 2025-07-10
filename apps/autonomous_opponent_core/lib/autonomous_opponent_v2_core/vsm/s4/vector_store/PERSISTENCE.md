# HNSW Index Persistence

## Overview

The HNSW (Hierarchical Navigable Small World) index now supports automatic persistence to disk using ETS table serialization. This ensures that S4's pattern memory survives process restarts and system reboots.

## Features

### Automatic Persistence
- **Periodic Saves**: Configurable interval (default: 5 minutes)
- **Graceful Shutdown**: Saves on normal termination
- **Atomic Writes**: Uses temp file + rename pattern
- **Version Migration**: Handles format upgrades

### Memory Management
- **Efficient Serialization**: Direct ETS table dumps
- **No Memory Spikes**: Streaming writes to disk
- **Concurrent Operations**: Non-blocking persistence
- **Crash Recovery**: Automatic restoration on startup

### OTP Integration
- **Supervised Process**: Part of S4 supervision tree
- **Timer Management**: Automatic cleanup on termination
- **Error Isolation**: Persistence failures don't crash the index
- **Hot Code Upgrades**: State preserved across upgrades

## Configuration

### Basic Setup

```elixir
# config/runtime.exs
config :autonomous_opponent_core,
  hnsw_persist_enabled: true,
  hnsw_persist_path: "priv/vector_store/hnsw_index",
  hnsw_persist_interval: :timer.minutes(5)
```

### Advanced Options

```elixir
config :autonomous_opponent_core,
  # Persistence settings
  hnsw_persist_enabled: true,
  hnsw_persist_path: System.get_env("HNSW_PERSIST_PATH", "priv/vector_store/hnsw_index"),
  hnsw_persist_interval: :timer.minutes(5),
  
  # Index parameters
  hnsw_m: 16,                    # Connectivity parameter
  hnsw_ef: 200,                  # Search beam width
  
  # Pattern expiry
  hnsw_prune_interval: :timer.hours(1),
  hnsw_prune_max_age: :timer.hours(24)
```

## Usage Examples

### Direct API Usage

```elixir
# Start index with persistence
{:ok, index} = HNSWIndex.start_link(
  persist_path: "priv/my_index",
  persist_interval: :timer.minutes(1)
)

# Manual persistence
:ok = HNSWIndex.persist(index)

# Check persistence status
{:ok, info} = Persistence.index_info("priv/my_index")
%{
  version: 2,
  node_count: 1000,
  saved_at: ~U[2024-01-10 10:00:00Z],
  parameters: %{m: 16, ef: 200, distance_metric: :cosine}
}
```

### Integration with S4

```elixir
# S4 Intelligence automatically configures persistence
{:ok, _} = AutonomousOpponentV2Core.VSM.S4.Intelligence.start_link()

# Vector store inherits configuration
VectorStore.store_pattern(pattern, %{source: "environmental_scan"})
```

## Performance Considerations

### Persistence Overhead
- **Save Time**: ~50ms per 10,000 nodes
- **Load Time**: ~100ms per 10,000 nodes
- **Disk Space**: ~100 bytes per node + metadata

### Optimization Tips

1. **Interval Tuning**: Balance between data safety and I/O load
   ```elixir
   # Development: Frequent saves
   persist_interval: :timer.seconds(30)
   
   # Production: Less frequent
   persist_interval: :timer.minutes(10)
   ```

2. **Disk Location**: Use SSD for better performance
   ```elixir
   persist_path: "/mnt/ssd/hnsw_index"
   ```

3. **Compaction**: Periodic compaction reduces file size
   ```elixir
   HNSWIndex.compact(index)
   ```

## Deployment Guidelines

### Docker Configuration

```yaml
# docker-compose.yml
services:
  app:
    volumes:
      - hnsw_data:/app/priv/vector_store
    environment:
      - HNSW_PERSIST_PATH=/app/priv/vector_store/hnsw_index
      - HNSW_PERSIST_INTERVAL=300000  # 5 minutes

volumes:
  hnsw_data:
```

### Kubernetes PersistentVolume

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hnsw-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: autonomous-opponent
        volumeMounts:
        - name: hnsw-storage
          mountPath: /app/priv/vector_store
      volumes:
      - name: hnsw-storage
        persistentVolumeClaim:
          claimName: hnsw-storage
```

## Monitoring

### Telemetry Events

The persistence system emits telemetry events for monitoring:

```elixir
# Attach to persistence events
:telemetry.attach(
  "hnsw-persistence",
  [:hnsw, :persist],
  fn _event, measurements, metadata, _config ->
    Logger.info("HNSW persisted: #{measurements.duration}μs, #{metadata.node_count} nodes")
  end,
  nil
)
```

### Health Checks

```elixir
defmodule HNSWHealthCheck do
  def check_persistence do
    path = Application.get_env(:autonomous_opponent_core, :hnsw_persist_path)
    
    case Persistence.index_info(path) do
      {:ok, info} ->
        age = DateTime.diff(DateTime.utc_now(), info.saved_at, :second)
        if age > 600 do  # 10 minutes
          {:error, "Index not persisted recently"}
        else
          {:ok, "Index persisted #{age}s ago"}
        end
      
      {:error, _} ->
        {:error, "No persisted index found"}
    end
  end
end
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Fix permissions
   chmod -R 755 priv/vector_store
   chown -R app:app priv/vector_store
   ```

2. **Disk Full**
   ```elixir
   # Monitor disk usage
   {_, 0} = System.cmd("df", ["-h", "/app/priv/vector_store"])
   ```

3. **Corrupted Files**
   ```elixir
   # Clean and restart
   Persistence.delete_index("priv/vector_store/hnsw_index")
   ```

### Recovery Procedures

```elixir
# Manual recovery from backup
backup_path = "backups/hnsw_index_20240110"
{:ok, state} = Persistence.load_index(backup_path)

# Rebuild from raw data
HNSWIndex.compact(index)  # Removes orphaned nodes
HNSWIndex.persist(index)  # Save clean state
```

## Future Enhancements

1. **Incremental Persistence**: Only save changes since last persist
2. **Compression**: Zstd compression for smaller files
3. **Replication**: Multi-node persistence for HA
4. **S3 Backend**: Cloud storage integration