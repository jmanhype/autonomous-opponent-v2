import Config

# Production database configuration
config :autonomous_opponent_core, AutonomousOpponentV2Core.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true

# Production AMQP configuration
config :autonomous_opponent_core,
  amqp_enabled: System.get_env("AMQP_ENABLED", "true") == "true",
  amqp_connection: System.get_env("AMQP_URL") || [
    host: System.get_env("AMQP_HOST", "localhost"),
    port: String.to_integer(System.get_env("AMQP_PORT", "5672")),
    username: System.get_env("AMQP_USERNAME", "guest"),
    password: System.get_env("AMQP_PASSWORD", "guest"),
    virtual_host: System.get_env("AMQP_VHOST", "/"),
    heartbeat: 30,
    connection_timeout: 10_000
  ],
  amqp_pool_size: String.to_integer(System.get_env("AMQP_POOL_SIZE", "20")),
  amqp_max_overflow: String.to_integer(System.get_env("AMQP_MAX_OVERFLOW", "10"))

# Production connection pool configuration
# Massive pools for handling traffic at scale!
config :autonomous_opponent_core, :connection_pools,
  openai: [
    size: String.to_integer(System.get_env("OPENAI_POOL_SIZE", "100")),
    max_idle_time: 5_000,
    hosts: ["https://api.openai.com"],
    health_check_url: "https://api.openai.com/v1/models",
    circuit_breaker: [
      threshold: 20,
      timeout: 60_000,
      half_open_max: 10
    ],
    conn_opts: [
      transport_opts: [
        timeout: 30_000,
        tcp: [:inet6, nodelay: true],
        # SSL options for production
        ssl: [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          depth: 3,
          reuse_sessions: true
        ]
      ]
    ]
  ],
  anthropic: [
    size: String.to_integer(System.get_env("ANTHROPIC_POOL_SIZE", "50")),
    max_idle_time: 5_000,
    hosts: ["https://api.anthropic.com"],
    circuit_breaker: [
      threshold: 10,
      timeout: 30_000
    ]
  ],
  google_ai: [
    size: String.to_integer(System.get_env("GOOGLE_AI_POOL_SIZE", "50")),
    max_idle_time: 5_000,
    hosts: ["https://generativelanguage.googleapis.com"],
    circuit_breaker: [
      threshold: 10,
      timeout: 30_000
    ]
  ],
  local_llm: [
    size: String.to_integer(System.get_env("LOCAL_LLM_POOL_SIZE", "30")),
    max_idle_time: 10_000,
    hosts: [System.get_env("LOCAL_LLM_URL", "http://localhost:11434")],
    circuit_breaker: [
      threshold: 5,
      timeout: 15_000
    ]
  ],
  vault: [
    size: String.to_integer(System.get_env("VAULT_POOL_SIZE", "20")),
    max_idle_time: 10_000,
    hosts: [System.get_env("VAULT_ADDR", "http://localhost:8200")],
    circuit_breaker: [
      threshold: 10,
      timeout: 30_000
    ]
  ],
  default: [
    size: String.to_integer(System.get_env("DEFAULT_POOL_SIZE", "30")),
    max_idle_time: 10_000,
    circuit_breaker: [
      threshold: 10,
      timeout: 30_000
    ]
  ]

# Production logging - less verbose
config :logger, level: :info

# Don't forget to configure your encryption key in production!
config :autonomous_opponent_core, AutonomousOpponentV2Core.Security.Encryption,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1", 
      key: Base.decode64!(System.fetch_env!("ENCRYPTION_KEY")),
      iv_length: 12
    }
  ]