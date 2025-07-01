import Config

# Note we don't include the `selfsigned.key` and `selfsigned.pem`
# files in production. You will need to provide your own certificates
# and point to them in your configuration.
#
# The `cipher_suite` is set to `:strong` to support only the most secure
# cipher suites available. This option requires OTP 27.
config :autonomous_opponent_v2, AutonomousOpponentV2Web.Endpoint,
  # url: [host: "example.com", port: 443],
  # cache_static_manifest: "priv/static/cache_manifest.json",
  # http: [
  #   port: 4000,
  #   transport_options: [
  #     cipher_suite: :strong,
  #     keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #     certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #   ]
  # ]
  check_origin: false

# ## Using releases
#
# If you are doing OTP releases, you need to instruct Phoenix
# to start each relevant endpoint explicitly. You can do so
# by adding the following entries to your config/runtime.exs:
#
#     config :autonomous_opponent_v2, AutonomousOpponentV2Web.Endpoint, server: true
#
# Then you can assemble a release by calling `mix release`.
# See `mix help release` for more information.

# Finally import the config/runtime.exs which loads secrets
# and configuration from environment variables.
import_config "runtime.exs"
