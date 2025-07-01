defmodule AutonomousOpponentV2Web.ErrorHTML do
  # In case you want to customize your error pages,
  # you can define a view to render them.
  use AutonomousOpponentV2Web, :html

  # By default, Phoenix uses the template `lib/autonomous_opponent_v2_web/controllers/error_html/404.html.heex`
  # for 404 errors and `lib/autonomous_opponent_v2_web/controllers/error_html/500.html.heex` for 500 errors.
  # If you don't want to show a stacktrace on 500 errors, you can put the following
  # inside your `config/prod.exs`:
  #
  #     config :autonomous_opponent_v2, AutonomousOpponentV2Web.Endpoint,
  #       render_errors: [view: AutonomousOpponentV2Web.ErrorView, accepts: ~w(html), layout: false]
  #
  # If you want to customize 404 errors, you can change the `render_errors`
  # configuration to something like this:
  #
  #     config :autonomous_opponent_v2, AutonomousOpponentV2Web.Endpoint,
  #       render_errors: [view: AutonomousOpponentV2Web.ErrorView, accepts: ~w(html), layout: false],
  #       code_reloader: true,
  #       debug_errors: true,
  #       check_origin: false
  #
  # It is also possible to define your own exceptions that will act as templates.
  # For example, to define a `NotAuthorizedError`, you could do:
  #
  #     defmodule AutonomousOpponentV2Web.NotAuthorizedError do
  #       defexception message: "You are not authorized to access this page."
  #     end
  #
  # Then you can add a new clause to the `render` function in this module:
  #
  #     def render("403.html", %{conn: conn, assigns: %{reason: %NotAuthorizedError{}}}) do
  #       # your custom 403 page
  #     end
  #
  embed_templates "controllers/error_html/*"
end
