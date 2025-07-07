defmodule AutonomousOpponentV2Web.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.
  
  This module is used by API controllers to handle common error cases
  and ensure JSON error responses instead of HTML.
  """
  use AutonomousOpponentV2Web, :controller

  # This clause handles errors returned by Ecto's insert/update/delete
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: AutonomousOpponentV2Web.ErrorJSON)
    |> render("422.json", changeset: changeset)
  end

  # This clause is an example of how to handle resources that cannot be found.
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: AutonomousOpponentV2Web.ErrorJSON)
    |> render("404.json")
  end

  # This clause handles unauthorized access
  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: AutonomousOpponentV2Web.ErrorJSON)
    |> render("401.json")
  end

  # This clause handles forbidden access
  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: AutonomousOpponentV2Web.ErrorJSON)
    |> render("403.json")
  end

  # This clause handles bad request errors
  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: AutonomousOpponentV2Web.ErrorJSON)
    |> render("400.json")
  end

  # Generic error handler
  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: reason}})
  end

  # Catch-all clause
  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> put_view(json: AutonomousOpponentV2Web.ErrorJSON)
    |> render("500.json")
  end
end