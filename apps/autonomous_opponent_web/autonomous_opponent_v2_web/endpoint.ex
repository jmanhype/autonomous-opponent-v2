defmodule AutonomousOpponentV2Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :autonomous_opponent_v2

  @session_options [
    store: :cookie,
    key: "_autonomous_opponent_v2_key",
    signing_salt: "aBcDeFgH",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  socket("/system", AutonomousOpponentV2Web.SystemEventSocket,
    websocket: true,
    longpoll: false
  )

  plug(Plug.Static,
    at: "/",
    from: :autonomous_opponent_v2,
    gzip: true,
    only: AutonomousOpponentV2Web.static_paths(),
    cache_control_for_etags: "public, max-age=31536000",
    cache_control_for_vsn_requests: "public, max-age=31536000"
  )

  if Application.compile_env(:autonomous_opponent_v2, :code_reloader) do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(AutonomousOpponentV2Web.Router)
end
