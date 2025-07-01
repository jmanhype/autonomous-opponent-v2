defmodule AutonomousOpponentV2Web.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.
  """
  use Gettext.Backend, otp_app: :autonomous_opponent_web
end