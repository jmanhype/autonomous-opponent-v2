defmodule AutonomousOpponentV2Core do
  @moduledoc """
  The public API for the Autonomous Opponent V2 Core application.
  This module defines the contracts for interaction with the core cybernetic systems.
  """

  @callback submit_user_input(session_id :: String.t(), text :: String.t()) :: {:ok, String.t()} | {:error, any()}
  @callback subscribe_to_updates(session_id :: String.t(), pid :: pid()) :: :ok

  # Placeholder for initial implementation
  def submit_user_input(_session_id, _text) do
    {:ok, "Core received input (placeholder)"}
  end

  def subscribe_to_updates(_session_id, _pid) do
    :ok
  end
end
