defmodule AutonomousOpponentV2Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :autonomous_opponent_web

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set this key in config/dev.exs
  @session_options [
    store: :cookie,
    key: "_autonomous_opponent_v2_web_key",
    signing_salt: "aBcDeFgH",
    same_site: "Lax"
  ]

  # Live reload socket
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
  end

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
  
  # Web Gateway WebSocket endpoint
  socket "/web-gateway/ws", AutonomousOpponentV2Web.WebGatewaySocket,
    websocket: [
      compress: true,
      max_frame_size: 65_536,
      timeout: 60_000
    ],
    longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :autonomous_opponent_web,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

  # Code reloading can be explicitly enabled by placing
  # the following in your config/dev.exs file and
  # setting `code_reloader: true`.
  if Application.compile_env(:autonomous_opponent_web, :code_reloader) do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :autonomous_opponent_web
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix_endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head

  plug Plug.Session, @session_options
  plug AutonomousOpponentV2Web.Router
end
