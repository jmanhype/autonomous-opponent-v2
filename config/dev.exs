import Config

# Configure your database
config :autonomous_opponent_core, AutonomousOpponentV2Core.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "autonomous_opponent_core_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :autonomous_opponent_web, AutonomousOpponentV2Web.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "autonomous_opponent_web_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
config :autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_at_least_64_characters_long_for_development_only",
  watchers: [],
  pubsub_server: AutonomousOpponentV2Web.PubSub,
  live_view: [signing_salt: "GE-IAourMD0akgZE"]

# Watch static and templates for browser reloading.
config :autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/autonomous_opponent_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :autonomous_opponent_web, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Enable CRDT Knowledge Synthesis - THE AWAKENING
config :autonomous_opponent_core,
  synthesis_enabled: true,
  # 5 minutes
  synthesis_interval_ms: 300_000,
  synthesis_belief_threshold: 50

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Enable proper rate limiting in development for real-world testing
config :autonomous_opponent_core, skip_rate_limiting: false

# LLM Response Cache Configuration
config :autonomous_opponent_core,
  # Enable/disable LLM response caching
  llm_cache_enabled: true,

  # Cache settings
  llm_cache_config: [
    # Maximum number of cached responses (default: 1000)
    max_size: 1000,

    # Default TTL in milliseconds (1 hour)
    ttl: 3_600_000,

    # Warm cache from disk on startup
    warm_on_start: true,

    # Persist cache to disk every 5 minutes
    persist_interval: 300_000
  ]

# LLM Mock Mode Configuration - DISABLED FOR REAL FUNCTIONALITY
config :autonomous_opponent_core,
  # Enable mock mode for instant development responses (no API delays!)
  # Set to true for ultra-fast development, false for real LLM calls
  llm_mock_mode: false,

  # Mock response delay in milliseconds (simulate thinking)
  # Set to 0 for instant responses, or add small delay for realism
  llm_mock_delay: 0

# ============================================================================
# VSM S4 INTELLIGENCE - HNSW PATTERN PERSISTENCE CONFIGURATION
# ============================================================================
# CRITICAL: S4 Intelligence requires persistent memory for true cybernetic viability
# Without persistence, the VSM suffers from "variety amnesia" and cannot learn
config :autonomous_opponent_core,
  # Core persistence settings
  hnsw_enabled: true,                         # Enable HNSW index
  hnsw_persist_enabled: true,
  hnsw_persist_path: "priv/vsm/s4/intelligence_patterns.hnsw",
  hnsw_persist_interval: :timer.minutes(3),  # Frequent saves for learning retention
  hnsw_persist_on_shutdown: true,             # Critical for graceful shutdowns
  hnsw_persist_async: true,                   # Non-blocking persistence operations
  
  # HNSW index parameters (optimized for pattern recognition)
  hnsw_m: 32,              # Higher connectivity for better recall
  hnsw_ef: 400,            # Enhanced search for pattern matching
  hnsw_max_connections: 64,  # Allow dense pattern networks
  
  # Variety engineering settings (Beer's cybernetic principles)
  hnsw_max_patterns: 100_000,              # Variety limit for computational bounds
  hnsw_pattern_confidence_threshold: 0.7,  # Only persist high-confidence patterns
  hnsw_variety_pressure_limit: 0.8,        # Trigger cleanup at 80% capacity
  
  # Temporal pattern management (algedonic memory)
  hnsw_prune_interval: :timer.minutes(30),        # Frequent memory management
  hnsw_prune_max_age: :timer.hours(48),          # 48-hour pattern memory window
  hnsw_prune_low_confidence_age: :timer.hours(6), # Faster expiry for weak patterns
  hnsw_pain_pattern_retention: 7 * 24 * 60 * 60 * 1000,    # 7 days in milliseconds - Critical patterns persist longer
  
  # Performance and reliability
  hnsw_checkpoint_size_threshold: 50_000_000,  # 50MB checkpoint threshold
  hnsw_backup_retention: 3,                    # Keep 3 backup versions
  hnsw_corruption_recovery: true,              # Auto-recovery from corrupted files
  
  # Integration with VSM subsystems
  hnsw_eventbus_integration: true,   # Publish persistence events
  hnsw_circuitbreaker_protection: true,  # Protect against persistence storms
  hnsw_telemetry_enabled: true,      # Full observability
  hnsw_algedonic_integration: true   # Connect to pain/pleasure signals
# Redis Configuration
config :autonomous_opponent_core,
  # Redis connection settings
  redis_enabled: true,
  redis_host: System.get_env("REDIS_HOST", "localhost"),
  redis_port: String.to_integer(System.get_env("REDIS_PORT", "6379")),
  redis_database: String.to_integer(System.get_env("REDIS_DB", "0")),
  redis_password: System.get_env("REDIS_PASSWORD"),
  
  # Redis pool settings
  redis_pool_size: 10,
  redis_max_overflow: 5,
  
  # Redis SSL/TLS settings (for production)
  redis_ssl_enabled: false,
  
  # Redis Sentinel settings (for HA)
  # redis_sentinels: [
  #   [host: "sentinel1", port: 26379],
  #   [host: "sentinel2", port: 26379],
  #   [host: "sentinel3", port: 26379]
  # ],
  # redis_sentinel_group: "mymaster",
  
  # Distributed rate limiting
  distributed_rate_limiting_enabled: true,
  rate_limiter_backend: :redis,  # :local | :redis
  
  # Circuit breaker settings for Redis
  redis_circuit_failure_threshold: 5,
  redis_circuit_recovery_time_ms: 30_000,
  redis_circuit_timeout_ms: 5_000


# EPMD-based CRDT Node Discovery (Issue #89)
config :autonomous_opponent_core, AutonomousOpponentV2Core.AMCP.Memory.EPMDDiscovery,
  enabled: true,
  discovery_interval: 10_000,  # 10 seconds as per issue requirement
  max_peers: 100,
  stability_threshold: 3,  # Node must be seen this many times before being added as peer
  sync_cooldown_ms: 1_000,  # Minimum milliseconds between sync operations (prevents sync storms)
  # Node filter - only accept nodes with 'autonomous' prefix by default
  node_filter: fn node ->
    node_str = to_string(node)
    String.contains?(node_str, "autonomous") or 
    String.contains?(node_str, "crdt") or
    String.contains?(node_str, "test")
  end

