# Config for autonomous_opponent_core
import Config

config :autonomous_opponent_core, 
  ecto_repos: [AutonomousOpponentV2Core.Repo]

# AMQP Configuration
config :autonomous_opponent_core,
  amqp_enabled: true,
  amqp_connection: [
    host: "localhost",
    port: 5672,
    username: "guest",
    password: "guest",
    virtual_host: "/",
    heartbeat: 30,
    connection_timeout: 10_000
  ],
  amqp_pool_size: 10,
  amqp_max_overflow: 5

# Task 7: Security - Configure Cloak encryption vault
config :autonomous_opponent_core, AutonomousOpponentV2Core.Security.Encryption,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1", 
      key: Base.decode64!(System.get_env("ENCRYPTION_KEY") || "3Jnb0hZiHIzHTOih7t2cTEPEpY98Tu1wvQkPfq/XwqE="),
      iv_length: 12
    }
  ]

# Task 8: Web Gateway Configuration
config :autonomous_opponent_core, :web_gateway,
  transports: [
    http_sse: [
      port: 4001,
      max_connections: 10_000,
      heartbeat_interval: 30_000
    ],
    websocket: [
      port: 4002,
      compression: true,
      max_frame_size: 65_536,
      ping_interval: 30_000,
      pong_timeout: 10_000
    ]
  ],
  pool: [
    size: 100,
    overflow: 50,
    strategy: :fifo,
    checkout_timeout: 5_000,
    idle_timeout: 300_000
  ],
  routing: [
    algorithm: :consistent_hash,
    vnodes: 150,
    failover_threshold: 3,
    health_check_interval: 10_000
  ],
  rate_limiting: [
    default_limit: 100,
    refill_rate: 100
  ]

# OpenTelemetry Configuration for distributed tracing
config :opentelemetry,
  resource: [
    service: [
      name: "web-gateway",
      namespace: "autonomous-opponent"
    ]
  ],
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318"),
  otlp_headers: [{"x-api-key", System.get_env("OTEL_API_KEY", "")}]

# Connection Pool Configuration
config :autonomous_opponent_core, :connection_pools,
  openai: [
    size: 50,
    max_idle_time: 5_000,
    hosts: ["https://api.openai.com"],
    health_check_url: "https://api.openai.com/v1/models",
    circuit_breaker: [
      threshold: 10,
      timeout: 60_000,
      half_open_max: 5
    ],
    conn_opts: [
      transport_opts: [
        timeout: 30_000,
        tcp: [:inet6, nodelay: true]
      ]
    ]
  ],
  anthropic: [
    size: 30,
    max_idle_time: 5_000,
    hosts: ["https://api.anthropic.com"],
    circuit_breaker: [
      threshold: 5,
      timeout: 30_000
    ]
  ],
  google_ai: [
    size: 30,
    max_idle_time: 5_000,
    hosts: ["https://generativelanguage.googleapis.com"],
    circuit_breaker: [
      threshold: 5,
      timeout: 30_000
    ]
  ],
  local_llm: [
    size: 20,
    max_idle_time: 10_000,
    hosts: ["http://localhost:11434"],
    circuit_breaker: [
      threshold: 3,
      timeout: 15_000
    ]
  ],
  vault: [
    size: 10,
    max_idle_time: 10_000,
    hosts: ["http://localhost:8200"],
    circuit_breaker: [
      threshold: 5,
      timeout: 30_000
    ]
  ],
  default: [
    size: 15,
    max_idle_time: 10_000,
    circuit_breaker: [
      threshold: 5,
      timeout: 30_000
    ]
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

