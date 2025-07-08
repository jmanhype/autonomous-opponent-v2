import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Load environment variables from .env file if it exists and we're in dev
if config_env() == :dev and File.exists?(".env") do
  # Manual parsing since DotenvParser may not be available at runtime
  File.read!(".env")
  |> String.split("\n")
  |> Enum.reject(&(String.starts_with?(&1, "#") or String.trim(&1) == ""))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        System.put_env(String.trim(key), String.trim(value))

      _ ->
        :ok
    end
  end)
end

# Task 7: Security Hardening - Configure secure environment handling
config :autonomous_opponent_core, :security,
  vault_enabled: System.get_env("VAULT_ENABLED") == "true",
  vault_address: System.get_env("VAULT_ADDR"),
  vault_token: System.get_env("VAULT_TOKEN"),
  encryption_key: System.get_env("ENCRYPTION_KEY"),
  allowed_env_keys: [
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "GOOGLE_AI_API_KEY",
    "DATABASE_URL",
    "SECRET_KEY_BASE",
    "GUARDIAN_SECRET",
    "AMQP_URL"
  ]

# Configure sensitive data exposure
config :logger,
  filter_parameters: ["password", "secret", "token", "key", "api_key"]

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/autonomous_opponent start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint, server: true
end

# Configure databases from environment variables
# This applies to all environments including test
if database_url = System.get_env("AUTONOMOUS_OPPONENT_CORE_DATABASE_URL") do
  pool_opts = if config_env() == :test, do: [pool: Ecto.Adapters.SQL.Sandbox], else: []

  config :autonomous_opponent_core,
         AutonomousOpponentV2Core.Repo,
         Keyword.merge(
           [
             url: database_url,
             pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
             # Task 7: Security Hardening - Disable sensitive data exposure
             stacktrace: true,
             show_sensitive_data_on_connection_error: false
           ],
           pool_opts
         )
end

if database_url = System.get_env("AUTONOMOUS_OPPONENT_V2_DATABASE_URL") do
  pool_opts = if config_env() == :test, do: [pool: Ecto.Adapters.SQL.Sandbox], else: []

  config :autonomous_opponent_web,
         AutonomousOpponentV2Web.Repo,
         Keyword.merge(
           [
             url: database_url,
             pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
             # Task 7: Security Hardening - Disable sensitive data exposure
             stacktrace: true,
             show_sensitive_data_on_connection_error: false
           ],
           pool_opts
         )
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :autonomous_opponent_core, AutonomousOpponentV2Core.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  config :autonomous_opponent_web, AutonomousOpponentV2Web.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support with TLS 1.3 (Task 7: Security Hardening)

  # Enable TLS 1.3 for enhanced security
  if System.get_env("TLS_ENABLED") == "true" do
    config :autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint,
      https: [
        port: String.to_integer(System.get_env("TLS_PORT") || "443"),
        cipher_suite: :strong,
        keyfile: System.get_env("TLS_KEY_PATH"),
        certfile: System.get_env("TLS_CERT_PATH"),
        # TLS 1.3 configuration
        versions: [:"tlsv1.3", :"tlsv1.2"],
        # Modern cipher suites only
        ciphers: [
          "TLS_AES_256_GCM_SHA384",
          "TLS_AES_128_GCM_SHA256",
          "TLS_CHACHA20_POLY1305_SHA256",
          "TLS_AES_128_CCM_SHA256",
          "TLS_AES_128_CCM_8_SHA256"
        ],
        secure_renegotiate: true,
        reuse_sessions: true,
        honor_cipher_order: true
      ],
      force_ssl: [
        hsts: true,
        rewrite_on: [:x_forwarded_proto],
        subdomains: true,
        preload: true
      ]
  end

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :autonomous_opponent_v2, AutonomousOpponent.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
