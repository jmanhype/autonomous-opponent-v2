import Config

# EventBus Cluster Configuration
# This configuration enables distributed EventBus with full VSM cybernetic principles

config :autonomous_opponent_core, AutonomousOpponentV2Core.EventBus.Cluster,
  # Enable clustering (set to false for single-node mode)
  enabled: true,

  # libcluster topology for automatic node discovery
  topology: [
    vsm_cluster: [
      # Use Gossip strategy for peer discovery
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_addr: "224.1.1.2",
        multicast_ttl: 1,
        broadcast_only: false
      ]
    ]
  ],

  # Partition detection and resolution
  # :static_quorum | :dynamic_weights | :vsm_health
  partition_strategy: :static_quorum,
  # :majority | integer
  quorum_size: :majority,
  # 5 seconds
  partition_check_interval: 5_000,

  # Variety management quotas (events per second)
  variety_quotas: %{
    # Pain/pleasure signals bypass all limits
    algedonic: :unlimited,
    # Governance decisions
    s5_policy: 50,
    # Environmental scanning
    s4_intelligence: 100,
    # Resource optimization
    s3_control: 200,
    # Anti-oscillation
    s2_coordination: 500,
    # Routine operations
    s1_operational: 1000,
    # Unclassified events
    general: 100
  },

  # Semantic compression for variety reduction
  semantic_compression: %{
    enabled: true,
    similarity_threshold: 0.8,
    # milliseconds
    aggregation_window: 100,
    max_cache_size: 10_000
  },

  # Circuit breaker configuration
  circuit_breaker: %{
    failure_threshold: 5,
    # 30 seconds
    recovery_time: 30_000,
    half_open_calls: 3
  },

  # VSM weight factors for partition resolution
  vsm_weight_factors: %{
    # Highest weight for governance
    s5_policy: 5.0,
    # Pattern recognition
    s4_intelligence: 4.0,
    # Resource management
    s3_control: 3.0,
    # Anti-oscillation
    s2_coordination: 2.0,
    # Basic operations
    s1_operational: 1.0,
    # Critical health signals
    algedonic_health: 10.0
  },

  # Event propagation settings
  # 5 minutes
  event_ttl: 300_000,
  # Maximum network hops
  max_hops: 3,

  # Discovery and health checking
  # 30 seconds
  peer_discovery_interval: 30_000,
  # 10 seconds
  health_check_interval: 10_000,
  # 1 minute
  telemetry_interval: 60_000

# Example node-specific configuration
# Override these in your environment-specific configs

if config_env() == :prod do
  config :autonomous_opponent_core, AutonomousOpponentV2Core.EventBus.Cluster,
    topology: [
      vsm_cluster: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :hostname,
          kubernetes_node_basename: "autonomous-opponent",
          kubernetes_selector: "app=autonomous-opponent",
          kubernetes_namespace: "production",
          polling_interval: 10_000
        ]
      ]
    ]
end

# Development environment - use Epmd strategy
if config_env() == :dev do
  config :autonomous_opponent_core, AutonomousOpponentV2Core.EventBus.Cluster,
    topology: [
      vsm_cluster: [
        strategy: Cluster.Strategy.Epmd,
        config: [
          hosts: [
            :vsm1@localhost,
            :vsm2@localhost,
            :vsm3@localhost
          ]
        ]
      ]
    ]
end
